import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/camera/camera_bloc.dart';
import '../blocs/speech/speech_bloc.dart';
import '../blocs/ai_chat/ai_chat_bloc.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/mic_button.dart';
import '../widgets/listening_indicator.dart';
import '../../domain/entities/message_entity.dart';
import '../../data/models/message_model.dart';
import '../../../injection_container.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with TickerProviderStateMixin {
  late final AnimationController _pulseAnimation;
  late final CameraBloc _cameraBloc;
  late final SpeechBloc _speechBloc;
  late final AIChatBloc _aiChatBloc;

  // Local message list for camera screen
  final List<MessageEntity> _messages = [];

  @override
  void initState() {
    super.initState();

    _pulseAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _cameraBloc = CameraBloc();
    _speechBloc = sl<SpeechBloc>();
    _aiChatBloc = sl<AIChatBloc>();

    // Auto-initialize camera when screen opens
    _cameraBloc.add(InitializeCameraEvent());
  }

  @override
  void dispose() {
    _pulseAnimation.dispose();
    _cameraBloc.add(DisposeCameraEvent());
    _cameraBloc.close();
    super.dispose();
  }

  /// Called when speech finishes — capture photo + send to AI
  Future<void> _handleVoiceInput(String text) async {
    if (text.isEmpty) return;

    // Add user message to local list
    final userMessage = MessageModel.create(
      content: text,
      role: MessageRole.user,
    );
    setState(() => _messages.add(userMessage));

    // Capture photo automatically
    _cameraBloc.add(CapturePhotoEvent());
  }

  /// After photo is captured, send both to AI
  Future<void> _sendToAI(String text, File imageFile) async {
    _aiChatBloc.add(
      SendMessageWithImageEvent(
        message: text,
        imageFile: imageFile,
        shouldSpeak: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _cameraBloc),
        BlocProvider.value(value: _speechBloc),
        BlocProvider.value(value: _aiChatBloc),
      ],
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── Layer 1: Full screen camera preview ──
            _buildCameraPreview(),

            // ── Layer 2: Top bar (back + switch camera) ──
            _buildTopBar(),

            // ── Layer 3: Floating chat bubbles ──
            _buildFloatingChat(),

            // ── Layer 4: Bottom mic area ──
            _buildBottomMicArea(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // CAMERA PREVIEW
  // ─────────────────────────────────────────────
  Widget _buildCameraPreview() {
    return BlocConsumer<CameraBloc, CameraState>(
      listener: (context, state) {
        // When photo is captured, send to AI with the last speech text
        if (state is CameraPhotoCaptured) {
          final lastUserMsg = _messages.isNotEmpty
              ? _messages.lastWhere(
                  (m) => m.role == MessageRole.user,
                  orElse: () => _messages.last,
                )
              : null;

          if (lastUserMsg != null) {
            _sendToAI(lastUserMsg.content, state.imageFile);
          }

          // // Go back to ready state after short delay
          // Future.delayed(const Duration(milliseconds: 500), () {
          //   if (mounted) _cameraBloc.add(InitializeCameraEvent());
          // });
        }
      },
      builder: (context, state) {
        if (state is CameraReady ||
            state is CameraCapturing ||
            state is CameraPhotoCaptured) {
          final controller = state is CameraReady
              ? state.controller
              : state is CameraCapturing
              ? state.controller
              : (state as CameraPhotoCaptured).controller;

          return SizedBox.expand(child: CameraPreview(controller));
        }

        if (state is CameraLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        if (state is CameraError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera_alt, color: Colors.white54, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Camera Error:\n${state.message}',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  // ─────────────────────────────────────────────
  // TOP BAR
  // ─────────────────────────────────────────────
  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Back button
            _glassButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.pop(context),
            ),

            const Text(
              'AI Camera',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),

            // Switch camera button
            _glassButton(
              icon: Icons.flip_camera_ios,
              onTap: () => _cameraBloc.add(SwitchCameraEvent()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // FLOATING CHAT BUBBLES
  // ─────────────────────────────────────────────
  Widget _buildFloatingChat() {
    return BlocListener<AIChatBloc, AIChatState>(
      listener: (context, state) {
        if (state is AIChatLoaded && state.messages.isNotEmpty) {
          final lastMsg = state.messages.last;
          // Only add AI responses to local list
          if (lastMsg.role == MessageRole.assistant) {
            final alreadyExists = _messages.any((m) => m.id == lastMsg.id);
            if (!alreadyExists) {
              setState(() => _messages.add(lastMsg));
            }
          }
        }
      },
      child: Positioned(
        top: 100,
        left: 0,
        right: 0,
        bottom: 180,
        child: _messages.isEmpty
            ? Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '📷 Point camera & tap mic to ask AI',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              )
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[_messages.length - 1 - index];
                  return _buildTransparentBubble(message);
                },
              ),
      ),
    );
  }

  /// Semi-transparent version of ChatBubble for camera overlay
  Widget _buildTransparentBubble(MessageEntity message) {
    final isUser = message.role == MessageRole.user;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser)
            Container(
              margin: const EdgeInsets.only(right: 6),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.deepPurple.withOpacity(0.8),
                child: const Icon(
                  Icons.smart_toy,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser
                    ? Colors.deepPurple.withOpacity(0.75)
                    : Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isUser
                      ? Colors.deepPurple.shade200.withOpacity(0.4)
                      : Colors.white24,
                ),
              ),
              child: Text(
                message.content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  shadows: [Shadow(blurRadius: 2, color: Colors.black54)],
                ),
              ),
            ),
          ),
          if (isUser)
            Container(
              margin: const EdgeInsets.only(left: 6),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.deepPurple.shade100.withOpacity(0.8),
                child: const Icon(Icons.person, color: Colors.white, size: 14),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BOTTOM MIC AREA
  // ─────────────────────────────────────────────
  Widget _buildBottomMicArea() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: BlocConsumer<SpeechBloc, SpeechState>(
        listener: (context, state) {
          if (state is SpeechResult) {
            _handleVoiceInput(state.text);
          } else if (state is SpeechError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          final isListening = state is SpeechListening;
          final transcript = isListening ? state.transcript : '';

          return Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.85), Colors.transparent],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // AI Thinking indicator
                BlocBuilder<AIChatBloc, AIChatState>(
                  builder: (context, chatState) {
                    if (chatState is AIChatLoaded && chatState.isTyping) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'AI is thinking...',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                // Listening transcript
                if (isListening && transcript.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      transcript,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Mic button
                MicButton(
                  isListening: isListening,
                  onTap: () {
                    if (isListening) {
                      context.read<SpeechBloc>().add(StopListeningEvent());
                    } else {
                      context.read<SpeechBloc>().add(StartListeningEvent());
                    }
                  },
                  pulseAnimation: _pulseAnimation,
                ),

                const SizedBox(height: 8),

                Text(
                  isListening
                      ? 'Listening... Tap to stop'
                      : 'Tap mic & ask about what you see',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
