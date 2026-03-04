// lib/data/datasources/remote/ai_remote_datasource.dart
// ✅ COMPLETE FIXED VERSION - Proper async search handling with timeout & cache

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/tools/tool_executor.dart';
import '../../../core/tools/tool_registry.dart';
import '../../../core/ai/gemini_model_manager.dart';
import '../local/search_cache_datasource.dart';

abstract class AIRemoteDataSource {
  Future<String> getAIResponse(String query);
  Future<String> getAIResponseWithImage(
    String query,
    File imageFile, {
    required Function(String finalResponse) onSearchCompleted,
  });
  void resetSession();
}

class AIRemoteDataSourceImpl implements AIRemoteDataSource {
  ChatSession? _chatSession;
  String? _currentModelName;
  late SearchCacheDataSource _cacheDataSource;

  static List<String>? _cachedVisionModels;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(hours: 1);

  final Map<String, DateTime> _modelCooldowns = {};

  AIRemoteDataSourceImpl() {
    _cacheDataSource = SearchCacheDataSource();
  }

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
    if (modelName.contains('-tts')) return false;
    if (modelName.contains('computer-use')) return false;
    if (modelName.contains('robotics')) return false;
    if (modelName.contains('-lite')) return false;
    if (modelName.contains('-exp') && !modelName.contains('flash-exp'))
      return false;
    if (modelName.contains('flash') || modelName.contains('pro')) return true;
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
  Future<String> getAIResponseWithImage(
    String query,
    File imageFile, {
    required Function(String finalResponse) onSearchCompleted,
  }) async {
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
          onSearchCompleted: onSearchCompleted,
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
    required Function(String finalResponse) onSearchCompleted,
  }) async {
    try {
      print('🔍 [Vision] Starting vision+tool call with model: $modelName');

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

      // ✅ CREATE CHAT SESSION (maintains conversation context)
      final session = model.startChat();

      print('🔍 [Vision] Sending initial vision request...');

      // ✅ SEND THROUGH SESSION (not direct generateContent)
      var response = await session.sendMessage(
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', Uint8List.fromList(imageBytes)),
        ]),
      );

      print('🔍 [Vision] Initial response received');
      print(
        '🔍 [Vision] Has function calls: ${response.functionCalls.isNotEmpty}',
      );

      int loopCount = 0;
      const maxLoops = 5;

      while (response.functionCalls.isNotEmpty && loopCount < maxLoops) {
        loopCount++;
        print('🔍 [Vision] Tool loop #$loopCount');
        print('🔍 [Vision] Function calls: ${response.functionCalls.length}');

        bool hasSearchTool = response.functionCalls.any(
          (call) => call.name == 'search_web',
        );

        // ✅ IF SEARCH DETECTED - RETURN EARLY AND HANDLE ASYNC
        if (hasSearchTool) {
          print('🔍 [Vision] Search tool detected!');
          print('🔍 [Vision] Returning "Searching..." immediately');

          // ✅ PASS SESSION TO ASYNC HANDLER (not model)
          _executeVisionSearchAsync(
            session: session,
            response: response,
            onSearchCompleted: onSearchCompleted,
          );

          // Return early so UI updates immediately
          return 'Searching the web for that information. Please wait...';
        }

        // For non-search tools, execute normally
        final functionResponseParts = <Part>[];

        for (final functionCall in response.functionCalls) {
          print('🔍 [Vision] Executing tool: ${functionCall.name}');

          final toolResult = await ToolExecutor.execute(
            functionCall.name,
            functionCall.args,
          );

          print('🔍 [Vision] Tool result: ${toolResult['success']}');
          functionResponseParts.add(
            FunctionResponse(functionCall.name, toolResult),
          );
        }

        print('🔍 [Vision] Sending function responses to API...');
        try {
          // ✅ SEND THROUGH SESSION (maintains context)
          response = await session.sendMessage(
            Content.model(functionResponseParts),
          );
          print('🔍 [Vision] Function response accepted');
        } catch (e) {
          print('🔍 [Vision] ❌ ERROR sending response: $e');
          rethrow;
        }
      }

      final text = response.text;
      print('🔍 [Vision] Final response: ${text?.length ?? 0} chars');

      if (text == null || text.trim().isEmpty) {
        return 'Action completed successfully.';
      }

      return text;
    } catch (e) {
      print('🔍 [Vision] ❌ ERROR: $e');
      rethrow;
    }
  }

  Future<void> _executeVisionSearchAsync({
    required ChatSession
    session, // ✅ CHANGED: ChatSession instead of GenerativeModel
    required GenerateContentResponse response,
    required Function(String finalResponse) onSearchCompleted,
  }) async {
    print('🔍 [Vision-Async] Starting background search...');

    try {
      // Execute all search tools with timeout
      final functionResponseParts = <Part>[];

      for (final functionCall in response.functionCalls) {
        print('🔍 [Vision-Async] Executing: ${functionCall.name}');

        try {
          // ✅ Add timeout to tool execution
          final toolResult =
              await ToolExecutor.execute(
                functionCall.name,
                functionCall.args,
              ).timeout(
                Duration(seconds: 5),
                onTimeout: () {
                  print('⏱️ [Vision-Async] Tool timeout: ${functionCall.name}');
                  return {
                    'success': false,
                    'error': 'Tool execution timed out',
                    'message': 'Search took too long',
                  };
                },
              );

          print('🔍 [Vision-Async] Tool result received');

          // ✅ Cache search results if successful
          if (functionCall.name == 'search_web' &&
              toolResult['success'] == true &&
              toolResult['results'] != null) {
            final searchQuery = functionCall.args?['query'] ?? 'unknown';
            final results = toolResult['results'] as List?;

            if (results != null && results.isNotEmpty) {
              print(
                '💾 [Vision-Async] Caching search results for: "$searchQuery"',
              );
              await _cacheDataSource.cacheSearchResults(
                searchQuery as String,
                List<Map<String, dynamic>>.from(results),
              );
            }
          }

          functionResponseParts.add(
            FunctionResponse(functionCall.name, toolResult),
          );
        } catch (e) {
          print('🔍 [Vision-Async] Tool error: $e');

          // ✅ Try cache if search tool fails
          if (functionCall.name == 'search_web') {
            final searchQuery = functionCall.args?['query'] ?? 'unknown';
            print(
              '💾 [Vision-Async] Trying cached results for: "$searchQuery"',
            );

            final cachedResults = await _cacheDataSource.getCachedResults(
              searchQuery as String,
            );

            if (cachedResults != null && cachedResults.isNotEmpty) {
              print(
                '✅ [Vision-Async] Found ${cachedResults.length} cached results',
              );
              functionResponseParts.add(
                FunctionResponse(functionCall.name, {
                  'success': true,
                  'results': cachedResults,
                  'cached': true,
                  'message': 'Using cached results (live search failed)',
                }),
              );
            } else {
              print('❌ [Vision-Async] No cached results available');
              functionResponseParts.add(
                FunctionResponse(functionCall.name, {
                  'success': false,
                  'error': 'Search failed and no cached results available',
                  'message': 'Please try again',
                }),
              );
            }
          } else {
            // Non-search tool failed
            functionResponseParts.add(
              FunctionResponse(functionCall.name, {
                'success': false,
                'error': e.toString(),
              }),
            );
          }
        }
      }

      print('🔍 [Vision-Async] Sending search results to Gemini...');

      // ✅ FIXED: Send through session (maintains conversation context)
      final finalResponse = await session.sendMessage(
        Content.model(functionResponseParts),
      );

      final finalText = finalResponse.text;
      print(
        '🔍 [Vision-Async] Final response ready: ${finalText?.length ?? 0} chars',
      );

      if (finalText != null && finalText.trim().isNotEmpty) {
        print('🔍 [Vision-Async] Calling callback with final response');
        onSearchCompleted(finalText);
      } else {
        print(
          '🔍 [Vision-Async] Empty response, calling callback with default',
        );
        onSearchCompleted('Search completed');
      }
    } catch (e) {
      print('🔍 [Vision-Async] ❌ ERROR: $e');
      onSearchCompleted(
        'I found information but encountered an error processing it. Please try again.',
      );
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
