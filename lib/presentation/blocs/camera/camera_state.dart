part of 'camera_bloc.dart';

abstract class CameraState extends Equatable {
  const CameraState();

  @override
  List<Object?> get props => [];
}

class CameraInitial extends CameraState {}

class CameraLoading extends CameraState {}

class CameraReady extends CameraState {
  final CameraController controller;

  const CameraReady({required this.controller});

  @override
  List<Object?> get props => [controller];
}

class CameraCapturing extends CameraState {
  final CameraController controller;

  const CameraCapturing({required this.controller});

  @override
  List<Object?> get props => [controller];
}

class CameraPhotoCaptured extends CameraState {
  final CameraController controller;
  final File imageFile;

  const CameraPhotoCaptured({
    required this.controller,
    required this.imageFile,
  });

  @override
  List<Object?> get props => [controller, imageFile];
}

class CameraError extends CameraState {
  final String message;

  const CameraError(this.message);

  @override
  List<Object?> get props => [message];
}
