import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

enum StreamingState {
  idle,
  initializing,
  ready,
  connecting,
  streaming,
  stopping,
  error,
  reconnecting
}

enum StreamQuality {
  low,    // 480p, 1Mbps
  medium, // 720p, 2.5Mbps  
  high,   // 1080p, 4Mbps
  auto    // Adaptive quality
}

class StreamingService extends ChangeNotifier {
  ApiVideoLiveStreamController? _controller;
  StreamingState _state = StreamingState.idle;
  String? _errorMessage;
  String? _streamKey;
  StreamQuality _quality = StreamQuality.medium;
  
  // Connection monitoring
  Timer? _connectionMonitor;
  Timer? _retryTimer;
  int _retryCount = 0;
  static const int _maxRetries = 5;
  static const Duration _retryDelay = Duration(seconds: 3);
  static const Duration _connectionCheckInterval = Duration(seconds: 5);
  
  // Stream health metrics
  bool _isHealthy = false;
  DateTime? _streamStartTime;
  int _frameDropCount = 0;
  double _currentBitrate = 0.0;

  // Getters
  StreamingState get state => _state;
  String? get errorMessage => _errorMessage;
  ApiVideoLiveStreamController? get controller => _controller;
  bool get isStreaming => _controller?.isStreaming() ?? false;
  bool get canStartStream => _state == StreamingState.ready && _streamKey != null;
  bool get canStopStream => _state == StreamingState.streaming;
  bool get isInitialized => _controller != null;
  StreamQuality get quality => _quality;
  bool get isHealthy => _isHealthy;
  int get retryCount => _retryCount;
  double get currentBitrate => _currentBitrate;
  int get frameDropCount => _frameDropCount;
  Duration? get streamDuration => _streamStartTime != null 
      ? DateTime.now().difference(_streamStartTime!) : null;

  /// Initialize the streaming service with ApiVideoLiveStreamController
  Future<bool> initializeStreaming(String streamKey) async {
    if (_state != StreamingState.idle) {
      _handleError('Streaming service already initialized');
      return false;
    }

    _setState(StreamingState.initializing);
    _streamKey = streamKey;

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

      // Initialize ApiVideoLiveStreamController
      _controller = ApiVideoLiveStreamController(
        initialAudioConfig: _getAudioConfig(),
        initialVideoConfig: _getVideoConfig(_quality),
        onConnectionSuccess: _onConnectionSuccess,
        onConnectionFailed: _onConnectionFailed,
        onDisconnection: _onDisconnection,
        onError: _onStreamError,
      );

      await _controller!.initialize();
      
      _setState(StreamingState.ready);
      _clearError();
      
      if (kDebugMode) {
        print('StreamingService: Initialized successfully with stream key: ${streamKey.substring(0, 8)}...');
      }
      
      return true;
    } catch (e) {
      _handleError('Failed to initialize streaming: $e');
      return false;
    }
  }

  /// Start YouTube Live streaming
  Future<bool> startYouTubeStream() async {
    if (!canStartStream || _streamKey == null) {
      _handleError('Cannot start stream: invalid state or missing stream key');
      return false;
    }

    _setState(StreamingState.connecting);
    _retryCount = 0;

    try {
      await _controller!.startStreaming(streamKey: _streamKey!);
      
      // Start connection monitoring
      _startConnectionMonitoring();
      
      _streamStartTime = DateTime.now();
      _setState(StreamingState.streaming);
      
      if (kDebugMode) {
        print('StreamingService: Started streaming to YouTube Live');
      }
      
      return true;
    } catch (e) {
      _handleError('Failed to start YouTube stream: $e');
      return false;
    }
  }

  /// Stop streaming
  Future<bool> stopStream() async {
    if (!canStopStream) {
      return true;
    }

    _setState(StreamingState.stopping);

    try {
      // Stop connection monitoring
      _stopConnectionMonitoring();
      
      await _controller!.stopStreaming();
      
      _streamStartTime = null;
      _frameDropCount = 0;
      _currentBitrate = 0.0;
      _isHealthy = false;
      
      _setState(StreamingState.ready);
      
      if (kDebugMode) {
        print('StreamingService: Stream stopped successfully');
      }
      
      return true;
    } catch (e) {
      _handleError('Failed to stop stream: $e');
      return false;
    }
  }

  /// Switch camera (front/back)
  Future<bool> switchCamera() async {
    if (_controller == null || _state == StreamingState.streaming) {
      return false;
    }

    try {
      await _controller!.switchCamera();
      
      if (kDebugMode) {
        print('StreamingService: Camera switched successfully');
      }
      
      return true;
    } catch (e) {
      _handleError('Failed to switch camera: $e');
      return false;
    }
  }

  /// Update stream quality
  Future<bool> updateStreamQuality(StreamQuality quality) async {
    if (_controller == null) {
      return false;
    }

    try {
      _quality = quality;
      final videoConfig = _getVideoConfig(quality);
      await _controller!.setVideoConfig(videoConfig);
      
      if (kDebugMode) {
        print('StreamingService: Quality updated to $quality');
      }
      
      notifyListeners();
      return true;
    } catch (e) {
      _handleError('Failed to update stream quality: $e');
      return false;
    }
  }

  /// Get connection status
  ConnectionStatus getConnectionStatus() {
    if (_controller == null) {
      return ConnectionStatus.disconnected;
    }
    
    if (_state == StreamingState.streaming && _isHealthy) {
      return ConnectionStatus.connected;
    } else if (_state == StreamingState.connecting || _state == StreamingState.reconnecting) {
      return ConnectionStatus.connecting;
    } else {
      return ConnectionStatus.disconnected;
    }
  }

  /// Handle stream errors with retry mechanism
  Future<void> handleStreamErrors() async {
    if (_state == StreamingState.error && _retryCount < _maxRetries) {
      await _attemptReconnection();
    }
  }

  /// Force landscape orientation for video
  VideoConfig _getVideoConfig(StreamQuality quality) {
    Resolution resolution;
    int bitrate;

    switch (quality) {
      case StreamQuality.low:
        resolution = Resolution.RESOLUTION_480;
        bitrate = 1000000; // 1 Mbps
        break;
      case StreamQuality.medium:
        resolution = Resolution.RESOLUTION_720;
        bitrate = 2500000; // 2.5 Mbps
        break;
      case StreamQuality.high:
        resolution = Resolution.RESOLUTION_1080;
        bitrate = 4000000; // 4 Mbps
        break;
      case StreamQuality.auto:
        resolution = Resolution.RESOLUTION_720;
        bitrate = 2500000; // Start with medium, will adapt
        break;
    }

    return VideoConfig(
      bitrate: bitrate,
      resolution: resolution,
      fps: 30,
      // Force landscape orientation (16:9 aspect ratio)
      orientationLockOnStartStreaming: OrientationLock.landscape,
    );
  }

  AudioConfig _getAudioConfig() {
    return const AudioConfig(
      bitrate: 128000, // 128 kbps
      sampleRate: 44100,
      stereo: true,
      echoCanceler: true,
      noiseSuppressor: true,
    );
  }

  /// Start monitoring connection health
  void _startConnectionMonitoring() {
    _connectionMonitor?.cancel();
    _connectionMonitor = Timer.periodic(_connectionCheckInterval, (timer) {
      _checkConnectionHealth();
    });
  }

  /// Stop connection monitoring
  void _stopConnectionMonitoring() {
    _connectionMonitor?.cancel();
    _retryTimer?.cancel();
  }

  /// Check connection health and stream metrics
  void _checkConnectionHealth() {
    if (_controller == null || !isStreaming) {
      _isHealthy = false;
      return;
    }

    try {
      // Get stream statistics (if available in the package)
      // This would depend on the specific API available in apivideo_live_stream
      
      // Basic health check - if we're still streaming, we're healthy
      _isHealthy = _controller!.isStreaming();
      
      // Update metrics (placeholder - actual implementation would depend on package APIs)
      _updateStreamMetrics();
      
      if (!_isHealthy && _state == StreamingState.streaming) {
        _handleError('Connection health check failed');
        _attemptReconnection();
      }
      
      notifyListeners();
    } catch (e) {
      _isHealthy = false;
      if (kDebugMode) {
        print('StreamingService: Health check error: $e');
      }
    }
  }

  /// Update stream metrics (placeholder implementation)
  void _updateStreamMetrics() {
    // This would be implemented based on available APIs from the package
    // For now, simulate some basic metrics
    if (isStreaming) {
      _currentBitrate = _getVideoConfig(_quality).bitrate.toDouble();
    }
  }

  /// Attempt to reconnect the stream
  Future<void> _attemptReconnection() async {
    if (_retryCount >= _maxRetries) {
      _handleError('Maximum retry attempts reached. Please restart the stream.');
      return;
    }

    _setState(StreamingState.reconnecting);
    _retryCount++;

    if (kDebugMode) {
      print('StreamingService: Attempting reconnection (attempt $_retryCount/$_maxRetries)');
    }

    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () async {
      try {
        // Stop current stream if running
        if (_controller!.isStreaming()) {
          await _controller!.stopStreaming();
        }

        // Wait a moment before restarting
        await Future.delayed(const Duration(seconds: 1));

        // Restart streaming
        if (_streamKey != null) {
          await _controller!.startStreaming(streamKey: _streamKey!);
          _setState(StreamingState.streaming);
          _clearError();
          
          if (kDebugMode) {
            print('StreamingService: Reconnection successful');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('StreamingService: Reconnection failed: $e');
        }
        
        // Try again if we haven't exceeded max retries
        if (_retryCount < _maxRetries) {
          await Future.delayed(const Duration(seconds: 2));
          _attemptReconnection();
        } else {
          _handleError('Reconnection failed after $_maxRetries attempts: $e');
        }
      }
    });
  }

  // Event handlers
  void _onConnectionSuccess() {
    _isHealthy = true;
    _retryCount = 0;
    _clearError();
    
    if (kDebugMode) {
      print('StreamingService: Connection successful');
    }
    
    notifyListeners();
  }

  void _onConnectionFailed(String error) {
    _isHealthy = false;
    _handleError('Connection failed: $error');
    
    // Attempt reconnection
    _attemptReconnection();
  }

  void _onDisconnection() {
    _isHealthy = false;
    
    if (_state == StreamingState.streaming) {
      if (kDebugMode) {
        print('StreamingService: Unexpected disconnection, attempting to reconnect');
      }
      _attemptReconnection();
    }
    
    notifyListeners();
  }

  void _onStreamError(String error) {
    _frameDropCount++;
    _handleError('Stream error: $error');
    
    // For critical errors, attempt reconnection
    if (error.toLowerCase().contains('connection') || 
        error.toLowerCase().contains('network')) {
      _attemptReconnection();
    }
  }

  void _setState(StreamingState state) {
    _state = state;
    notifyListeners();
  }

  void _handleError(String error) {
    _state = StreamingState.error;
    _errorMessage = error;
    _isHealthy = false;
    notifyListeners();

    if (kDebugMode) {
      print('StreamingService Error: $error');
    }
  }

  void _clearError() {
    _errorMessage = null;
  }

  /// Clear error and reset to ready state
  void clearError() {
    if (_state == StreamingState.error) {
      _errorMessage = null;
      _setState(StreamingState.ready);
    }
  }

  /// Reset the service to initial state
  void reset() {
    _stopConnectionMonitoring();
    _streamKey = null;
    _errorMessage = null;
    _retryCount = 0;
    _streamStartTime = null;
    _frameDropCount = 0;
    _currentBitrate = 0.0;
    _isHealthy = false;
    
    if (_state != StreamingState.streaming) {
      _setState(StreamingState.idle);
    }
  }

  @override
  void dispose() {
    _stopConnectionMonitoring();
    _controller?.dispose();
    super.dispose();
  }
}

enum ConnectionStatus {
  connected,
  connecting,
  disconnected,
}