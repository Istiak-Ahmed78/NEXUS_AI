// lib/injection_container.dart
// ✅ COMPLETE FIXED VERSION - Proper DI Setup

import 'package:fl_ai/core/tools/tool_executor.dart';
import 'package:fl_ai/domain/usecases/clear_chat_history_usecase.dart';
import 'package:fl_ai/domain/usecases/get_ai_response_usecase.dart'
    hide ClearChatHistoryUseCase;
import 'package:fl_ai/domain/usecases/listen_to_speech_usecase.dart';
import 'package:fl_ai/domain/usecases/speak_text_usecase.dart';
import 'package:fl_ai/presentation/blocs/ai_chat/ai_chat_bloc.dart';
import 'package:fl_ai/presentation/blocs/speech/speech_bloc.dart';
import 'package:get_it/get_it.dart';

import 'data/datasources/local/ai_local_datasource.dart';
import 'data/datasources/remote/ai_remote_datasource.dart';
import 'data/repositories/ai_repository_impl.dart';
import 'domain/repositories/ai_repository.dart';

final sl = GetIt.instance;

// ✅ MAIN INITIALIZATION FUNCTION
Future<void> init() async {
  print('🔧 [DI] Starting dependency injection initialization...');

  try {
    _initSpeechFeatures();
    print('✅ [DI] Speech features initialized');

    _initAIFeatures();
    print('✅ [DI] AI features initialized');

    _initCameraFeatures();
    print('✅ [DI] Camera features initialized');

    await ToolExecutor.init();
    print('✅ [DI] Tool executor initialized');

    print('✅ [DI] All dependencies initialized successfully!');
  } catch (e) {
    print('❌ [DI] Error during initialization: $e');
    rethrow;
  }
}

// ── Speech Features ────────────────────────────────────────────
void _initSpeechFeatures() {
  // BLoC
  sl.registerFactory(
    () => SpeechBloc(
      listenToSpeech: sl(),
      stopListening: sl(),
      speakText: sl(),
      stopSpeaking: sl(),
    ),
  );

  // UseCases
  sl.registerLazySingleton(() => ListenToSpeechUseCase(sl()));
  sl.registerLazySingleton(() => StopListeningUseCase(sl()));
  sl.registerLazySingleton(() => SpeakTextUseCase(sl()));
  sl.registerLazySingleton(() => StopSpeakingUseCase(sl()));
}

// ── AI Features ────────────────────────────────────────────────
void _initAIFeatures() {
  // BLoC
  sl.registerFactory(
    () => AIChatBloc(
      getAIResponse: sl(),
      getChatHistory: sl(),
      clearChatHistory: sl(),
      speakText: sl(),
    ),
  );

  // UseCases
  sl.registerLazySingleton(() => GetAIResponseUseCase(sl()));
  sl.registerLazySingleton(() => GetChatHistoryUseCase(sl()));
  sl.registerLazySingleton(() => ClearChatHistoryUseCase(sl()));

  // Repository
  sl.registerLazySingleton<AIRepository>(
    () => AIRepositoryImpl(remoteDataSource: sl(), localDataSource: sl()),
  );

  // DataSources
  sl.registerLazySingleton<AIRemoteDataSource>(() => AIRemoteDataSourceImpl());
  sl.registerLazySingleton<AILocalDataSource>(() => AILocalDataSourceImpl());
}

// ── Camera Features ───────────────────────────────────────────
void _initCameraFeatures() {
  // CameraBloc is created directly in CameraPage
  // because each camera screen needs its own controller instance
}
