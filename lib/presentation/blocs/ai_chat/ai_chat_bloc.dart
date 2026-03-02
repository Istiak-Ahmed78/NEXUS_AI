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
    on<SendMessageWithImageEvent>(_onSendMessageWithImage); // ✅ NEW
    on<LoadChatHistoryEvent>(_onLoadChatHistory);
    on<ClearChatHistoryEvent>(_onClearChatHistory);
    on<AddMessageEvent>(_onAddMessage);
  }

  // ── Text-only message handler (unchanged) ──────────────────────
  Future<void> _onSendMessage(
    SendMessageEvent event,
    Emitter<AIChatState> emit,
  ) async {
    final currentState = state;
    List<MessageEntity> currentMessages = [];

    if (currentState is AIChatLoaded) {
      currentMessages = currentState.messages;
    }

    // Add user message immediately
    final userMessage = MessageModel.create(
      content: event.message,
      role: MessageRole.user,
    );

    emit(
      AIChatLoaded(messages: [...currentMessages, userMessage], isTyping: true),
    );

    // Get AI response
    final result = await getAIResponse(event.message);

    result.fold((failure) => emit(AIChatError(failure.message)), (aiMessage) {
      final updatedMessages = [...currentMessages, userMessage, aiMessage];
      emit(AIChatLoaded(messages: updatedMessages, isTyping: false));

      if (event.shouldSpeak) {
        speakText(aiMessage.content);
      }
    });
  }

  // ✅ NEW: Image + text message handler ──────────────────────────
  // Flow:
  //   1. Show user's spoken query as a chat bubble immediately
  //   2. Show typing indicator while Gemini Vision processes
  //   3. Emit AI response + speak it aloud
  Future<void> _onSendMessageWithImage(
    SendMessageWithImageEvent event,
    Emitter<AIChatState> emit,
  ) async {
    final currentState = state;
    List<MessageEntity> currentMessages = [];

    if (currentState is AIChatLoaded) {
      currentMessages = currentState.messages;
    }

    // ── Step 1: Show user message bubble immediately ───────────────
    final userMessage = MessageModel.create(
      content: event.message,
      role: MessageRole.user,
    );

    emit(
      AIChatLoaded(
        messages: [...currentMessages, userMessage],
        isTyping: true, // ← show "AI is thinking..." indicator
      ),
    );

    // ── Step 2: Call vision use case ───────────────────────────────
    final result = await getAIResponse.callWithImage(
      event.message,
      event.imageFile,
    );

    // ── Step 3: Emit result ────────────────────────────────────────
    result.fold(
      (failure) {
        emit(AIChatError(failure.message));
      },
      (aiMessage) {
        final updatedMessages = [...currentMessages, userMessage, aiMessage];

        emit(AIChatLoaded(messages: updatedMessages, isTyping: false));

        // ── Step 4: Speak AI response aloud ───────────────────────
        if (event.shouldSpeak) {
          speakText(aiMessage.content);
        }
      },
    );
  }

  // ── Load chat history (unchanged) ──────────────────────────────
  Future<void> _onLoadChatHistory(
    LoadChatHistoryEvent event,
    Emitter<AIChatState> emit,
  ) async {
    emit(AIChatLoading());

    final result = await getChatHistory(NoParams());

    result.fold(
      (failure) => emit(AIChatError(failure.message)),
      (messages) => emit(AIChatLoaded(messages: messages)),
    );
  }

  // ── Clear chat history (unchanged) ─────────────────────────────
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

  // ── Add message (unchanged) ────────────────────────────────────
  void _onAddMessage(AddMessageEvent event, Emitter<AIChatState> emit) {
    final currentState = state;
    if (currentState is AIChatLoaded) {
      emit(AIChatLoaded(messages: [...currentState.messages, event.message]));
    }
  }
}
