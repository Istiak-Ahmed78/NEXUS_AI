import 'dart:io';
import 'package:dartz/dartz.dart';
import '../../core/errors/failures.dart';
import '../../core/usecases/usecase.dart';
import '../entities/message_entity.dart';
import '../repositories/ai_repository.dart';

class GetAIResponseUseCase implements UseCase<MessageEntity, String> {
  final AIRepository repository;

  GetAIResponseUseCase(this.repository);

  // ── Text-only call ─────────────────────────────────────────────
  @override
  Future<Either<Failure, MessageEntity>> call(String query) async {
    print('🔧 [UseCase] call() → Routing to repository.getAIResponse()');
    print('   📝 Query: "$query"');
    return await repository.getAIResponse(query);
  }

  // ── Image + text call ──────────────────────────────────────────
  Future<Either<Failure, MessageEntity>> callWithImage(
    String query,
    File imageFile,
  ) async {
    print(
      '🔧 [UseCase] callWithImage() → Routing to repository.getAIResponseWithImage()',
    );
    print('   📝 Query: "$query"');
    print('   🖼️  Image: ${imageFile.path}');
    return await repository.getAIResponseWithImage(query, imageFile);
  }
}

// ── GetChatHistoryUseCase ──────────────────────────────────────
class GetChatHistoryUseCase implements UseCase<List<MessageEntity>, NoParams> {
  final AIRepository repository;

  GetChatHistoryUseCase(this.repository);

  @override
  Future<Either<Failure, List<MessageEntity>>> call(NoParams params) async {
    return await repository.getChatHistory();
  }
}
