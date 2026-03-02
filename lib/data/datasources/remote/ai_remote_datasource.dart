import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';

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
- Making phone calls
- Toggling the flashlight
- Opening web searches
- Telling the current time and date

When the user asks you to perform an action, use the appropriate tool.
Always respond in a friendly, concise, conversational tone.
If a tool call succeeds, confirm it naturally to the user.
If a tool call fails, apologize and explain what went wrong.
When asked for the time or date, use the current date and time provided above.
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
      if (_currentModelName != null && _currentModelName != modelName) {
        print('🔀 [Session] Model changed: $_currentModelName → $modelName');
      }
      _currentModelName = modelName;
      _chatSession = _buildModel(modelName).startChat();
      print('✅ [Session] New session started with: $modelName');
    }
    return _chatSession!;
  }

  /// ✅ Get vision models from API (using full model name, not baseModelId)
  Future<List<String>> _getAvailableVisionModels() async {
    if (_cachedVisionModels != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      print('📦 Using cached vision models: $_cachedVisionModels');
      return _cachedVisionModels!;
    }

    try {
      final apiKey = AppConstants.geminiApiKey;
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
      );

      print('🔍 Fetching available vision models...');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = data['models'] as List;

        final visionModels = <String>[];
        for (final model in models) {
          final name =
              model['name'] as String; // e.g., "models/gemini-2.5-flash"
          final supportedMethods = model['supportedGenerationMethods'] as List?;

          // Check if supports generateContent (vision capability)
          if (supportedMethods != null &&
              supportedMethods.contains('generateContent')) {
            // Extract model name without "models/" prefix
            final modelName = name.replaceFirst('models/', '');

            // Only add Gemini models (not Gemma, Imagen, Veo, etc.)
            if (modelName.startsWith('gemini-')) {
              visionModels.add(modelName);
              print('✅ Found vision model: $modelName');
            }
          }
        }

        if (visionModels.isEmpty) {
          print('⚠️ No vision models found, using fallback');
          return [
            'gemini-2.5-flash',
            'gemini-2.0-flash',
            'gemini-flash-latest',
          ];
        }

        // Sort by preference: 2.5 > 2.0 > flash > pro
        visionModels.sort((a, b) {
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

        print('📋 Vision models available: ${visionModels.take(5).join(', ')}');
        return visionModels;
      } else {
        print('⚠️ Failed to fetch models (${response.statusCode})');
        return ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-flash-latest'];
      }
    } catch (e) {
      print('⚠️ Error fetching models: $e');
      return ['gemini-2.5-flash', 'gemini-2.0-flash', 'gemini-flash-latest'];
    }
  }

  @override
  Future<String> getAIResponse(String query) async {
    print('👤 User query: $query');
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
            print('🔧 Tool: ${functionCall.name}');
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
        print('🤖 Response: $finalText');
        return finalText;
      } on GenerativeAIException catch (e) {
        print('❌ GenerativeAI error: ${e.message}');
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
          print('💡 Model "$modelName" not supported — trying next...');
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
    print('📷 Image query: $query');
    print('📁 Image path : ${imageFile.path}');

    final visionModels = await _getAvailableVisionModels();

    for (int i = 0; i < visionModels.length && i < 5; i++) {
      final modelName = visionModels[i];

      final cooldownUntil = _modelCooldowns[modelName];
      if (cooldownUntil != null && DateTime.now().isBefore(cooldownUntil)) {
        final waitSeconds = cooldownUntil.difference(DateTime.now()).inSeconds;
        print('⏭️ $modelName in cooldown (${waitSeconds}s). Trying next...');
        continue;
      }

      try {
        final imageBytes = await imageFile.readAsBytes();
        print('🖼️  Image loaded: ${imageBytes.lengthInBytes} bytes');

        print('🌐 Calling v1beta API for: $modelName');
        final response = await _callVisionAPIv1beta(
          modelName: modelName,
          prompt: query,
          imageBytes: imageBytes,
        );

        if (response.isEmpty) {
          return 'I can see the image but could not generate a response.';
        }

        _modelCooldowns.remove(modelName);
        print('✅ Vision response from $modelName');
        return response;
      } catch (e) {
        final errorMsg = e.toString();
        print(
          '❌ Vision error ($modelName): ${errorMsg.substring(0, errorMsg.length > 100 ? 100 : errorMsg.length)}',
        );

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

        if (errorMsg.contains('400') || errorMsg.contains('INVALID_ARGUMENT')) {
          return '⚠️ Could not process this image. Please try again with a clearer photo.';
        }

        _modelCooldowns[modelName] = DateTime.now().add(
          const Duration(minutes: 5),
        );
        continue;
      }
    }

    return '⚠️ Vision service temporarily unavailable. Please try again shortly.';
  }

  Future<String> _callVisionAPIv1beta({
    required String modelName,
    required String prompt,
    required List<int> imageBytes,
  }) async {
    final apiKey = AppConstants.geminiApiKey;
    final base64Image = base64Encode(imageBytes);

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey',
    );

    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
            },
          ],
        },
      ],
      'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 1000},
    };

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      final candidates = data['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          final text = parts[0]['text'];
          if (text != null) return text as String;
        }
      }

      throw Exception('No text in response');
    } else {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
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
    print('🔄 Chat session reset');
  }
}
