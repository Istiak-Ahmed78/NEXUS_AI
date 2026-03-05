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
// Triggered by CameraPage after user speaks a query and takes a photo.
// imageFile  = the captured photo from CameraX
// message    = the spoken/typed question about the image
// shouldSpeak = whether TTS should read the AI response aloud
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
