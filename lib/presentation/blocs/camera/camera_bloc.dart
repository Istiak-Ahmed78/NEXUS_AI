import 'dart:io';
import 'package:camera/camera.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'camera_event.dart';
part 'camera_state.dart';

class CameraBloc extends Bloc<CameraEvent, CameraState> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;

  CameraBloc() : super(CameraInitial()) {
    on<InitializeCameraEvent>(_onInitializeCamera);
    on<SwitchCameraEvent>(_onSwitchCamera);
    on<CapturePhotoEvent>(_onCapturePhoto);
    on<DisposeCameraEvent>(_onDisposeCamera);
  }

  CameraController? get controller => _controller;

  Future<void> _onInitializeCamera(
    InitializeCameraEvent event,
    Emitter<CameraState> emit,
  ) async {
    try {
      if (_controller != null && _controller!.value.isInitialized) {
        emit(CameraReady(controller: _controller!));
        return;
      }

      emit(CameraLoading());

      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }

      _currentCameraIndex = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_currentCameraIndex == -1) _currentCameraIndex = 0;

      await _initController(_cameras[_currentCameraIndex]);

      emit(CameraReady(controller: _controller!));
    } catch (e) {
      emit(CameraError(e.toString()));
    }
  }

  Future<void> _onSwitchCamera(
    SwitchCameraEvent event,
    Emitter<CameraState> emit,
  ) async {
    try {
      emit(CameraLoading());

      await _controller?.dispose();

      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;

      await _initController(_cameras[_currentCameraIndex]);

      emit(CameraReady(controller: _controller!));
    } catch (e) {
      emit(CameraError(e.toString()));
    }
  }

  Future<void> _onCapturePhoto(
    CapturePhotoEvent event,
    Emitter<CameraState> emit,
  ) async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        emit(const CameraError('Camera not ready'));
        return;
      }

      final currentState = state;

      // ✅ Pause preview BEFORE capture to reduce buffer pressure
      try {
        await _controller!.pausePreview();
      } catch (e) {
        print('⚠️ Could not pause preview: $e');
      }

      // Emit capturing state
      if (currentState is CameraReady) {
        emit(CameraCapturing(controller: _controller!));
      }

      final XFile file = await _controller!.takePicture();
      final imageFile = File(file.path);

      // ✅ Resume preview AFTER capture
      try {
        await _controller!.resumePreview();
      } catch (e) {
        print('⚠️ Could not resume preview: $e');
      }

      emit(CameraPhotoCaptured(controller: _controller!, imageFile: imageFile));
    } catch (e) {
      // Make sure to resume preview even if capture fails
      try {
        await _controller?.resumePreview();
      } catch (_) {}
      emit(CameraError(e.toString()));
    }
  }

  Future<void> _onDisposeCamera(
    DisposeCameraEvent event,
    Emitter<CameraState> emit,
  ) async {
    await _controller?.dispose();
    _controller = null;
    emit(CameraInitial());
  }

  /// ✅ Optimized initialization
  Future<void> _initController(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.low, // Low resolution for preview
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _controller!.initialize();
  }

  @override
  Future<void> close() async {
    await _controller?.dispose();
    return super.close();
  }
}
