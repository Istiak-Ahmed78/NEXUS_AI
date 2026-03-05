import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/camera/camera_bloc.dart';
import '../blocs/speech/speech_bloc.dart';
import '../blocs/ai_chat/ai_chat_bloc.dart';
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

  final List<MessageEntity> _localMessages = [];

  File? _lastCapturedImage;
  bool _isVisionModeEnabled = false;
  String? _pendingVoiceInput;

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

    _cameraBloc.add(InitializeCameraEvent());
  }

  @override
  void dispose() {
    _pulseAnimation.dispose();
    _cameraBloc.add(DisposeCameraEvent());
    _cameraBloc.close();
    super.dispose();
  }

  void _toggleVisionMode() {
    setState(() {
      _isVisionModeEnabled = !_isVisionModeEnabled;
    });
  }

  Future<void> _handleVoiceInput(String text) async {
    if (text.isEmpty) return;

    final userMessage = MessageModel.create(
      content: text,
      role: MessageRole.user,
    );
    setState(() => _localMessages.add(userMessage));

    if (_isVisionModeEnabled) {
      _pendingVoiceInput = text;
      _cameraBloc.add(CapturePhotoEvent());
    } else if (_lastCapturedImage != null) {
      _sendVisionMessage(text, _lastCapturedImage!);
    } else {
      _pendingVoiceInput = text;
      _cameraBloc.add(CapturePhotoEvent());
    }
  }

  Future<void> _sendVisionMessage(String text, File imageFile) async {
    _aiChatBloc.add(
      SendMessageWithImageEvent(
        message: text,
        imageFile: imageFile,
        shouldSpeak: true,
      ),
    );

    if (_isVisionModeEnabled) {
      setState(() {
        _lastCapturedImage = imageFile;
        _isVisionModeEnabled = false;
        _pendingVoiceInput = null;
      });
    }
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
            _buildCameraPreview(),
            _buildTopBar(),
            _buildFloatingChat(),
            _buildVisionToggleButton(),
            _buildBottomMicArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    return BlocConsumer<CameraBloc, CameraState>(
      listener: (context, state) {
        if (state is CameraPhotoCaptured) {
          if (_pendingVoiceInput != null) {
            _sendVisionMessage(_pendingVoiceInput!, state.imageFile);
          }
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

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
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

  Widget _buildFloatingChat() {
    return BlocListener<AIChatBloc, AIChatState>(
      listener: (context, state) {
        if (state is AIChatLoaded && state.messages.isNotEmpty) {
          final lastMsg = state.messages.last;
          if (lastMsg.role == MessageRole.assistant) {
            final alreadyExists = _localMessages.any((m) => m.id == lastMsg.id);
            if (!alreadyExists) {
              setState(() => _localMessages.add(lastMsg));
            }
          }
        }
      },
      child: Positioned(
        top: 100,
        left: 0,
        right: 0,
        bottom: 240,
        child: _localMessages.isEmpty
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isVisionModeEnabled
                            ? Icons.camera_alt
                            : _lastCapturedImage != null
                            ? Icons.chat_bubble_outline
                            : Icons.camera_alt_outlined,
                        color: Colors.white70,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isVisionModeEnabled
                            ? '📷 Vision mode ON\nNext message will capture NEW image'
                            : _lastCapturedImage != null
                            ? '💬 Follow-up mode\nAsking about previous image'
                            : '📸 Point camera & tap mic\nto start analyzing',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                reverse: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                itemCount: _localMessages.length,
                itemBuilder: (context, index) {
                  final message =
                      _localMessages[_localMessages.length - 1 - index];
                  return _buildTransparentBubble(message);
                },
              ),
      ),
    );
  }

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

  Widget _buildVisionToggleButton() {
    return Positioned(
      bottom: 160,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _toggleVisionMode,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _isVisionModeEnabled
                  ? Colors.green.withOpacity(0.9)
                  : _lastCapturedImage != null
                  ? Colors.blue.withOpacity(0.8)
                  : Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: _isVisionModeEnabled
                    ? Colors.greenAccent
                    : _lastCapturedImage != null
                    ? Colors.blueAccent
                    : Colors.white38,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (_isVisionModeEnabled
                              ? Colors.green
                              : _lastCapturedImage != null
                              ? Colors.blue
                              : Colors.black)
                          .withOpacity(0.5),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isVisionModeEnabled
                      ? Icons.camera_alt
                      : _lastCapturedImage != null
                      ? Icons.image
                      : Icons.camera_alt_outlined,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  _isVisionModeEnabled
                      ? 'Capture NEW'
                      : _lastCapturedImage != null
                      ? 'Follow-up Mode'
                      : 'Vision OFF',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
                BlocBuilder<AIChatBloc, AIChatState>(
                  builder: (context, chatState) {
                    if (chatState is AIChatLoaded && chatState.isTyping) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white70,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'AI is analyzing...',
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

                GestureDetector(
                  onTap: () {
                    if (isListening) {
                      context.read<SpeechBloc>().add(StopListeningEvent());
                    } else {
                      context.read<SpeechBloc>().add(StartListeningEvent());
                    }
                  },
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isListening ? Colors.red : Colors.deepPurple,
                      boxShadow: [
                        BoxShadow(
                          color: (isListening ? Colors.red : Colors.deepPurple)
                              .withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      isListening ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  isListening
                      ? 'Listening... Tap to stop'
                      : _isVisionModeEnabled
                      ? 'Tap mic to capture & analyze'
                      : _lastCapturedImage != null
                      ? 'Tap mic to ask follow-up'
                      : 'Tap mic to start',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
