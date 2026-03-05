import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/tools/tool_executor.dart';
import '../../../core/tools/tool_registry.dart';
import '../../../core/ai/gemini_model_manager.dart';

abstract class AIRemoteDataSource {
  Future<String> getAIResponse(String query);
  Future<String> getAIResponseWithImage(String query, File imageFile);
  void resetSession();
}

class AIRemoteDataSourceImpl implements AIRemoteDataSource {
  ChatSession? _chatSession;
  String? _currentModelName;

  static List<String>? _cachedVisionModels;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(hours: 1);

  final Map<String, DateTime> _modelCooldowns = {};

  AIRemoteDataSourceImpl();

  static String _buildSystemPrompt() {
    final now = DateTime.now();
    final weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final weekday = weekdays[now.weekday - 1];
    final month = months[now.month - 1];
    final day = now.day;
    final year = now.year;
    final hour12 = now.hour == 0
        ? 12
        : now.hour > 12
        ? now.hour - 12
        : now.hour;
    final minute = now.minute.toString().padLeft(2, '0');
    final amPm = now.hour < 12 ? 'AM' : 'PM';
    final dateTimeStr = '$weekday, $month $day, $year at $hour12:$minute $amPm';

    return '''
You are a helpful AI voice assistant built into a Flutter app.

📅 Current date and time: $dateTimeStr

You can perform real device actions like:
- Checking weather
- Setting alarms and reminders
- Making phone calls (by contact name OR direct phone number)
- Toggling the flashlight
- Opening web searches
- Telling the current time and date

When the user asks you to perform an action, use the appropriate tool.
Always respond in a friendly, concise, conversational tone.
If a tool call succeeds, confirm it naturally to the user.
If a tool call fails, apologize and explain what went wrong.
When asked for the time or date, use the current date and time provided above.

When analyzing images:
- Extract text, numbers, URLs, or other actionable information
- If you see a phone number in the image and user asks to call it, use the phone_call tool with the number
- If user mentions a contact name, use make_call tool with the contact name
- For URLs, use open_web_search tool
''';
  }

  GenerativeModel _buildModel(String modelName) {
    final apiKey = AppConstants.geminiApiKey;
    if (apiKey.isEmpty) throw Exception('Gemini API key is empty.');
    return GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      tools: ToolRegistry.getTools(),
      systemInstruction: Content.system(_buildSystemPrompt()),
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 800,
      ),
    );
  }

  Future<ChatSession> _getOrCreateSession(String modelName) async {
    if (_chatSession == null || _currentModelName != modelName) {
      _currentModelName = modelName;
      _chatSession = _buildModel(modelName).startChat();
    }
    return _chatSession!;
  }

  Future<List<String>> _getAvailableVisionModels() async {
    if (_cachedVisionModels != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedVisionModels!;
    }

    try {
      final apiKey = AppConstants.geminiApiKey;
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = data['models'] as List;

        final visionModels = <String>[];
        for (final model in models) {
          final name = model['name'] as String;
          final supportedMethods = model['supportedGenerationMethods'] as List?;

          if (supportedMethods != null &&
              supportedMethods.contains('generateContent')) {
            final modelName = name.replaceFirst('models/', '');

            if (modelName.startsWith('gemini-') &&
                _isVisionCapable(modelName)) {
              visionModels.add(modelName);
            }
          }
        }

        if (visionModels.isEmpty) {
          return [
            'gemini-2.5-flash',
            'gemini-2.0-flash',
            'gemini-flash-latest',
          ];
        }

        visionModels.sort((a, b) {
          if (a.contains('2.5-flash') && !b.contains('2.5-flash')) return -1;
          if (!a.contains('2.5-flash') && b.contains('2.5-flash')) return 1;
          if (a.contains('2.5')) return -1;
          if (b.contains('2.5')) return 1;
          if (a.contains('2.0')) return -1;
          if (b.contains('2.0')) return 1;
          if (a.contains('flash')) return -1;
          if (b.contains('flash')) return 1;
          return 0;
        });

        _cachedVisionModels = visionModels;
        _cacheTime = DateTime.now();

        return visionModels;
      } else {
        return ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-flash-latest'];
      }
    } catch (e) {
      return ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-flash-latest'];
    }
  }

  bool _isVisionCapable(String modelName) {
    if (modelName.contains('-tts')) {
      return false;
    }

    if (modelName.contains('computer-use')) {
      return false;
    }

    if (modelName.contains('robotics')) {
      return false;
    }

    if (modelName.contains('-lite')) {
      return false;
    }

    if (modelName.contains('-exp') && !modelName.contains('flash-exp')) {
      return false;
    }

    if (modelName.contains('flash') || modelName.contains('pro')) {
      return true;
    }

    return false;
  }

  @override
  Future<String> getAIResponse(String query) async {
    const maxModelSwitches = 3;
    int modelAttempts = 0;

    while (modelAttempts < maxModelSwitches) {
      final modelName = await GeminiModelManager.getCurrentModel();
      try {
        final session = await _getOrCreateSession(modelName);
        var response = await session.sendMessage(Content.text(query));
        int loopCount = 0;
        const maxLoops = 5;

        while (response.functionCalls.isNotEmpty && loopCount < maxLoops) {
          loopCount++;
          for (final functionCall in response.functionCalls) {
            final toolResult = await ToolExecutor.execute(
              functionCall.name,
              functionCall.args,
            );
            response = await session.sendMessage(
              Content.functionResponse(functionCall.name, toolResult),
            );
          }
        }

        final finalText = response.text;
        if (finalText == null || finalText.trim().isEmpty) {
          return 'Action completed successfully.';
        }
        return finalText;
      } on GenerativeAIException catch (e) {
        if (_isQuotaError(e.message)) {
          final retrySeconds = GeminiModelManager.parseRetrySeconds(e.message);
          final nextModel = await GeminiModelManager.onQuotaExceeded(
            modelName,
            retrySeconds,
          );
          if (nextModel == modelName) {
            return '⚠️ All AI models are currently busy. Please try again in a minute!';
          }
          modelAttempts++;
          continue;
        }
        if (_isModelNotFoundError(e.message)) {
          await GeminiModelManager.onQuotaExceeded(modelName, 21600);
          modelAttempts++;
          continue;
        }
        if (e.message.contains('thought_signature')) {
          await GeminiModelManager.onQuotaExceeded(modelName, 21600);
          modelAttempts++;
          continue;
        }
        throw Exception('Gemini API error: ${e.message}');
      } catch (e) {
        throw Exception('Failed to get AI response: $e');
      }
    }
    return '⚠️ Service temporarily unavailable. Please try again shortly.';
  }

  @override
  Future<String> getAIResponseWithImage(String query, File imageFile) async {
    final visionModels = await _getAvailableVisionModels();

    for (int i = 0; i < visionModels.length && i < 5; i++) {
      final modelName = visionModels[i];

      final cooldownUntil = _modelCooldowns[modelName];
      if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil)) {
        continue;
      }

      try {
        final imageBytes = await imageFile.readAsBytes();

        final response = await _callVisionWithTools(
          modelName: modelName,
          prompt: query,
          imageBytes: imageBytes,
        );

        if (response.isEmpty) {
          return 'I can see the image but could not generate a response.';
        }

        _modelCooldowns.remove(modelName);
        return response;
      } catch (e) {
        final errorMsg = e.toString();

        if (errorMsg.contains('404') || errorMsg.contains('not found')) {
          _modelCooldowns[modelName] = DateTime.now().add(
            const Duration(hours: 1),
          );
          continue;
        }

        if (errorMsg.contains('429') ||
            errorMsg.contains('quota') ||
            errorMsg.contains('RESOURCE_EXHAUSTED')) {
          final retrySeconds = _parseRetrySecondsFromError(errorMsg);
          _modelCooldowns[modelName] = DateTime.now().add(
            Duration(seconds: retrySeconds + 2),
          );
          continue;
        }

        if (e.toString().contains('quota') ||
            e.toString().contains('RESOURCE_EXHAUSTED')) {
          final retrySeconds = _parseRetrySecondsFromError(e.toString());
          _modelCooldowns[modelName] = DateTime.now().add(
            Duration(seconds: retrySeconds + 2),
          );
        }

        _modelCooldowns[modelName] = DateTime.now().add(
          const Duration(minutes: 5),
        );
        continue;
      }
    }

    return '⚠️ Vision service temporarily unavailable. Please try again shortly.';
  }

  Future<String> _callVisionWithTools({
    required String modelName,
    required String prompt,
    required List<int> imageBytes,
  }) async {
    DateTime _toolStartTime = DateTime.now();
    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: AppConstants.geminiApiKey,
        tools: ToolRegistry.getTools(),
        systemInstruction: Content.system(_buildSystemPrompt()),
        generationConfig: GenerationConfig(
          temperature: 0.7,
          maxOutputTokens: 2048,
        ),
      );

      final initialContent = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', Uint8List.fromList(imageBytes)),
        ]),
      ];

      var response = await model.generateContent(initialContent);

      int loopCount = 0;
      const maxLoops = 5;

      while (response.functionCalls.isNotEmpty && loopCount < maxLoops) {
        loopCount++;

        final functionResponseParts = <Part>[];

        for (final functionCall in response.functionCalls) {
          final toolResult = await ToolExecutor.execute(
            functionCall.name,
            functionCall.args,
          );

          functionResponseParts.add(
            FunctionResponse(functionCall.name, toolResult),
          );
        }

        Future<void> ensureAppIsActive() async {
          var currentState = WidgetsBinding.instance.lifecycleState;

          if (currentState == AppLifecycleState.inactive) {
            final completer = Completer<void>();
            final observer = _AppLifecycleObserver(completer);
            WidgetsBinding.instance.addObserver(observer);

            try {
              await completer.future.timeout(
                const Duration(seconds: 2),
                onTimeout: () {
                  if (!completer.isCompleted) {
                    completer.complete();
                  }
                },
              );
            } finally {
              WidgetsBinding.instance.removeObserver(observer);
            }
          }
        }

        try {
          final connectivityResult = await Connectivity().checkConnectivity();

          final currentState = WidgetsBinding.instance.lifecycleState;

          if (currentState == AppLifecycleState.inactive) {
            return 'Call initiated successfully!';
          }

          response = await model.generateContent([
            Content.model(functionResponseParts),
          ]);
        } catch (e) {
          rethrow;
        }
      }

      final text = response.text;

      if (text == null || text.trim().isEmpty) {
        return 'Action completed successfully.';
      }

      return text;
    } catch (e) {
      rethrow;
    }
  }

  int _parseRetrySecondsFromError(String error) {
    final match = RegExp(r'retry in (\d+)').firstMatch(error);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '60') ?? 60;
    }

    final match2 = RegExp(r'retry in ([\d.]+)s').firstMatch(error);
    if (match2 != null) {
      final seconds = double.tryParse(match2.group(1) ?? '60') ?? 60;
      return seconds.ceil();
    }

    return 60;
  }

  bool _isQuotaError(String error) {
    return error.contains('quota') ||
        error.contains('429') ||
        error.contains('RESOURCE_EXHAUSTED') ||
        error.contains('exceeded') ||
        error.contains('rate limit');
  }

  bool _isModelNotFoundError(String error) {
    return error.contains('not found') ||
        error.contains('is not supported') ||
        error.contains('ListModels');
  }

  @override
  void resetSession() {
    _chatSession = null;
    _currentModelName = null;
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final Completer<void> completer;

  _AppLifecycleObserver(this.completer);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}
