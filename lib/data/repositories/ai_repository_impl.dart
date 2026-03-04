// lib/data/repositories/ai_repository_impl.dart
// ✅ COMPLETE FIXED VERSION - With async search callback

import 'dart:async';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../../core/errors/failures.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/ai_repository.dart';
import '../datasources/remote/ai_remote_datasource.dart';
import '../datasources/local/ai_local_datasource.dart';
import '../models/message_model.dart';

class AIRepositoryImpl implements AIRepository {
  final AIRemoteDataSource remoteDataSource;
  final AILocalDataSource localDataSource;

  // ── Speech services (unchanged) ────────────────────────────────
  late final stt.SpeechToText _speech;
  late final FlutterTts _tts;

  // ── Stream for listening state (unchanged) ─────────────────────
  final _listeningController = StreamController<bool>.broadcast();

  // ✅ NEW: Stream for vision search completion
  final _visionSearchController = StreamController<String>.broadcast();

  AIRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  }) {
    _speech = stt.SpeechToText();
    _tts = FlutterTts();
    _initTTS();
  }

  // ── TTS init (unchanged) ───────────────────────────────────────
  Future<void> _initTTS() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(AppConstants.speechRate);
    await _tts.setPitch(AppConstants.pitch);
  }

  // ── listenForSpeech (unchanged) ────────────────────────────────
  @override
  Future<Either<Failure, String>> listenForSpeech() async {
    try {
      bool available = await _speech.initialize();
      if (!available) {
        return Left(
          SpeechRecognitionFailure('Speech recognition not available'),
        );
      }

      _listeningController.add(true);

      Completer<String> completer = Completer();

      await _speech.listen(
        onResult: (result) {
          if (result.finalResult && !completer.isCompleted) {
            completer.complete(result.recognizedWords);
          }
        },
        listenFor: AppConstants.listenDuration,
        pauseFor: AppConstants.pauseDuration,
      );

      String result = await completer.future;
      _listeningController.add(false);

      return Right(result);
    } catch (e) {
      _listeningController.add(false);
      return Left(SpeechRecognitionFailure(e.toString()));
    }
  }

  // ── stopListening (unchanged) ──────────────────────────────────
  @override
  Future<Either<Failure, void>> stopListening() async {
    try {
      await _speech.stop();
      _listeningController.add(false);
      return const Right(null);
    } catch (e) {
      return Left(SpeechRecognitionFailure(e.toString()));
    }
  }

  // ── speakText (unchanged) ──────────────────────────────────────
  @override
  Future<Either<Failure, void>> speakText(String text) async {
    try {
      await _tts.speak(text);
      return const Right(null);
    } catch (e) {
      return Left(TTSFailure(e.toString()));
    }
  }

  // ── stopSpeaking (unchanged) ───────────────────────────────────
  @override
  Future<Either<Failure, void>> stopSpeaking() async {
    try {
      await _tts.stop();
      return const Right(null);
    } catch (e) {
      return Left(TTSFailure(e.toString()));
    }
  }

  // ── getAIResponse (unchanged) ──────────────────────────────────
  @override
  Future<Either<Failure, MessageEntity>> getAIResponse(String query) async {
    try {
      final aiResponse = await remoteDataSource.getAIResponse(query);

      final message = MessageModel.create(
        content: aiResponse,
        role: MessageRole.assistant,
      );

      await localDataSource.saveMessage(message);

      return Right(message);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ✅ UPDATED: getAIResponseWithImage with callback
  @override
  Future<Either<Failure, MessageEntity>> getAIResponseWithImage(
    String query,
    File imageFile, {
    required Function(String finalResponse) onSearchCompleted,
  }) async {
    try {
      print(
        '📦 [Repository] Calling remoteDataSource.getAIResponseWithImage()',
      );
      print('   📝 Query: "$query"');
      print('   🖼️  Image: ${imageFile.path}');

      final aiResponse = await remoteDataSource.getAIResponseWithImage(
        query,
        imageFile,
        onSearchCompleted: (finalResponse) {
          print('📦 [Repository] Vision search completed callback received');
          print(
            '   📝 Final response: "${finalResponse.substring(0, finalResponse.length > 50 ? 50 : finalResponse.length)}..."',
          );

          // Save the final response to local database
          _saveVisionSearchResult(finalResponse);

          // Emit to stream so BLoC can listen
          _visionSearchController.add(finalResponse);

          // Also call the original callback
          onSearchCompleted(finalResponse);
        },
      );

      final message = MessageModel.create(
        content: aiResponse,
        role: MessageRole.assistant,
      );

      // Save initial "Searching..." message to local chat history
      await localDataSource.saveMessage(message);

      print('📦 [Repository] Returning initial response: "$aiResponse"');
      return Right(message);
    } catch (e) {
      print('📦 [Repository] ❌ Error: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  // ✅ NEW: Save vision search result to local database
  Future<void> _saveVisionSearchResult(String finalResponse) async {
    try {
      final message = MessageModel.create(
        content: finalResponse,
        role: MessageRole.assistant,
      );
      await localDataSource.saveMessage(message);
      print('💾 [Repository] Vision search result saved to local database');
    } catch (e) {
      print('❌ [Repository] Failed to save vision search result: $e');
    }
  }

  // ✅ NEW: Stream for listening to vision search completion
  Stream<String> get visionSearchStream => _visionSearchController.stream;

  // ── getChatHistory (unchanged) ─────────────────────────────────
  @override
  Future<Either<Failure, List<MessageEntity>>> getChatHistory() async {
    try {
      final messages = await localDataSource.getChatHistory();
      return Right(messages);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ── clearChatHistory (unchanged) ───────────────────────────────
  @override
  Future<Either<Failure, void>> clearChatHistory() async {
    try {
      await localDataSource.clearChatHistory();
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  // ── listeningStream (unchanged) ────────────────────────────────
  @override
  Stream<bool> get listeningStream => _listeningController.stream;

  // ── dispose (updated) ──────────────────────────────────────────
  void dispose() {
    _listeningController.close();
    _visionSearchController.close();
    _tts.stop();
  }
}
