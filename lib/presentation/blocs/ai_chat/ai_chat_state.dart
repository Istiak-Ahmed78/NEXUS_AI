part of 'ai_chat_bloc.dart';

abstract class AIChatState extends Equatable {
  const AIChatState();

  @override
  List<Object?> get props => [];
}

// ── Initial state ──────────────────────────────────────────────────
class AIChatInitial extends AIChatState {}

// ── Loading (fetching history etc.) ───────────────────────────────
class AIChatLoading extends AIChatState {}

// ── Loaded — main state with messages ─────────────────────────────
// isTyping = true  → show "AI is thinking..." bubble
// isTyping = false → normal chat view
class AIChatLoaded extends AIChatState {
  final List<MessageEntity> messages;
  final bool isTyping;

  const AIChatLoaded({required this.messages, this.isTyping = false});

  @override
  List<Object?> get props => [messages, isTyping];
}

// ── Error state ────────────────────────────────────────────────────
class AIChatError extends AIChatState {
  final String message;

  const AIChatError(this.message);

  @override
  List<Object?> get props => [message];
}
