import 'package:flutter/foundation.dart';
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

  Future<bool> initialize() async {
    if (_state != StreamingState.idle) {
      return false;
    }

    _setState(StreamingState.initializing);

    try {
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
        _handleError('Camera error: ${_cameraController!.value.errorDescription}');
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
    _rtmpUrl = rtmpUrl; // Set RTMP URL before any checks
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
      // Use the correct method from rtmp_broadcaster
      await _cameraController!.startVideoStreaming(rtmpUrl);

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
    _cameraController?.dispose();
    super.dispose();
  }
}