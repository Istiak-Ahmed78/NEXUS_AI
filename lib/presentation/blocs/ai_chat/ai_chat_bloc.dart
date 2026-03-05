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

  String _truncateForLog(String text, [int maxLength = 50]) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  String _stripMarkdown(String text) {
    String cleaned = text;

    cleaned = cleaned.replaceAll(RegExp(r'\*\*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'__'), '');

    cleaned = cleaned.replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'(?<!_)_(?!_)'), '');

    cleaned = cleaned.replaceAll(RegExp(r'```[^`]*```'), '');

    cleaned = cleaned.replaceAll(RegExp(r'`([^`]+)`'), r'$1');

    cleaned = cleaned.replaceAll(RegExp(r'~~([^~]+)~~'), r'$1');

    cleaned = cleaned.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');

    cleaned = cleaned.replaceAll(RegExp(r'^#+\s+', multiLine: true), '');

    cleaned = cleaned.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

    cleaned = cleaned.replaceAll(RegExp(r'^[-*_]{3,}$', multiLine: true), '');

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    return cleaned.trim();
  }

  Future<void> _onSendMessage(
    SendMessageEvent event,
    Emitter<AIChatState> emit,
  ) async {
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

    final result = await getAIResponse(event.message);

    result.fold(
      (failure) {
        emit(AIChatError(failure.message));
      },
      (aiMessage) {
        final updatedMessages = [...currentMessages, userMessage, aiMessage];
        emit(AIChatLoaded(messages: updatedMessages, isTyping: false));

        if (event.shouldSpeak) {
          final cleanText = _stripMarkdown(aiMessage.content);
          speakText(cleanText);
        }
      },
    );
  }

  Future<void> _onSendMessageWithImage(
    SendMessageWithImageEvent event,
    Emitter<AIChatState> emit,
  ) async {
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

    final result = await getAIResponse.callWithImage(
      event.message,
      event.imageFile,
    );

    result.fold(
      (failure) {
        emit(AIChatError(failure.message));
      },
      (aiMessage) {
        final updatedMessages = [...currentMessages, userMessage, aiMessage];

        emit(AIChatLoaded(messages: updatedMessages, isTyping: false));

        if (event.shouldSpeak) {
          final cleanText = _stripMarkdown(aiMessage.content);
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
      return;
    }

    if (currentState is! AIChatLoaded) {
      emit(AIChatLoading());
    }

    final result = await getChatHistory(NoParams());

    result.fold((failure) => emit(AIChatError(failure.message)), (messages) {
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
