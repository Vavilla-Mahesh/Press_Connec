import 'package:flutter/foundation.dart';
import 'package:rtmp_broadcaster/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config.dart';

enum StreamingState {
  idle,
  initializing,
  ready,
  streaming,
  stopping,
  error
}

class RTMPStreamingService extends ChangeNotifier {
  Camera? _camera;
  StreamingState _state = StreamingState.idle;
  String? _errorMessage;
  String? _rtmpUrl;
  
  // Getters
  StreamingState get state => _state;
  String? get errorMessage => _errorMessage;
  Camera? get camera => _camera;
  bool get isStreaming => _state == StreamingState.streaming;
  bool get canStartStream => _state == StreamingState.ready && _rtmpUrl != null;
  bool get canStopStream => _state == StreamingState.streaming;
  bool get isCameraInitialized => _camera != null;
  
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
      
      // Initialize RTMP broadcaster camera
      _camera = Camera();
      await _camera!.initialize(
        preset: CameraPreset.hd720,
        enableAudio: true,
      );
      
      _setState(StreamingState.ready);
      return true;
    } catch (e) {
      _handleError('Initialization failed: $e');
      return false;
    }
  }
  
  Future<bool> switchCamera() async {
    if (_state == StreamingState.streaming) {
      return false;
    }
    
    try {
      await _camera?.switchCamera();
      return true;
    } catch (e) {
      _handleError('Failed to switch camera: $e');
      return false;
    }
  }
  
  Future<bool> startStreaming(String rtmpUrl) async {
    if (!canStartStream || _camera == null) {
      _handleError('Cannot start streaming in current state');
      return false;
    }

    try {
      _rtmpUrl = rtmpUrl;
      
      // Start RTMP streaming with the camera
      await _camera!.startStreaming(
        url: rtmpUrl,
        bitrate: AppConfig.defaultBitrate,
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
      await _camera!.stopStreaming();
      
      _setState(StreamingState.ready);
      return true;
    } catch (e) {
      _handleError('Failed to stop streaming: $e');
      return false;
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
  
  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }
}