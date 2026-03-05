// lib/core/ai/gemini_model_manager.dart

import 'package:shared_preferences/shared_preferences.dart';

class GeminiModelManager {
  static const List<String> _models = [
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-2.0-flash-lite',
  ];

  static const String _prefKey = 'current_model_index';
  static const String _cooldownPrefix = 'model_cooldown_';

  static Future<String> getCurrentModel() async {
    final prefs = await SharedPreferences.getInstance();

    for (int i = 0; i < _models.length; i++) {
      final model = _models[i];
      if (!await _isInCooldown(model, prefs)) {
        await prefs.setInt(_prefKey, i);
        return model;
      }
    }

    return _models.last;
  }

  static Future<String> onQuotaExceeded(
    String failedModel,
    int retryAfterSeconds,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final effectiveCooldown = retryAfterSeconds > 600
        ? 21600
        : retryAfterSeconds + 5;

    final cooldownUntil = DateTime.now()
        .add(Duration(seconds: effectiveCooldown))
        .millisecondsSinceEpoch;

    await prefs.setInt('$_cooldownPrefix$failedModel', cooldownUntil);

    for (final model in _models) {
      if (model != failedModel && !await _isInCooldown(model, prefs)) {
        return model;
      }
    }

    return failedModel;
  }

  static Future<bool> _isInCooldown(
    String model,
    SharedPreferences prefs,
  ) async {
    final cooldownUntil = prefs.getInt('$_cooldownPrefix$model') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now < cooldownUntil) {
      return true;
    }

    return false;
  }

  static Future<int> getCooldownRemaining(String model) async {
    final prefs = await SharedPreferences.getInstance();
    final cooldownUntil = prefs.getInt('$_cooldownPrefix$model') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((cooldownUntil - now) / 1000).ceil();
    return remaining > 0 ? remaining : 0;
  }

  static Future<Map<String, dynamic>> getAllModelStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> status = {};

    for (final model in _models) {
      final inCooldown = await _isInCooldown(model, prefs);
      final remaining = await getCooldownRemaining(model);
      status[model] = {
        'available': !inCooldown,
        'cooldown_remaining_seconds': remaining,
      };
    }

    return status;
  }

  static Future<void> resetAllCooldowns() async {
    final prefs = await SharedPreferences.getInstance();
    for (final model in _models) {
      await prefs.remove('$_cooldownPrefix$model');
    }
    await prefs.remove('model_cooldown_gemini-1.5-flash');
    await prefs.remove('model_cooldown_gemini-2.0-flash');
  }

  static int parseRetrySeconds(String errorMessage) {
    final match = RegExp(r'retry in (\d+)').firstMatch(errorMessage);
    return int.tryParse(match?.group(1) ?? '60') ?? 60;
  }

  static bool isModelUnavailable(String errorMessage) {
    return errorMessage.contains('limit: 0') ||
        errorMessage.contains('not found') ||
        errorMessage.contains('not supported') ||
        errorMessage.contains('PERMISSION_DENIED');
  }
}
