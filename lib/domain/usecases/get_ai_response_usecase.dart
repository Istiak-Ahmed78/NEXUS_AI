// lib/domain/usecases/get_ai_response_usecase.dart
// ✅ COMPLETE FIXED VERSION - With async search callback

import 'dart:async';
import 'dart:io';
import 'package:dartz/dartz.dart';
import '../../core/errors/failures.dart';
import '../../core/usecases/usecase.dart';
import '../entities/message_entity.dart';
import '../repositories/ai_repository.dart';

class GetAIResponseUseCase implements UseCase<MessageEntity, String> {
  final AIRepository repository;

  // ✅ NEW: Stream controller for vision search completion
  final _visionSearchController = StreamController<String>.broadcast();

  GetAIResponseUseCase(this.repository);

  // ✅ NEW: Expose stream for BLoC to listen
  Stream<String> get visionSearchStream => _visionSearchController.stream;

  // ── Text-only call ─────────────────────────────────────────────
  @override
  Future<Either<Failure, MessageEntity>> call(String query) async {
    print('🔧 [UseCase] call() → Routing to repository.getAIResponse()');
    print('   📝 Query: "$query"');
    return await repository.getAIResponse(query);
  }

  // ✅ UPDATED: Image + text call with callback
  Future<Either<Failure, MessageEntity>> callWithImage(
    String query,
    File imageFile, {
    required Function(String finalResponse) onVisionSearchCompleted,
  }) async {
    print(
      '🔧 [UseCase] callWithImage() → Routing to repository.getAIResponseWithImage()',
    );
    print('   📝 Query: "$query"');
    print('   🖼️  Image: ${imageFile.path}');

    return await repository.getAIResponseWithImage(
      query,
      imageFile,
      onSearchCompleted: (finalResponse) {
        print('🔧 [UseCase] Vision search completed, emitting to stream');
        print(
          '   📝 Response: "${finalResponse.substring(0, finalResponse.length > 50 ? 50 : finalResponse.length)}..."',
        );

        // Emit to stream
        _visionSearchController.add(finalResponse);

        // Call the original callback
        onVisionSearchCompleted(finalResponse);
      },
    );
  }

  // ✅ NEW: Dispose method
  void dispose() {
    _visionSearchController.close();
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

// ── ClearChatHistoryUseCase ────────────────────────────────────
class ClearChatHistoryUseCase implements UseCase<void, NoParams> {
  final AIRepository repository;

  ClearChatHistoryUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(NoParams params) async {
    return await repository.clearChatHistory();
  }
}
