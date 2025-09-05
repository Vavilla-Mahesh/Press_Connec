import 'package:flutter/foundation.dart';
import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:flutter/material.dart';

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

class StreamingService extends ChangeNotifier
    implements ApiVideoLiveStreamEventsListener {
  ApiVideoLiveStreamController? _controller;
  StreamingState _state = StreamingState.idle;
  String? _errorMessage;
  String? _streamKey;
  String? _rtmpUrl;
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

  // Required by ApiVideoLiveStreamEventsListener
  @override
  void Function(Size)? get onVideoSizeChanged => null;
  @override
  VoidCallback? get onConnectionSuccess => () {
    _isHealthy = true;
    _retryCount = 0;
    _clearError();
    if (kDebugMode) {
      print('StreamingService: Connection successful');
    }
    notifyListeners();
  };
  @override
  void Function(String)? get onConnectionFailed => (reason) {
    _isHealthy = false;
    _handleError('Connection failed: $reason');
    _attemptReconnection();
  };
  @override
  VoidCallback? get onDisconnection => () {
    _isHealthy = false;
    if (_state == StreamingState.streaming) {
      if (kDebugMode) {
        print('StreamingService: Unexpected disconnection, attempting to reconnect');
      }
      _attemptReconnection();
    }
    notifyListeners();
  };
  @override
  void Function(Exception)? get onError => (error) {
    _frameDropCount++;
    _handleError('Stream error: $error');
    if (error.toString().toLowerCase().contains('connection') ||
        error.toString().toLowerCase().contains('network')) {
      _attemptReconnection();
    }
  };

  // Getters
  StreamingState get state => _state;
  String? get errorMessage => _errorMessage;
  ApiVideoLiveStreamController? get controller => _controller;
  bool get isStreaming => _controller != null && (_controller!.isStreaming == true);
  bool get canStartStream => _state == StreamingState.ready && _streamKey != null;
  bool get canStopStream => _state == StreamingState.streaming;
  bool get isInitialized => _controller?.isInitialized ?? false;
  StreamQuality get quality => _quality;
  bool get isHealthy => _isHealthy;
  int get retryCount => _retryCount;
  double get currentBitrate => _currentBitrate;
  int get frameDropCount => _frameDropCount;
  Duration? get streamDuration => _streamStartTime != null 
      ? DateTime.now().difference(_streamStartTime!) : null;

  /// Initialize the streaming service with ApiVideoLiveStreamController
  Future<bool> initializeStreaming(String streamKey, {String? rtmpUrl}) async {
    if (_state != StreamingState.idle) {
      _handleError('Streaming service already initialized');
      return false;
    }

    _setState(StreamingState.initializing);
    _streamKey = streamKey;
    _rtmpUrl = rtmpUrl;

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
      );

      // Add event listener
      _controller!.addEventsListener(this);

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
  // Key updates to the streaming_service.dart - specifically the startYouTubeStream method

  /// Start YouTube Live streaming with improved connection handling
  Future<bool> startYouTubeStream() async {
    if (!canStartStream || _streamKey == null) {
      _handleError('Cannot start stream: invalid state or missing stream key');
      return false;
    }

    _setState(StreamingState.connecting);
    _retryCount = 0;

    try {
      if (kDebugMode) {
        print('StreamingService: Starting RTMP stream to YouTube...');
        print('Stream key: ${_streamKey!.substring(0, 8)}...');
        print('RTMP URL: $_rtmpUrl');
      }

      // Start streaming with stream key and RTMP URL
      if (_rtmpUrl != null && _rtmpUrl!.isNotEmpty) {
        await _controller!.startStreaming(streamKey: _streamKey!, url: _rtmpUrl!);
      } else {
        // Fallback to YouTube's default RTMP endpoint
        await _controller!.startStreaming(
            streamKey: _streamKey!,
            url: 'rtmp://a.rtmp.youtube.com/live2'
        );
      }

      // Start connection monitoring immediately
      _startConnectionMonitoring();

      // Give the RTMP connection a moment to establish
      await Future.delayed(const Duration(seconds: 2));

      // Verify the stream is actually running
      bool isStreaming = await _controller!.isStreaming;

      if (isStreaming) {
        _streamStartTime = DateTime.now();
        _setState(StreamingState.streaming);
        _clearError();

        if (kDebugMode) {
          print('StreamingService: RTMP stream started successfully');
        }

        return true;
      } else {
        _handleError('RTMP stream failed to start - connection not established');
        return false;
      }

    } catch (e) {
      _handleError('Failed to start YouTube stream: $e');

      if (kDebugMode) {
        print('StreamingService: RTMP start error details: $e');
      }

      return false;
    }
  }

  /// Enhanced connection monitoring with better health checks
  Future<void> _checkConnectionHealth() async {
    if (_controller == null) {
      _isHealthy = false;
      return;
    }

    try {
      // Check if we're still streaming
      bool isStreaming = await _controller!.isStreaming;

      if (!isStreaming && _state == StreamingState.streaming) {
        // Stream dropped unexpectedly
        _isHealthy = false;
        _handleError('RTMP connection lost');
        await _attemptReconnection();
        return;
      }

      _isHealthy = isStreaming;

      // Update metrics if still streaming
      if (isStreaming) {
        _updateStreamMetrics();
      }

      notifyListeners();

    } catch (e) {
      _isHealthy = false;
      if (kDebugMode) {
        print('StreamingService: Health check error: $e');
      }

      if (_state == StreamingState.streaming) {
        _handleError('Connection health check failed: $e');
      }
    }
  }

  /// Improved reconnection logic with exponential backoff
  Future<void> _attemptReconnection() async {
    if (_retryCount >= _maxRetries) {
      _handleError('Maximum retry attempts reached. Stream connection lost.');
      return;
    }

    _setState(StreamingState.reconnecting);
    _retryCount++;

    // Exponential backoff: 3s, 6s, 12s, 24s, 48s
    final delay = Duration(seconds: (3 * (1 << (_retryCount - 1))).clamp(3, 60));

    if (kDebugMode) {
      print('StreamingService: Attempting reconnection $_retryCount/$_maxRetries after ${delay.inSeconds}s delay');
    }

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () async {
      try {
        // First, make sure we stop the current stream cleanly
        if (_controller != null) {
          try {
            bool wasStreaming = await _controller!.isStreaming;
            if (wasStreaming) {
              await _controller!.stopStreaming();
              // Wait for clean shutdown
              await Future.delayed(const Duration(seconds: 1));
            }
          } catch (e) {
            if (kDebugMode) {
              print('StreamingService: Error stopping stream during reconnection: $e');
            }
          }
        }

        // Wait a moment before restarting
        await Future.delayed(const Duration(seconds: 1));

        // Restart streaming
        if (_streamKey != null) {
          if (_rtmpUrl != null && _rtmpUrl!.isNotEmpty) {
            await _controller!.startStreaming(streamKey: _streamKey!, url: _rtmpUrl!);
          } else {
            await _controller!.startStreaming(
                streamKey: _streamKey!,
                url: 'rtmp://a.rtmp.youtube.com/live2'
            );
          }

          // Verify the reconnection worked
          await Future.delayed(const Duration(seconds: 2));
          bool isStreaming = await _controller!.isStreaming;

          if (isStreaming) {
            _setState(StreamingState.streaming);
            _isHealthy = true;
            _clearError();

            if (kDebugMode) {
              print('StreamingService: Reconnection successful');
            }
          } else {
            throw Exception('Stream restart failed - not streaming after restart');
          }
        } else {
          throw Exception('No stream key available for reconnection');
        }
      } catch (e) {
        if (kDebugMode) {
          print('StreamingService: Reconnection attempt $_retryCount failed: $e');
        }

        // Try again if we haven't exceeded max retries
        if (_retryCount < _maxRetries) {
          await Future.delayed(const Duration(seconds: 2));
          await _attemptReconnection();
        } else {
          _handleError('All reconnection attempts failed: $e');
        }
      }
    });
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
      // Note: The actual apivideo package may not have setVideoConfig method
      // This would need to be implemented by recreating the controller
      // For now, we'll just update the internal state
      
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

  /// Get video configuration for streaming quality
  VideoConfig _getVideoConfig(StreamQuality quality) {
    int bitrate;
    Resolution resolution;

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
    );
  }

  AudioConfig _getAudioConfig() {
    return AudioConfig(
      bitrate: 128000, // 128 kbps
      channel: Channel.stereo,
      sampleRate: SampleRate.kHz_11,
      enableEchoCanceler: true,
      enableNoiseSuppressor: true,
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
  // Future<void> _checkConnectionHealth() async {
  //   if (_controller == null || !(await _controller!.isStreaming)) {
  //     _isHealthy = false;
  //     return;
  //   }
  //   try {
  //     // Basic health check - if we're still streaming, we're healthy
  //     _isHealthy = await _controller!.isStreaming;
  //     // Update metrics (placeholder - actual implementation would depend on package APIs)
  //     _updateStreamMetrics();
  //     if (!_isHealthy && _state == StreamingState.streaming) {
  //       _handleError('Connection health check failed');
  //       await _attemptReconnection();
  //     }
  //     notifyListeners();
  //   } catch (e) {
  //     _isHealthy = false;
  //     if (kDebugMode) {
  //       print('StreamingService: Health check error: $e');
  //     }
  //   }
  // }

  /// Update stream metrics (placeholder implementation)
  void _updateStreamMetrics() {
    // This would be implemented based on available APIs from the package
    // For now, simulate some basic metrics
    if (isStreaming) {
      _currentBitrate = _getVideoConfig(_quality).bitrate.toDouble();
    }
  }

  /// Attempt to reconnect the stream
  // Future<void> _attemptReconnection() async {
  //   if (_retryCount >= _maxRetries) {
  //     _handleError('Maximum retry attempts reached. Please restart the stream.');
  //     return;
  //   }
  //   _setState(StreamingState.reconnecting);
  //   _retryCount++;
  //   if (kDebugMode) {
  //     print('StreamingService: Attempting reconnection (attempt $_retryCount/$_maxRetries)');
  //   }
  //   _retryTimer?.cancel();
  //   _retryTimer = Timer(_retryDelay, () async {
  //     try {
  //       // Stop current stream if running
  //       if (await _controller!.isStreaming) {
  //         await _controller!.stopStreaming();
  //       }
  //       // Wait a moment before restarting
  //       await Future.delayed(const Duration(seconds: 1));
  //       // Restart streaming
  //       if (_streamKey != null) {
  //         if (_rtmpUrl != null) {
  //           await _controller!.startStreaming(streamKey: _streamKey!, url: _rtmpUrl!);
  //         } else {
  //           await _controller!.startStreaming(streamKey: _streamKey!);
  //         }
  //         _setState(StreamingState.streaming);
  //         _clearError();
  //         if (kDebugMode) {
  //           print('StreamingService: Reconnection successful');
  //         }
  //       }
  //     } catch (e) {
  //       if (kDebugMode) {
  //         print('StreamingService: Reconnection failed: $e');
  //       }
  //       // Try again if we haven't exceeded max retries
  //       if (_retryCount < _maxRetries) {
  //         await Future.delayed(const Duration(seconds: 2));
  //         await _attemptReconnection();
  //       } else {
  //         _handleError('Reconnection failed after $_maxRetries attempts: $e');
  //       }
  //     }
  //   });
  // }


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
    _rtmpUrl = null;
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
    _controller?.removeEventsListener(this);
    _controller?.dispose();
    super.dispose();
  }
}

enum ConnectionStatus {
  connected,
  connecting,
  disconnected,
}