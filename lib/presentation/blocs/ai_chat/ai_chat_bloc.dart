import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:fl_ai/domain/usecases/clear_chat_history_usecase.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/usecases/usecase.dart';
import '../../../domain/entities/message_entity.dart';
import '../../../domain/usecases/get_ai_response_usecase.dart';
import '../../../domain/usecases/speak_text_usecase.dart';
import '../../../data/models/message_model.dart';

part 'ai_chat_event.dart';
part 'ai_chat_state.dart';

class AIChatBloc extends Bloc<AIChatEvent, AIChatState> {
  final GetAIResponseUseCase getAIResponse;
  final GetChatHistoryUseCase getChatHistory;
  final ClearChatHistoryUseCase clearChatHistory;
  final SpeakTextUseCase speakText;

  AIChatBloc({
    required this.getAIResponse,
    required this.getChatHistory,
    required this.clearChatHistory,
    required this.speakText,
  }) : super(AIChatInitial()) {
    on<SendMessageEvent>(_onSendMessage);
    on<SendMessageWithImageEvent>(_onSendMessageWithImage);
    on<LoadChatHistoryEvent>(_onLoadChatHistory);
    on<ClearChatHistoryEvent>(_onClearChatHistory);
    on<AddMessageEvent>(_onAddMessage);
  }

  // ✅ Helper to safely truncate text for logging
  String _truncateForLog(String text, [int maxLength = 50]) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  // ✅ IMPROVED: Better markdown stripping for TTS
  String _stripMarkdown(String text) {
    String cleaned = text;

    // Remove bold (**text** or __text__)
    cleaned = cleaned.replaceAll(RegExp(r'\*\*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'__'), '');

    // Remove italic (*text* or _text_)
    cleaned = cleaned.replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'(?<!_)_(?!_)'), '');

    // Remove code blocks (```text```)
    cleaned = cleaned.replaceAll(RegExp(r'```[^`]*```'), '');

    // Remove inline code (`text`)
    cleaned = cleaned.replaceAll(RegExp(r'`([^`]+)`'), r'$1');

    // Remove strikethrough (~~text~~)
    cleaned = cleaned.replaceAll(RegExp(r'~~([^~]+)~~'), r'$1');

    // Remove links [text](url) -> keep only text
    cleaned = cleaned.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');

    // Remove headers (# ## ### etc.)
    cleaned = cleaned.replaceAll(RegExp(r'^#+\s+', multiLine: true), '');

    // Remove list markers (- * + or 1. 2. etc.)
    cleaned = cleaned.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

    // Remove horizontal rules (---, ***, ___)
    cleaned = cleaned.replaceAll(RegExp(r'^[-*_]{3,}$', multiLine: true), '');

    // Clean up multiple spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    return cleaned.trim();
  }

  Future<void> _onSendMessage(
    SendMessageEvent event,
    Emitter<AIChatState> emit,
  ) async {
    print('\n🎯 [BLoC] Event: SendMessageEvent (TEXT-ONLY)');
    print('   📝 Message: "${event.message}"');
    print('   🚫 Image: NONE');
    print('   🔊 Should speak: ${event.shouldSpeak}');

    final currentState = state;
    List<MessageEntity> currentMessages = [];

    if (currentState is AIChatLoaded) {
      currentMessages = currentState.messages;
    }

    final userMessage = MessageModel.create(
      content: event.message,
      role: MessageRole.user,
    );

    emit(
      AIChatLoaded(messages: [...currentMessages, userMessage], isTyping: true),
    );

    print('   🔄 Calling: getAIResponse.call() → TEXT MODEL');
    final result = await getAIResponse(event.message);

    result.fold(
      (failure) {
        print('   ❌ Error: ${failure.message}\n');
        emit(AIChatError(failure.message));
      },
      (aiMessage) {
        print(
          '   ✅ Response received (${aiMessage.content.length} chars): "${_truncateForLog(aiMessage.content)}"\n',
        );
        final updatedMessages = [...currentMessages, userMessage, aiMessage];
        emit(AIChatLoaded(messages: updatedMessages, isTyping: false));

        if (event.shouldSpeak) {
          final cleanText = _stripMarkdown(aiMessage.content);
          print(
            '   🔊 TTS Original: "${_truncateForLog(aiMessage.content, 100)}"',
          );
          print('   🔊 TTS Cleaned: "${_truncateForLog(cleanText, 100)}"');
          speakText(cleanText);
        }
      },
    );
  }

  Future<void> _onSendMessageWithImage(
    SendMessageWithImageEvent event,
    Emitter<AIChatState> emit,
  ) async {
    print('\n🎯 [BLoC] Event: SendMessageWithImageEvent (VISION)');
    print('   📝 Message: "${event.message}"');
    print('   🖼️  Image: ${event.imageFile.path}');
    print('   📏 Image size: ${await event.imageFile.length()} bytes');
    print('   🔊 Should speak: ${event.shouldSpeak}');

    final currentState = state;
    List<MessageEntity> currentMessages = [];

    if (currentState is AIChatLoaded) {
      currentMessages = currentState.messages;
    }

    final userMessage = MessageModel.create(
      content: '📷 ${event.message}',
      role: MessageRole.user,
    );

    emit(
      AIChatLoaded(messages: [...currentMessages, userMessage], isTyping: true),
    );

    print('   🔄 Calling: getAIResponse.callWithImage() → VISION MODEL');
    final result = await getAIResponse.callWithImage(
      event.message,
      event.imageFile,
    );

    result.fold(
      (failure) {
        print('   ❌ Error: ${failure.message}\n');
        emit(AIChatError(failure.message));
      },
      (aiMessage) {
        print(
          '   ✅ Response received (${aiMessage.content.length} chars): "${_truncateForLog(aiMessage.content)}"\n',
        );
        final updatedMessages = [...currentMessages, userMessage, aiMessage];

        emit(AIChatLoaded(messages: updatedMessages, isTyping: false));

        if (event.shouldSpeak) {
          final cleanText = _stripMarkdown(aiMessage.content);
          print(
            '   🔊 TTS Original: "${_truncateForLog(aiMessage.content, 100)}"',
          );
          print('   🔊 TTS Cleaned: "${_truncateForLog(cleanText, 100)}"');
          speakText(cleanText);
        }
      },
    );
  }

  Future<void> _onLoadChatHistory(
    LoadChatHistoryEvent event,
    Emitter<AIChatState> emit,
  ) async {
    final currentState = state;

    if (currentState is AIChatLoaded && currentState.messages.isNotEmpty) {
      print(
        '📋 [BLoC] Chat already loaded (${currentState.messages.length} messages), skipping reload',
      );
      return;
    }

    if (currentState is! AIChatLoaded) {
      emit(AIChatLoading());
    }

    final result = await getChatHistory(NoParams());

    result.fold((failure) => emit(AIChatError(failure.message)), (messages) {
      print('📋 [BLoC] Loaded ${messages.length} messages from storage');
      emit(AIChatLoaded(messages: messages));
    });
  }

  Future<void> _onClearChatHistory(
    ClearChatHistoryEvent event,
    Emitter<AIChatState> emit,
  ) async {
    final result = await clearChatHistory(NoParams());

    result.fold(
      (failure) => emit(AIChatError(failure.message)),
      (_) => emit(const AIChatLoaded(messages: [])),
    );
  }

  void _onAddMessage(AddMessageEvent event, Emitter<AIChatState> emit) {
    final currentState = state;
    if (currentState is AIChatLoaded) {
      emit(AIChatLoaded(messages: [...currentState.messages, event.message]));
    }
  }
}
