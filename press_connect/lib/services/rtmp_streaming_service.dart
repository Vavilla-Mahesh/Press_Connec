import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:rtmp_broadcaster/rtmp_broadcaster.dart';
import 'package:permission_handler/permission_handler.dart';
import 'live_service.dart';
import 'watermark_service.dart';

class RTMPStreamingService extends ChangeNotifier {
  RtmpBroadcaster? _broadcaster;
  bool _isStreaming = false;
  bool _isInitialized = false;
  String? _errorMessage;
  
  // Stream configuration
  int _bitrate = 2000; // kbps
  int _width = 1280;
  int _height = 720;
  int _fps = 30;
  
  // Getters
  bool get isStreaming => _isStreaming;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  
  // Stream quality getters
  int get bitrate => _bitrate;
  int get width => _width;
  int get height => _height;
  int get fps => _fps;
  
  /// Initialize RTMP broadcaster
  Future<bool> initialize() async {
    try {
      // Request permissions
      final permissions = await _requestPermissions();
      if (!permissions) {
        _setError('Required permissions not granted');
        return false;
      }
      
      // Initialize broadcaster
      _broadcaster = RtmpBroadcaster();
      
      _isInitialized = true;
      notifyListeners();
      return true;
    } catch (e) {
      _setError('Failed to initialize broadcaster: $e');
      return false;
    }
  }
  
  /// Start streaming to RTMP endpoint
  Future<bool> startStreaming({
    required CameraController cameraController,
    required LiveStreamInfo streamInfo,
    WatermarkService? watermarkService,
  }) async {
    if (!_isInitialized || _broadcaster == null) {
      _setError('Broadcaster not initialized');
      return false;
    }
    
    if (_isStreaming) {
      _setError('Already streaming');
      return false;
    }
    
    try {
      // Configure stream parameters
      final rtmpUrl = streamInfo.rtmpUrl;
      
      if (kDebugMode) {
        print('Starting RTMP stream to: $rtmpUrl');
        print('Stream config: ${_width}x$_height @ ${_fps}fps, ${_bitrate}kbps');
      }
      
      // Prepare camera for streaming
      if (!cameraController.value.isInitialized) {
        await cameraController.initialize();
      }
      
      // Start the RTMP broadcaster
      await _broadcaster!.startStream(
        url: rtmpUrl,
        bitrate: _bitrate,
        width: _width,
        height: _height,
        fps: _fps,
      );
      
      // Connect camera to broadcaster
      await _broadcaster!.startVideoStreaming(cameraController);
      
      // Enable audio streaming
      await _broadcaster!.startAudioStreaming();
      
      _isStreaming = true;
      _setError(null);
      notifyListeners();
      
      if (kDebugMode) {
        print('RTMP streaming started successfully');
      }
      
      return true;
    } catch (e) {
      _setError('Failed to start streaming: $e');
      if (kDebugMode) {
        print('RTMP streaming error: $e');
      }
      return false;
    }
  }
  
  /// Stop streaming
  Future<void> stopStreaming({CameraController? cameraController}) async {
    try {
      // Stop RTMP broadcaster
      if (_broadcaster != null && _isStreaming) {
        await _broadcaster!.stopStream();
      }
      
      _stopStreaming();
    } catch (e) {
      _setError('Error stopping stream: $e');
    }
  }
  
  /// Update stream quality settings
  void updateStreamQuality({
    int? bitrate,
    int? width,
    int? height,
    int? fps,
  }) {
    if (bitrate != null) _bitrate = bitrate;
    if (width != null) _width = width;
    if (height != null) _height = height;
    if (fps != null) _fps = fps;
    notifyListeners();
  }
  
  /// Set predefined quality preset
  void setQualityPreset(StreamQuality quality) {
    switch (quality) {
      case StreamQuality.low:
        updateStreamQuality(
          bitrate: 800,
          width: 640,
          height: 480,
          fps: 15,
        );
        break;
      case StreamQuality.medium:
        updateStreamQuality(
          bitrate: 1500,
          width: 854,
          height: 480,
          fps: 30,
        );
        break;
      case StreamQuality.high:
        updateStreamQuality(
          bitrate: 2500,
          width: 1280,
          height: 720,
          fps: 30,
        );
        break;
      case StreamQuality.ultra:
        updateStreamQuality(
          bitrate: 4000,
          width: 1920,
          height: 1080,
          fps: 30,
        );
        break;
    }
  }
  
  /// Request necessary permissions
  Future<bool> _requestPermissions() async {
    final permissions = [
      Permission.camera,
      Permission.microphone,
    ];
    
    final statuses = await permissions.request();
    
    return statuses.values.every((status) => status == PermissionStatus.granted);
  }
  
  /// Take a snapshot during streaming
  Future<String?> takeSnapshot({required CameraController cameraController}) async {
    if (!_isStreaming) {
      _setError('Cannot take snapshot: not streaming');
      return null;
    }

    try {
      // Take a picture using the camera controller
      final image = await cameraController.takePicture();
      
      if (kDebugMode) {
        print('Snapshot taken: ${image.path}');
      }
      
      return image.path;
    } catch (e) {
      _setError('Failed to take snapshot: $e');
      if (kDebugMode) {
        print('Snapshot error: $e');
      }
      return null;
    }
  }

  /// Start recording the stream (local recording)
  Future<bool> startRecording({required CameraController cameraController}) async {
    if (!_isStreaming) {
      _setError('Cannot start recording: not streaming');
      return false;
    }

    try {
      // Start video recording
      await cameraController.startVideoRecording();
      
      if (kDebugMode) {
        print('Recording started');
      }
      
      return true;
    } catch (e) {
      _setError('Failed to start recording: $e');
      if (kDebugMode) {
        print('Recording start error: $e');
      }
      return false;
    }
  }

  /// Stop recording and return the file path
  Future<String?> stopRecording({required CameraController cameraController}) async {
    try {
      final file = await cameraController.stopVideoRecording();
      
      if (kDebugMode) {
        print('Recording stopped: ${file.path}');
      }
      
      return file.path;
    } catch (e) {
      _setError('Failed to stop recording: $e');
      if (kDebugMode) {
        print('Recording stop error: $e');
      }
      return null;
    }
  }
  
  void _stopStreaming() {
    _isStreaming = false;
    notifyListeners();
  }

  void _setError(String? error) {
    _errorMessage = error;
    if (error != null) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stopStreaming();
    _broadcaster?.dispose();
    super.dispose();
  }
}

/// Stream quality presets
enum StreamQuality {
  low,    // 640x480, 15fps, 800kbps
  medium, // 854x480, 30fps, 1500kbps  
  high,   // 1280x720, 30fps, 2500kbps
  ultra,  // 1920x1080, 30fps, 4000kbps
}

/// Streaming configuration class
class StreamingConfig {
  final String rtmpUrl;
  final int width;
  final int height;
  final int bitrate;
  final int fps;
  final bool enableAudio;
  Map<String, dynamic>? watermarkConfig;
  
  StreamingConfig({
    required this.rtmpUrl,
    required this.width,
    required this.height,
    required this.bitrate,
    required this.fps,
    this.enableAudio = true,
    this.watermarkConfig,
  });
}