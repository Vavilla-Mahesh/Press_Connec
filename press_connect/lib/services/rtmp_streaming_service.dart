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

  // Track device orientation separately from app orientation
  DeviceOrientation _currentDeviceOrientation = DeviceOrientation.landscapeLeft;

  // Getters
  StreamingState get state => _state;
  String? get errorMessage => _errorMessage;
  CameraController? get cameraController => _cameraController;
  bool get isStreaming => _cameraController?.value.isStreamingVideoRtmp ?? false;
  bool get canStartStream => _state == StreamingState.ready && _rtmpUrl != null && !isStreaming;
  bool get canStopStream => isStreaming;
  bool get isCameraInitialized => _cameraController?.value.isInitialized ?? false;

  Future<bool> initialize() async {
    if (_state != StreamingState.idle) {
      return false;
    }

    _setState(StreamingState.initializing);

    try {
      // Set app to landscape but don't lock device orientation yet
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

      // Find back camera first, fallback to first available
      _selectedCameraIndex = _cameras.indexWhere(
              (camera) => camera.lensDirection == CameraLensDirection.back
      );
      if (_selectedCameraIndex == -1) {
        _selectedCameraIndex = 0;
      }

      // Initialize camera with specific settings for landscape streaming
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

    // Initialize camera controller with specific settings
    _cameraController = CameraController(
      _cameras[cameraIndex],
      ResolutionPreset.high,
      enableAudio: true,
      androidUseOpenGL: true,
      // Force the camera to initialize in a way that's compatible with landscape streaming
      // imageFormatGroup: ImageFormatGroup.yuv420,
    );

    // Add listener for camera events
    _cameraController!.addListener(() {
      if (_cameraController!.value.hasError) {
        _handleError('Camera error: ${_cameraController!.value.errorDescription}');
      }
      notifyListeners();
    });

    await _cameraController!.initialize();

    if (kDebugMode) {
      final camera = _cameras[cameraIndex];
      print('Camera initialized: ${camera.name}');
      print('Sensor orientation: ${camera.sensorOrientation}');
      print('Lens direction: ${camera.lensDirection}');
    }

    notifyListeners();
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

    if (!canStartStream || controller == null || !isInitialized) {
      _handleError('Cannot start streaming in current state');
      return false;
    }

    try {
      final camera = _cameras[_selectedCameraIndex];

      if (kDebugMode) {
        print('Starting RTMP stream to: $rtmpUrl');
        print('Camera: ${camera.name}');
        print('Sensor orientation: ${camera.sensorOrientation}');
        print('Is back camera: ${camera.lensDirection == CameraLensDirection.back}');
      }

      // Start streaming with explicit parameters for landscape output
      await controller.startVideoStreaming(
        rtmpUrl,
        bitrate: 2500000, // 2.5 Mbps
        androidUseOpenGL: true,
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

  // Method to get the correct preview orientation for UI display
  double getPreviewRotationRadians() {
    if (_cameraController == null) {
      return 0.0;
    }


    final camera = _cameras[_selectedCameraIndex];
    final sensorOrientation = camera.sensorOrientation ?? 0;
    final isBackCamera = camera.lensDirection == CameraLensDirection.back;

    // Calculate rotation needed for correct preview display in landscape app
    double rotationDegrees = 0.0;

    if (isBackCamera) {
      // For back camera: most Android devices have sensor at 90°
      // We need to rotate to show correctly in landscape UI
      switch (sensorOrientation) {
        case 0:
          rotationDegrees = 90.0; // Portrait sensor, rotate for landscape
          break;
        case 90:
          rotationDegrees = 0.0; // Already landscape oriented
          break;
        case 180:
          rotationDegrees = 270.0;
          break;
        case 270:
          rotationDegrees = 180.0;
          break;
      }
    } else {
      // For front camera: usually needs different rotation due to mirroring
      switch (sensorOrientation) {
        case 0:
          rotationDegrees = 270.0;
          break;
        case 90:
          rotationDegrees = 180.0;
          break;
        case 180:
          rotationDegrees = 90.0;
          break;
        case 270:
          rotationDegrees = 0.0;
          break;
      }
    }

    if (kDebugMode) {
      print('Preview rotation: $rotationDegrees degrees for sensor orientation: $sensorOrientation, back camera: $isBackCamera');
    }

    return rotationDegrees * (3.141592653589793 / 180.0); // Convert to radians
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