part of 'ai_chat_bloc.dart';

abstract class AIChatEvent extends Equatable {
  const AIChatEvent();

  @override
  List<Object?> get props => [];
}

// ── Text-only query (unchanged) ────────────────────────────────────
class SendMessageEvent extends AIChatEvent {
  final String message;
  final bool shouldSpeak;

  const SendMessageEvent({required this.message, this.shouldSpeak = true});

  @override
  List<Object?> get props => [message, shouldSpeak];
}

// ✅ NEW: Image + text query ────────────────────────────────────────
class SendMessageWithImageEvent extends AIChatEvent {
  final String message;
  final File imageFile;
  final bool shouldSpeak;

  const SendMessageWithImageEvent({
    required this.message,
    required this.imageFile,
    this.shouldSpeak = true,
  });

  @override
  List<Object?> get props => [message, imageFile, shouldSpeak];
}

// ✅ NEW: Handle async search result from vision
// Emitted when a vision query completes its background search
class VisionSearchCompletedEvent extends AIChatEvent {
  final String finalResponse;
  final bool shouldSpeak;

  const VisionSearchCompletedEvent({
    required this.finalResponse,
    this.shouldSpeak = true,
  });

  @override
  List<Object?> get props => [finalResponse, shouldSpeak];
}

// ── Load chat history (unchanged) ──────────────────────────────────
class LoadChatHistoryEvent extends AIChatEvent {
  const LoadChatHistoryEvent();
}

// ── Clear chat history (unchanged) ─────────────────────────────────
class ClearChatHistoryEvent extends AIChatEvent {
  const ClearChatHistoryEvent();
}

// ── Add a single message to state (unchanged) ──────────────────────
class AddMessageEvent extends AIChatEvent {
  final MessageEntity message;

  const AddMessageEvent(this.message);

  @override
  List<Object?> get props => [message];
}
