import 'dart:io'; // ✅ NEW
import 'package:dartz/dartz.dart';
import '../../core/errors/failures.dart';
import '../entities/message_entity.dart';

abstract class AIRepository {
  Future<Either<Failure, MessageEntity>> getAIResponse(String query);

  // ✅ UPDATED signature
  Future<Either<Failure, MessageEntity>> getAIResponseWithImage(
    String query,
    File imageFile, {
    required Function(String finalResponse) onSearchCompleted,
  });

  Future<Either<Failure, List<MessageEntity>>> getChatHistory();
  Future<Either<Failure, void>> clearChatHistory();
  Future<Either<Failure, String>> listenForSpeech();
  Future<Either<Failure, void>> stopListening();
  Future<Either<Failure, void>> speakText(String text);
  Future<Either<Failure, void>> stopSpeaking();

  Stream<bool> get listeningStream;
}
