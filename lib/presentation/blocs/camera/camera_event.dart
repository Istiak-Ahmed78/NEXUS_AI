part of 'camera_bloc.dart';

abstract class CameraEvent extends Equatable {
  const CameraEvent();

  @override
  List<Object> get props => [];
}

class InitializeCameraEvent extends CameraEvent {}

class SwitchCameraEvent extends CameraEvent {}

class CapturePhotoEvent extends CameraEvent {}

class DisposeCameraEvent extends CameraEvent {}
