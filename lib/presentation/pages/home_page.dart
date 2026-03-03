import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/speech/speech_bloc.dart';
import '../blocs/ai_chat/ai_chat_bloc.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/mic_button.dart';
import '../widgets/listening_indicator.dart';
import 'camera_page.dart';
import '../../../injection_container.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late final AnimationController _pulseAnimation;
  late final SpeechBloc _speechBloc;
  late final AIChatBloc _aiChatBloc;
  bool _hasLoadedHistory = false; // ✅ Prevent duplicate loading

  @override
  void initState() {
    super.initState();
    _pulseAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _speechBloc = sl<SpeechBloc>();
    _aiChatBloc = sl<AIChatBloc>();

    // ✅ Only load history once on app start
    if (!_hasLoadedHistory) {
      _hasLoadedHistory = true;
      _aiChatBloc.add(const LoadChatHistoryEvent());
    }
  }

  @override
  void dispose() {
    _pulseAnimation.dispose();
    super.dispose();
  }

  void _handleVoiceInput(String text) {
    if (text.isNotEmpty) {
      _aiChatBloc.add(SendMessageEvent(message: text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _speechBloc),
        BlocProvider.value(value: _aiChatBloc),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('FL AI Assistant'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.camera_alt),
              tooltip: 'AI Camera',
              onPressed: () async {
                // ✅ Navigate to camera
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CameraPage()),
                );
                // ✅ Reload history when returning (to show camera messages)
                if (mounted) {
                  _aiChatBloc.add(const LoadChatHistoryEvent());
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                _aiChatBloc.add(const ClearChatHistoryEvent());
              },
            ),
            IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
          ],
        ),
        body: BlocBuilder<AIChatBloc, AIChatState>(
          builder: (context, chatState) {
            return Column(
              children: [
                Expanded(
                  child: BlocBuilder<AIChatBloc, AIChatState>(
                    builder: (context, state) {
                      if (state is AIChatLoading) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (state is AIChatLoaded) {
                        // ✅ Show empty state if no messages
                        if (state.messages.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.waving_hand,
                                  size: 64,
                                  color: Colors.deepPurple.withOpacity(0.5),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Tap mic & ask me anything!',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          itemCount: state.messages.length,
                          itemBuilder: (context, index) {
                            final message = state
                                .messages[state.messages.length - 1 - index];
                            return ChatBubble(message: message);
                          },
                        );
                      } else if (state is AIChatError) {
                        return Center(child: Text('Error: ${state.message}'));
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),

                if (chatState is AIChatLoaded && chatState.isTyping)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('AI is thinking...'),
                      ],
                    ),
                  ),

                BlocConsumer<SpeechBloc, SpeechState>(
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
                    String transcript = '';
                    bool isListening = false;

                    if (state is SpeechListening) {
                      transcript = state.transcript;
                      isListening = true;
                    } else if (state is SpeechResult) {
                      transcript = state.text;
                    }

                    return Column(
                      children: [
                        if (isListening)
                          ListeningIndicator(transcript: transcript),
                        Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              MicButton(
                                isListening: isListening,
                                onTap: () {
                                  if (isListening) {
                                    context.read<SpeechBloc>().add(
                                      StopListeningEvent(),
                                    );
                                  } else {
                                    context.read<SpeechBloc>().add(
                                      StartListeningEvent(),
                                    );
                                  }
                                },
                                pulseAnimation: _pulseAnimation,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isListening
                                    ? 'Listening... Tap to stop'
                                    : 'Tap to speak',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
