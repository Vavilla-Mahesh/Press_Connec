import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:rtmp_broadcaster/rtmp_broadcaster.dart';
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
  RTMPBroadcaster? _broadcaster;
  CameraController? _cameraController;
  StreamingState _state = StreamingState.idle;
  String? _errorMessage;
  String? _rtmpUrl;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;
  
  // Getters
  StreamingState get state => _state;
  String? get errorMessage => _errorMessage;
  CameraController? get cameraController => _cameraController;
  bool get isStreaming => _state == StreamingState.streaming;
  bool get canStartStream => _state == StreamingState.ready && _rtmpUrl != null;
  bool get canStopStream => _state == StreamingState.streaming;
  bool get isCameraInitialized => _cameraController?.value.isInitialized ?? false;
  List<CameraDescription> get cameras => _cameras;
  int get currentCameraIndex => _currentCameraIndex;
  
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
      
      // Initialize cameras
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _handleError('No cameras available');
        return false;
      }
      
      // Initialize camera controller
      await _initializeCamera();
      
      // Initialize RTMP broadcaster
      _broadcaster = RTMPBroadcaster();
      
      _setState(StreamingState.ready);
      return true;
    } catch (e) {
      _handleError('Initialization failed: $e');
      return false;
    }
  }
  
  Future<void> _initializeCamera() async {
    try {
      _cameraController?.dispose();
      
      _cameraController = CameraController(
        _cameras[_currentCameraIndex],
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      await _cameraController!.initialize();
      notifyListeners();
    } catch (e) {
      throw Exception('Camera initialization failed: $e');
    }
  }
  
  Future<bool> switchCamera() async {
    if (_cameras.length <= 1 || _state == StreamingState.streaming) {
      return false;
    }
    
    try {
      _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;
      await _initializeCamera();
      return true;
    } catch (e) {
      _handleError('Failed to switch camera: $e');
      return false;
    }
  }
  
  Future<bool> startStreaming(String rtmpUrl) async {
    if (!canStartStream || _cameraController == null) {
      _handleError('Cannot start streaming in current state');
      return false;
    }

    try {
      _rtmpUrl = rtmpUrl;
      
      // Start RTMP streaming with the camera
      // Note: The actual implementation will depend on the specific 
      // rtmp_broadcaster package API. This is a placeholder that
      // follows common patterns.
      await _broadcaster!.startStream(
        rtmpUrl: rtmpUrl,
        width: AppConfig.defaultResolution['width']!,
        height: AppConfig.defaultResolution['height']!,
        bitrate: AppConfig.defaultBitrate,
        fps: 30,
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
      await _broadcaster!.stopStream();
      
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
    _broadcaster?.dispose();
    _cameraController?.dispose();
    super.dispose();
  }
}