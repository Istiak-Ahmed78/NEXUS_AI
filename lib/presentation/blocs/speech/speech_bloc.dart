import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/usecases/usecase.dart';
import '../../../domain/usecases/listen_to_speech_usecase.dart';
import '../../../domain/usecases/speak_text_usecase.dart';

part 'speech_event.dart';
part 'speech_state.dart';

class SpeechBloc extends Bloc<SpeechEvent, SpeechState> {
  final ListenToSpeechUseCase listenToSpeech;
  final StopListeningUseCase stopListening;
  final SpeakTextUseCase speakText;
  final StopSpeakingUseCase stopSpeaking;

  SpeechBloc({
    required this.listenToSpeech,
    required this.stopListening,
    required this.speakText,
    required this.stopSpeaking,
  }) : super(SpeechInitial()) {
    on<StartListeningEvent>(_onStartListening);
    on<StopListeningEvent>(_onStopListening);
    on<SpeakTextEvent>(_onSpeakText);
    on<StopSpeakingEvent>(_onStopSpeaking);
    on<SpeechResultEvent>(_onSpeechResult);
    on<ListeningStateChangedEvent>(_onListeningStateChanged);
  }

  Future<void> _onStartListening(
    StartListeningEvent event,
    Emitter<SpeechState> emit,
  ) async {
    await stopSpeaking(NoParams());

    emit(const SpeechListening());

    final result = await listenToSpeech(NoParams());

    result.fold(
      (failure) {
        emit(SpeechError(failure.message));
      },
      (text) {
        add(SpeechResultEvent(text));
      },
    );
  }

  Future<void> _onStopListening(
    StopListeningEvent event,
    Emitter<SpeechState> emit,
  ) async {
    await stopListening(NoParams());
    emit(SpeechIdle());
  }

  Future<void> _onSpeakText(
    SpeakTextEvent event,
    Emitter<SpeechState> emit,
  ) async {
    emit(Speaking(event.text));

    final result = await speakText(event.text);

    result.fold(
      (failure) {
        emit(SpeechError(failure.message));
      },
      (_) {
        emit(SpeechIdle());
      },
    );
  }

  Future<void> _onStopSpeaking(
    StopSpeakingEvent event,
    Emitter<SpeechState> emit,
  ) async {
    await stopSpeaking(NoParams());
    emit(SpeechIdle());
  }

  void _onSpeechResult(SpeechResultEvent event, Emitter<SpeechState> emit) {
    emit(SpeechResult(event.text));
  }

  void _onListeningStateChanged(
    ListeningStateChangedEvent event,
    Emitter<SpeechState> emit,
  ) {
    if (event.isListening) {
      emit(const SpeechListening());
    } else {
      emit(SpeechIdle());
    }
  }
}
