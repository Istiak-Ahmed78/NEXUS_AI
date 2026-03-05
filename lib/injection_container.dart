import 'package:fl_ai/core/tools/tool_executor.dart';
import 'package:fl_ai/domain/usecases/clear_chat_history_usecase.dart';
import 'package:get_it/get_it.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'presentation/blocs/speech/speech_bloc.dart';
import 'presentation/blocs/ai_chat/ai_chat_bloc.dart';
import 'presentation/blocs/camera/camera_bloc.dart'; // ✅ NEW

import 'domain/usecases/listen_to_speech_usecase.dart';
import 'domain/usecases/speak_text_usecase.dart';
import 'domain/usecases/get_ai_response_usecase.dart';

import 'domain/repositories/ai_repository.dart';
import 'data/repositories/ai_repository_impl.dart';

import 'data/datasources/remote/ai_remote_datasource.dart';
import 'data/datasources/local/ai_local_datasource.dart';

final sl = GetIt.instance;

Future<void> init() async {
  _initSpeechFeatures();
  _initAIFeatures();
  _initCameraFeatures(); // ✅ NEW

  await ToolExecutor.init();
}

void _initSpeechFeatures() {
  sl.registerFactory(
    () => SpeechBloc(
      listenToSpeech: sl(),
      stopListening: sl(),
      speakText: sl(),
      stopSpeaking: sl(),
    ),
  );

  sl.registerLazySingleton(() => ListenToSpeechUseCase(sl()));
  sl.registerLazySingleton(() => StopListeningUseCase(sl()));
  sl.registerLazySingleton(() => SpeakTextUseCase(sl()));
  sl.registerLazySingleton(() => StopSpeakingUseCase(sl()));
}

void _initAIFeatures() {
  sl.registerFactory(
    () => AIChatBloc(
      getAIResponse: sl(),
      getChatHistory: sl(),
      clearChatHistory: sl(),
      speakText: sl(),
    ),
  );

  sl.registerLazySingleton(() => GetAIResponseUseCase(sl()));
  sl.registerLazySingleton(() => GetChatHistoryUseCase(sl()));
  sl.registerLazySingleton(() => ClearChatHistoryUseCase(sl()));

  sl.registerLazySingleton<AIRepository>(
    () => AIRepositoryImpl(remoteDataSource: sl(), localDataSource: sl()),
  );

  sl.registerLazySingleton<AIRemoteDataSource>(() => AIRemoteDataSourceImpl());
  sl.registerLazySingleton<AILocalDataSource>(() => AILocalDataSourceImpl());
}

// ✅ NEW
void _initCameraFeatures() {
  // CameraBloc is created directly in CameraPage (not registered here)
  // because each camera screen needs its own controller instance
}
