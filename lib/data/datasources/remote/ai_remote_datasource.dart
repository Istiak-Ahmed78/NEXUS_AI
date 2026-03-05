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
      if (_currentModelName != null && _currentModelName != modelName) {
        print('🔀 [Session] Model changed: $_currentModelName → $modelName');
      }
      _currentModelName = modelName;
      _chatSession = _buildModel(modelName).startChat();
      print('✅ [Session] New session started with: $modelName');
    }
    return _chatSession!;
  }

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
          final name = model['name'] as String;
          final supportedMethods = model['supportedGenerationMethods'] as List?;

          if (supportedMethods != null &&
              supportedMethods.contains('generateContent')) {
            final modelName = name.replaceFirst('models/', '');

            if (modelName.startsWith('gemini-') &&
                _isVisionCapable(modelName)) {
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

  bool _isVisionCapable(String modelName) {
    if (modelName.contains('-tts')) {
      print('⏭️ Skipping TTS model: $modelName');
      return false;
    }

    if (modelName.contains('computer-use')) {
      print('⏭️ Skipping computer-use model: $modelName');
      return false;
    }

    if (modelName.contains('robotics')) {
      print('⏭️ Skipping robotics model: $modelName');
      return false;
    }

    if (modelName.contains('-lite')) {
      print('⏭️ Skipping lite model: $modelName');
      return false;
    }

    if (modelName.contains('-exp') && !modelName.contains('flash-exp')) {
      print('⏭️ Skipping experimental model: $modelName');
      return false;
    }

    if (modelName.contains('flash') || modelName.contains('pro')) {
      return true;
    }

    print('⏭️ Skipping unknown model type: $modelName');
    return false;
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

        print('🌐 Calling vision API with tools for: $modelName');
        final response = await _callVisionWithTools(
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

        if (e.toString().contains('quota') ||
            e.toString().contains('RESOURCE_EXHAUSTED')) {
          print('🔍 [DEBUG VISION] ⚠️ This is a QUOTA error');
          // Parse retry seconds...
          final retrySeconds = _parseRetrySecondsFromError(e.toString());
          print('🔍 [DEBUG VISION] Setting cooldown for $retrySeconds seconds');
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
      print('🔍 [DEBUG] Starting vision+tool call with model: $modelName');
      print('🔍 [DEBUG] Prompt length: ${prompt.length} chars');
      print('🔍 [DEBUG] Image size: ${imageBytes.length} bytes');

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

      // Initial request with image
      final initialContent = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', Uint8List.fromList(imageBytes)),
        ]),
      ];

      print('🔍 [DEBUG] Sending initial vision request...');
      var response = await model.generateContent(initialContent);
      print('🔍 [DEBUG] Initial response received');
      print(
        '🔍 [DEBUG] Has function calls: ${response.functionCalls.isNotEmpty}',
      );

      int loopCount = 0;
      const maxLoops = 5;

      while (response.functionCalls.isNotEmpty && loopCount < maxLoops) {
        loopCount++;
        print('🔍 [DEBUG] Tool loop #$loopCount started');
        print(
          '🔍 [DEBUG] Function calls count: ${response.functionCalls.length}',
        );

        final functionResponseParts = <Part>[];

        for (final functionCall in response.functionCalls) {
          print('🔍 [DEBUG] Executing tool: ${functionCall.name}');
          print('🔍 [DEBUG] Tool args: ${functionCall.args}');

          print(
            '🔍 [DEBUG TIMING] Starting tool execution at: ${DateTime.now().toIso8601String()}',
          );
          final toolResult = await ToolExecutor.execute(
            functionCall.name,
            functionCall.args,
          );
          print(
            '🔍 [DEBUG TIMING] Tool execution completed in: ${DateTime.now().difference(_toolStartTime).inMilliseconds}ms',
          );

          print('🔍 [DEBUG] Tool execution result: $toolResult');
          print('🔍 [DEBUG] Tool success: ${toolResult['success']}');

          // Add function response as Part
          functionResponseParts.add(
            FunctionResponse(functionCall.name, toolResult),
          );
        }

        // ⭐ FUNCTION TO WAIT FOR APP TO BE ACTIVE
        Future<void> ensureAppIsActive() async {
          // Check current state
          var currentState = WidgetsBinding.instance.lifecycleState;
          print('🔍 [DEBUG LIFECYCLE] Current app state: $currentState');

          // If inactive, wait for resume
          if (currentState == AppLifecycleState.inactive) {
            print(
              '🔍 [DEBUG LIFECYCLE] App is inactive, waiting for resume...',
            );

            final completer = Completer<void>();
            final observer = _AppLifecycleObserver(completer);
            WidgetsBinding.instance.addObserver(observer);

            try {
              await completer.future.timeout(
                const Duration(seconds: 2),
                onTimeout: () {
                  print(
                    '🔍 [DEBUG LIFECYCLE] Timeout waiting for app to resume',
                  );
                  if (!completer.isCompleted) {
                    completer.complete();
                  }
                },
              );
            } finally {
              WidgetsBinding.instance.removeObserver(observer);
            }

            // Check state again after waiting
            print(
              '🔍 [DEBUG LIFECYCLE] After wait, app state: ${WidgetsBinding.instance.lifecycleState}',
            );
          }
        }

        // After tool execution
        print('🔍 [DEBUG] Sending function responses back to API...');
        print(
          '🔍 [DEBUG] Function response parts count: ${functionResponseParts.length}',
        );

        try {
          final connectivityResult = await Connectivity().checkConnectivity();
          print('🔍 [DEBUG NETWORK] Connectivity: $connectivityResult');

          // ⭐ NEW: Check state - if inactive, DON'T WAIT, just give up
          final currentState = WidgetsBinding.instance.lifecycleState;
          print('🔍 [DEBUG LIFECYCLE] Current app state: $currentState');

          if (currentState == AppLifecycleState.inactive) {
            print(
              '🔍 [DEBUG LIFECYCLE] App is inactive - CANNOT send function response',
            );
            print('🔍 [DEBUG LIFECYCLE] Skipping API call to preserve quota');

            // Return a simple success message without trying API
            return 'Call initiated successfully!';
          }

          // Only try API call if app is active
          print('🔍 [DEBUG LIFECYCLE] App is active, proceeding with API call');
          response = await model.generateContent([
            Content.model(functionResponseParts),
          ]);
          print('🔍 [DEBUG] Function response accepted by API');
        } catch (e) {
          print('🔍 [DEBUG] ❌ ERROR sending function response: $e');
          print('🔍 [DEBUG] Error type: ${e.runtimeType}');
          rethrow;
        }
      }

      final text = response.text;
      print('🔍 [DEBUG] Final response text length: ${text?.length ?? 0}');

      if (text == null || text.trim().isEmpty) {
        return 'Action completed successfully.';
      }

      return text;
    } catch (e) {
      print('🔍 [DEBUG TIMING] ❌ ERROR in vision+tool call: $e');
      print('🔍 [DEBUG TIMING] Error type: ${e.runtimeType}');
      print(
        '🔍 [DEBUG TIMING] Current time: ${DateTime.now().toIso8601String()}',
      );
      print(
        '🔍 [DEBUG TIMING] Time since tool execution started: ${DateTime.now().difference(_toolStartTime).inMilliseconds}ms',
      );

      // Check if app is in foreground (though Flutter can't directly know this)
      print(
        '🔍 [DEBUG TIMING] Widgets binding initialized: ${WidgetsBinding.instance.lifecycleState}',
      );
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
    print('🔄 Chat session reset');
  }
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  final Completer<void> completer;

  _AppLifecycleObserver(this.completer);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!completer.isCompleted) {
        print('🔍 [DEBUG LIFECYCLE] App resumed, completing waiter');
        completer.complete();
      }
    }
  }
}
