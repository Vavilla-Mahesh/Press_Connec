import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rtmp_broadcaster/camera.dart';
import 'package:permission_handler/permission_handler.dart';

enum StreamingState {
  idle,
  initializing,
  ready,
  streaming,
  stopping,
  error
}

class RTMPStreamingService extends ChangeNotifier {
  CameraController? _cameraController;
  StreamingState _state = StreamingState.idle;
  String? _errorMessage;
  String? _rtmpUrl;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  // Getters
  StreamingState get state => _state;
  String? get errorMessage => _errorMessage;
  CameraController? get cameraController => _cameraController;
  bool get isStreaming => _cameraController?.value.isStreamingVideoRtmp ?? false;
  bool get canStartStream => _state == StreamingState.ready && _rtmpUrl != null && !isStreaming;
  bool get canStopStream => isStreaming;
  bool get isCameraInitialized => _cameraController?.value.isInitialized ?? false;
  double _currentRotationRadians = 0.0;

  double get currentRotationRadians => _currentRotationRadians;

  Future<bool> initialize() async {
    if (_state != StreamingState.idle) {
      return false;
    }

    _setState(StreamingState.initializing);

    try {
      // Force landscape orientation for streaming
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // Request permissions
      final cameraPermission = await Permission.camera.request();
      final microphonePermission = await Permission.microphone.request();

      if (cameraPermission != PermissionStatus.granted) {
        _handleError('Camera permission denied');
        return false;
      }

      if (microphonePermission != PermissionStatus.granted) {
        _handleError('Microphone permission denied');
        return false;
      }

      // Get available cameras
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        _handleError('No cameras found');
        return false;
      }

      // Initialize camera with the first available camera (usually back camera)
      await _initializeCamera(_selectedCameraIndex);

      _setState(StreamingState.ready);
      return true;
    } catch (e) {
      _handleError('Initialization failed: $e');
      return false;
    }
  }

  Future<void> _initializeCamera(int cameraIndex) async {
    // Dispose previous controller if exists
    await _cameraController?.dispose();

    _cameraController = CameraController(
      _cameras[cameraIndex],
      ResolutionPreset.high,
      enableAudio: true,
      androidUseOpenGL: true,
    );

    // Add listener for camera events
    _cameraController!.addListener(() {
      if (_cameraController!.value.hasError) {
        _handleError('Camera error: [32m${_cameraController!.value.errorDescription}[0m');
      } else {
        // Handle RTMP events
        try {
          final Map<dynamic, dynamic> event = _cameraController!.value.event as Map<dynamic, dynamic>;
          final String eventType = event['eventType'] as String;
          if (eventType == 'rtmp_retry') {
            _handleError('RTMP connection failed, retrying...');
          } else if (eventType == 'rtmp_stopped') {
            if (_state == StreamingState.streaming) {
              _setState(StreamingState.ready);
            }
          }
        } catch (e) {
          // Event parsing failed, ignore
        }
      }
      notifyListeners();
    });

    await _cameraController!.initialize();

    // Set the correct orientation after initialization
    await _setCorrectOrientation();

    notifyListeners();
  }

  Future<void> _setCorrectOrientation() async {
    if (_cameraController != null && _cameraController!.value.isInitialized== true) {
      return;
    }

    try {
      final camera = _cameras[_selectedCameraIndex];
      final deviceOrientation = await _getDeviceOrientation();
      int rotation = _calculateRotation(camera, deviceOrientation);
      _currentRotationRadians = rotation * 3.141592653589793 / 180.0;
      if (kDebugMode) {
        print('Camera: \u001b[32m${camera.name}\u001b[0m, Device orientation: $deviceOrientation, Applied rotation: $rotation');
      }

      // Apply rotation to the camera controller
      // Note: This depends on your rtmp_broadcaster package version
      // Some packages use setRotation, others might use different methods
      // await _cameraController!.setRotation(rotation); // Removed as not supported

    } catch (e) {
      if (kDebugMode) {
        print('Failed to set camera orientation: $e');
      }
    }
  }

  Future<DeviceOrientation> _getDeviceOrientation() async {
    // This is a simplified approach - you might need platform channels for more accurate detection
    return DeviceOrientation.landscapeLeft; // Default for your use case
  }

  int _calculateRotation(CameraDescription camera, DeviceOrientation deviceOrientation) {
    // Standard rotation calculations for Android/iOS
    int sensorOrientation = camera.sensorOrientation ?? 0;
    bool isFrontCamera = camera.lensDirection == CameraLensDirection.front;

    int rotation;

    switch (deviceOrientation) {
      case DeviceOrientation.portraitUp:
        rotation = sensorOrientation;
        break;
      case DeviceOrientation.portraitDown:
        rotation = (sensorOrientation + 180) % 360;
        break;
      case DeviceOrientation.landscapeLeft:
        rotation = (sensorOrientation + 90) % 360;
        break;
      case DeviceOrientation.landscapeRight:
        rotation = (sensorOrientation - 90 + 360) % 360;
        break;
    }

    // For front camera, we need to mirror the rotation
    if (isFrontCamera) {
      rotation = (360 - rotation) % 360;
    }

    return rotation;
  }

  Future<bool> switchCamera() async {
    if (_state == StreamingState.streaming || _cameras.length < 2) {
      return false;
    }

    try {
      // Switch to the next available camera
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
      await _initializeCamera(_selectedCameraIndex);
      return true;
    } catch (e) {
      _handleError('Failed to switch camera: $e');
      return false;
    }
  }

  Future<bool> startStreaming(String rtmpUrl) async {
    _rtmpUrl = rtmpUrl;
    final controller = _cameraController;
    final isInitialized = controller?.value.isInitialized ?? false;

    if (!canStartStream) {
      if (kDebugMode) print('Cannot start: canStartStream is false. State=$_state, rtmpUrl=$_rtmpUrl, isStreaming=$isStreaming');
    }
    if (controller == null) {
      if (kDebugMode) print('Cannot start: CameraController is null');
    }
    if (!isInitialized) {
      if (kDebugMode) print('Cannot start: CameraController is not initialized');
    }

    if (!canStartStream || controller == null || !isInitialized) {
      _handleError('Cannot start streaming in current state');
      return false;
    }

    try {
      // Ensure correct orientation before starting stream
      await _setCorrectOrientation();

      // Use the correct method from rtmp_broadcaster with orientation settings
      await _cameraController!.startVideoStreaming(
        rtmpUrl,
        // Add these parameters if your package supports them
        // width: 1920,
        // height: 1080,
        // fps: 30,
        // bitrate: 2500000,
      );

      _setState(StreamingState.streaming);
      return true;
    } catch (e) {
      _handleError('Failed to start streaming: $e');
      return false;
    }
  }

  Future<bool> stopStreaming() async {
    if (!canStopStream) {
      return true;
    }

    _setState(StreamingState.stopping);

    try {
      await _cameraController!.stopVideoStreaming();
      _setState(StreamingState.ready);
      return true;
    } catch (e) {
      _handleError('Failed to stop streaming: $e');
      return false;
    }
  }

  Future<bool> pauseStreaming() async {
    if (!isStreaming) {
      return false;
    }

    try {
      await _cameraController!.pauseVideoStreaming();
      return true;
    } catch (e) {
      _handleError('Failed to pause streaming: $e');
      return false;
    }
  }

  Future<bool> resumeStreaming() async {
    final controller = _cameraController;
    final isPaused = controller?.value.isStreamingPaused ?? false;
    if (!isPaused) {
      return false;
    }
    try {
      await controller!.resumeVideoStreaming();
      return true;
    } catch (e) {
      _handleError('Failed to resume streaming: $e');
      return false;
    }
  }

  Future<void> takeSnapshot() async {
    final controller = _cameraController;
    final isInitialized = controller?.value.isInitialized ?? false;
    if (controller == null || !isInitialized) {
      throw Exception('Camera not initialized');
    }
    try {
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String filePath = '/storage/emulated/0/Pictures/snapshot_$timestamp.jpg';
      await controller.takePicture(filePath);
      if (kDebugMode) {
        print('Snapshot saved to: $filePath');
      }
    } catch (e) {
      throw Exception('Failed to take snapshot: $e');
    }
  }

  // Method to manually fix orientation if needed
  Future<void> fixOrientation() async {
    if (_cameraController != null && _cameraController!.value.isInitialized== true) {
      await _setCorrectOrientation();
      notifyListeners();
    }
  }

  void setRtmpUrl(String url) {
    _rtmpUrl = url;
    notifyListeners();
  }

  void reset() {
    _rtmpUrl = null;
    _errorMessage = null;
    if (_state != StreamingState.streaming) {
      _setState(StreamingState.idle);
    }
  }

  void _setState(StreamingState state) {
    _state = state;
    notifyListeners();
  }

  void _handleError(String error) {
    _state = StreamingState.error;
    _errorMessage = error;
    notifyListeners();

    if (kDebugMode) {
      print('RTMPStreamingService Error: $error');
    }
  }

  void clearError() {
    if (_state == StreamingState.error) {
      _errorMessage = null;
      _setState(StreamingState.ready);
    }
  }

  // Get current camera description
  CameraDescription? get currentCamera {
    if (_cameras.isEmpty || _selectedCameraIndex >= _cameras.length) {
      return null;
    }
    return _cameras[_selectedCameraIndex];
  }

  // Check if front camera is being used
  bool get isFrontCamera {
    return currentCamera?.lensDirection == CameraLensDirection.front;
  }

  // Check if back camera is being used
  bool get isBackCamera {
    return currentCamera?.lensDirection == CameraLensDirection.back;
  }

  // Check if streaming is paused
  bool get isStreamingPaused => _cameraController?.value.isStreamingPaused ?? false;

  @override
  void dispose() {
    // Restore orientation to all when disposing
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _cameraController?.dispose();
    super.dispose();
  }
}