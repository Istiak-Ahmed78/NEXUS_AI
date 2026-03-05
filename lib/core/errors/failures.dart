import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;

  const Failure(this.message);

  @override
  List<Object> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class SpeechRecognitionFailure extends Failure {
  const SpeechRecognitionFailure(super.message);
}

class TTSFailure extends Failure {
  const TTSFailure(super.message);
}

class PermissionFailure extends Failure {
  const PermissionFailure(super.message);
}
