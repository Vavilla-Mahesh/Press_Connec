import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:io';
import 'live_service.dart';
import 'native_rtmp_channel.dart';

/// Stream quality configurations for adaptive streaming
enum StreamQuality {
  quality360p(resolution: '360p', bitrate: 1000, fps: 30),
  quality480p(resolution: '480p', bitrate: 1500, fps: 30),
  quality720p(resolution: '720p', bitrate: 2500, fps: 30),
  quality1080p(resolution: '1080p', bitrate: 4000, fps: 30);

  const StreamQuality({
    required this.resolution,
    required this.bitrate,
    required this.fps,
  });

  final String resolution;
  final int bitrate; // kbps
  final int fps;

  String get value => resolution;
  
  ResolutionPreset get cameraResolution {
    switch (this) {
      case StreamQuality.quality360p:
        return ResolutionPreset.low;
      case StreamQuality.quality480p:
        return ResolutionPreset.medium;
      case StreamQuality.quality720p:
        return ResolutionPreset.high;
      case StreamQuality.quality1080p:
        return ResolutionPreset.veryHigh;
    }
  }
}

/// Network condition for adaptive streaming
enum NetworkCondition {
  poor,
  fair, 
  good,
  excellent;

  StreamQuality get recommendedQuality {
    switch (this) {
      case NetworkCondition.poor:
        return StreamQuality.quality360p;
      case NetworkCondition.fair:
        return StreamQuality.quality480p;
      case NetworkCondition.good:
        return StreamQuality.quality720p;
      case NetworkCondition.excellent:
        return StreamQuality.quality1080p;
    }
  }
}

/// Performance optimized direct streaming service with native RTMP capabilities
class DirectStreamingService extends ChangeNotifier {
  bool _isStreaming = false;
  bool _isInitialized = false;
  String? _errorMessage;
  
  // Stream configuration
  StreamQuality _quality = StreamQuality.quality720p;
  NetworkCondition _networkCondition = NetworkCondition.good;
  
  // Performance monitoring
  int _droppedFrames = 0;
  double _averageFrameRate = 0.0;
  int _uploadBandwidth = 0; // kbps
  
  // Memory management
  Timer? _performanceMonitor;
  Timer? _networkMonitor;
  StreamSubscription? _nativeEventsSubscription;
  
  // Fallback options
  bool _adaptiveQualityEnabled = true;
  bool _autoRetryEnabled = true;
  int _retryAttempts = 0;
  final int _maxRetryAttempts = 3;
  
  // Keep reference for retry attempts
  CameraController? _lastCameraController;
  LiveStreamInfo? _currentStream;
  
  // Getters
  bool get isStreaming => _isStreaming;
  bool get isInitialized => _isInitialized;
  String? get errorMessage => _errorMessage;
  StreamQuality get quality => _quality;
  NetworkCondition get networkCondition => _networkCondition;
  bool get adaptiveQualityEnabled => _adaptiveQualityEnabled;
  int get droppedFrames => _droppedFrames;
  double get averageFrameRate => _averageFrameRate;
  int get uploadBandwidth => _uploadBandwidth;

  /// Initialize the streaming service with performance optimizations
  Future<bool> initialize() async {
    try {
      // Request permissions
      final permissions = await _requestPermissions();
      if (!permissions) {
        _setError('Required permissions not granted');
        return false;
      }
      
      // Initialize network monitoring
      _startNetworkMonitoring();
      
      // Set up native streaming events
      _setupNativeEventListening();
      
      _isInitialized = true;
      notifyListeners();
      return true;
    } catch (e) {
      _setError('Failed to initialize streaming service: $e');
      return false;
    }
  }

  /// Start streaming with enhanced error recovery and performance optimization
  Future<bool> startStreaming({
    required CameraController cameraController,
    required LiveStreamInfo streamInfo,
  }) async {
    if (!_isInitialized) {
      _setError('Service not initialized');
      return false;
    }
    
    if (_isStreaming) {
      _setError('Already streaming');
      return false;
    }
    
    return await _attemptStreaming(cameraController, streamInfo);
  }

  /// Attempt streaming with retry logic
  Future<bool> _attemptStreaming(CameraController cameraController, LiveStreamInfo streamInfo) async {
    // Store references for retry attempts
    _lastCameraController = cameraController;
    _currentStream = streamInfo;
    
    try {
      // Optimize camera settings for current network condition
      await _optimizeCameraSettings(cameraController);
      
      // Adjust quality based on network condition if adaptive quality is enabled
      if (_adaptiveQualityEnabled) {
        _quality = _networkCondition.recommendedQuality;
      }
      
      if (kDebugMode) {
        print('Starting optimized stream to: ${streamInfo.rtmpUrl}');
        print('Stream quality: ${_quality.value} (${_quality.bitrate}kbps)');
        print('Network condition: $_networkCondition');
      }
      
      // Prepare camera for streaming with optimized settings
      if (!cameraController.value.isInitialized) {
        await cameraController.initialize();
      }
      
      // Platform-specific RTMP streaming implementation
      final success = await _startNativeRTMPStream(cameraController, streamInfo);
      
      if (success) {
        _isStreaming = true;
        _retryAttempts = 0;
        _startPerformanceMonitoring();
        _setError(null);
        notifyListeners();
        
        if (kDebugMode) {
          print('Native RTMP streaming started successfully');
        }
        
        return true;
      } else {
        throw Exception('Failed to start native RTMP stream');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Streaming attempt failed: $e');
      }
      
      // Retry logic with fallback quality
      if (_autoRetryEnabled && _retryAttempts < _maxRetryAttempts) {
        _retryAttempts++;
        
        // Reduce quality for retry
        if (_quality != StreamQuality.quality360p) {
          _quality = _getReducedQuality(_quality);
          if (kDebugMode) {
            print('Retrying with reduced quality: ${_quality.value}');
          }
        }
        
        // Wait before retry with exponential backoff
        await Future.delayed(Duration(seconds: _retryAttempts * 2));
        return await _attemptStreaming(cameraController, streamInfo);
      }
      
      _setError('Failed to start streaming after $_retryAttempts attempts: $e');
      return false;
    }
  }

  /// Platform-specific native RTMP streaming implementation
  Future<bool> _startNativeRTMPStream(CameraController cameraController, LiveStreamInfo streamInfo) async {
    try {
      // Initialize native RTMP if not already done
      await NativeRTMPChannel.initialize();
      
      // Start native RTMP streaming
      return await NativeRTMPChannel.startStreaming(
        rtmpUrl: streamInfo.rtmpUrl,
        quality: _quality.resolution,
        bitrate: _quality.bitrate,
        frameRate: _quality.fps,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Native RTMP stream error: $e');
      }
      return false;
    }
  }

  /// Android-specific RTMP streaming
  Future<bool> _startAndroidRTMPStream(CameraController cameraController, LiveStreamInfo streamInfo) async {
    // Use the unified native channel approach
    return await _startNativeRTMPStream(cameraController, streamInfo);
  }

  /// iOS-specific RTMP streaming
  Future<bool> _startIOSRTMPStream(CameraController cameraController, LiveStreamInfo streamInfo) async {
    // Use the unified native channel approach
    return await _startNativeRTMPStream(cameraController, streamInfo);
  }

  /// Web/Desktop RTMP streaming fallback
  Future<bool> _startWebRTCStream(CameraController cameraController, LiveStreamInfo streamInfo) async {
    // For web/desktop, we could implement WebRTC to RTMP bridge
    // or use a different streaming protocol
    
    if (kDebugMode) {
      print('Starting WebRTC stream (fallback implementation)');
      print('Note: For production web deployment, consider implementing WebRTC to RTMP bridge');
    }
    
    // Simulate streaming initialization
    await Future.delayed(const Duration(milliseconds: 1000));
    return true;
  }

  /// Stop streaming with cleanup
  Future<void> stopStreaming() async {
    try {
      if (_isStreaming) {
        // Stop platform-specific streaming
        await _stopNativeRTMPStream();
        
        // Stop performance monitoring
        _stopPerformanceMonitoring();
        
        if (kDebugMode) {
          print('Streaming stopped successfully');
        }
      }
      
      _stopStreaming();
    } catch (e) {
      _setError('Error stopping stream: $e');
    }
  }

  /// Stop native RTMP stream
  Future<void> _stopNativeRTMPStream() async {
    try {
      await NativeRTMPChannel.stopStreaming();
    } catch (e) {
      if (kDebugMode) {
        print('Error stopping native RTMP: $e');
      }
    }
  }

  Future<void> _stopAndroidRTMPStream() async {
    // Use unified approach
    await _stopNativeRTMPStream();
  }

  Future<void> _stopIOSRTMPStream() async {
    // Use unified approach
    await _stopNativeRTMPStream();
  }

  Future<void> _stopWebRTCStream() async {
    // Web/Desktop cleanup
    await Future.delayed(const Duration(milliseconds: 200));
  }

  /// Optimize camera settings based on quality and network condition
  Future<void> _optimizeCameraSettings(CameraController cameraController) async {
    try {
      // Set resolution based on quality
      await cameraController.setDescription(CameraDescription(
        name: cameraController.description.name,
        lensDirection: cameraController.description.lensDirection,
        sensorOrientation: cameraController.description.sensorOrientation,
      ));
      
      // Additional optimizations could include:
      // - Setting frame rate
      // - Adjusting exposure
      // - Setting focus mode
      // - Enabling image stabilization
      
    } catch (e) {
      if (kDebugMode) {
        print('Camera optimization failed: $e');
      }
    }
  }

  /// Set up native streaming event listening
  void _setupNativeEventListening() {
    _nativeEventsSubscription = NativeRTMPChannel.streamingEvents.listen(
      (event) {
        _handleNativeStreamingEvent(event);
      },
      onError: (error) {
        if (kDebugMode) {
          print('Native streaming event error: $error');
        }
      },
    );
  }

  /// Handle native streaming events
  void _handleNativeStreamingEvent(Map<String, dynamic> event) {
    final eventType = event['type'] as String?;
    
    switch (eventType) {
      case 'connection_status':
        final connected = event['connected'] as bool? ?? false;
        if (!connected && _isStreaming) {
          _handleConnectionLoss();
        }
        break;
        
      case 'stats_update':
        _updateNativeStats(event);
        break;
        
      case 'error':
        final error = event['error'] as String? ?? 'Unknown native error';
        _handleNativeError(error);
        break;
        
      case 'quality_changed':
        final newQuality = event['quality'] as String?;
        if (newQuality != null) {
          if (kDebugMode) {
            print('Native quality changed to: $newQuality');
          }
        }
        break;
    }
    
    notifyListeners();
  }

  /// Handle connection loss with auto-retry
  void _handleConnectionLoss() {
    if (_autoRetryEnabled && _retryAttempts < _maxRetryAttempts) {
      _retryAttempts++;
      if (kDebugMode) {
        print('Connection lost, attempting retry $_retryAttempts/$_maxRetryAttempts');
      }
      
      // Try to reconnect after a delay
      Future.delayed(Duration(seconds: _retryAttempts * 2), () {
        if (_isStreaming && _currentStream != null) {
          // Attempt to restart streaming
          _attemptStreaming(_lastCameraController!, _currentStream!);
        }
      });
    } else {
      _setError('Connection lost and max retries exceeded');
      _stopStreaming();
    }
  }

  /// Update performance stats from native channel
  void _updateNativeStats(Map<String, dynamic> stats) {
    _droppedFrames = stats['droppedFrames'] as int? ?? _droppedFrames;
    _averageFrameRate = (stats['frameRate'] as num?)?.toDouble() ?? _averageFrameRate;
    _uploadBandwidth = stats['bandwidth'] as int? ?? _uploadBandwidth;
  }

  /// Handle native streaming errors
  void _handleNativeError(String error) {
    if (kDebugMode) {
      print('Native streaming error: $error');
    }
    
    if (_isStreaming) {
      _setError('Native streaming error: $error');
    }
  }

  /// Start network condition monitoring
  void _startNetworkMonitoring() {
    _networkMonitor = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkNetworkCondition();
    });
  }

  /// Check current network condition
  Future<void> _checkNetworkCondition() async {
    try {
      // This would implement actual network speed testing
      // For now, simulate network condition assessment
      
      // Simulate bandwidth test (this would be real network measurement)
      final simulatedBandwidth = 2500 + (DateTime.now().millisecond % 2000);
      _uploadBandwidth = simulatedBandwidth;
      
      // Determine network condition based on bandwidth
      if (simulatedBandwidth < 1000) {
        _networkCondition = NetworkCondition.poor;
      } else if (simulatedBandwidth < 2000) {
        _networkCondition = NetworkCondition.fair;
      } else if (simulatedBandwidth < 3500) {
        _networkCondition = NetworkCondition.good;
      } else {
        _networkCondition = NetworkCondition.excellent;
      }
      
      // Auto-adjust quality if enabled and streaming
      if (_adaptiveQualityEnabled && _isStreaming) {
        final recommendedQuality = _networkCondition.recommendedQuality;
        if (recommendedQuality != _quality) {
          await _adjustStreamQuality(recommendedQuality);
        }
      }
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Network condition check failed: $e');
      }
    }
  }

  /// Start performance monitoring
  void _startPerformanceMonitoring() {
    _performanceMonitor = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updatePerformanceMetrics();
    });
  }

  /// Stop performance monitoring
  void _stopPerformanceMonitoring() {
    _performanceMonitor?.cancel();
    _performanceMonitor = null;
  }

  /// Update performance metrics
  void _updatePerformanceMetrics() {
    // Simulate performance metrics (in real implementation, these would come from native code)
    _droppedFrames += DateTime.now().millisecond % 3;
    _averageFrameRate = 30.0 - (DateTime.now().millisecond % 100) / 100.0 * 5.0;
    
    // Trigger quality adjustment if performance is poor
    if (_averageFrameRate < 25.0 && _quality != StreamQuality.quality360p) {
      _adjustStreamQuality(_getReducedQuality(_quality));
    }
    
    notifyListeners();
  }

  /// Adjust stream quality during streaming
  Future<void> _adjustStreamQuality(StreamQuality newQuality) async {
    if (_quality == newQuality || !_isStreaming) return;
    
    if (kDebugMode) {
      print('Adjusting stream quality from ${_quality.value} to ${newQuality.value}');
    }
    
    _quality = newQuality;
    
    // Update quality through native channel if streaming
    if (_isStreaming) {
      try {
        await NativeRTMPChannel.updateQuality(
          quality: _quality.resolution,
          bitrate: _quality.bitrate,
        );
      } catch (e) {
        if (kDebugMode) {
          print('Failed to update quality dynamically: $e');
        }
      }
    }
    
    notifyListeners();
  }

  /// Get reduced quality for fallback
  StreamQuality _getReducedQuality(StreamQuality current) {
    switch (current) {
      case StreamQuality.quality1080p:
        return StreamQuality.quality720p;
      case StreamQuality.quality720p:
        return StreamQuality.quality480p;
      case StreamQuality.quality480p:
        return StreamQuality.quality360p;
      case StreamQuality.quality360p:
        return StreamQuality.quality360p;
    }
  }

  /// Update stream quality settings
  void updateStreamQuality(StreamQuality quality) {
    _quality = quality;
    notifyListeners();
  }

  /// Enable/disable adaptive quality
  void setAdaptiveQuality(bool enabled) {
    _adaptiveQualityEnabled = enabled;
    notifyListeners();
  }

  /// Enable/disable auto retry
  void setAutoRetry(bool enabled) {
    _autoRetryEnabled = enabled;
    notifyListeners();
  }

  /// Request necessary permissions
  Future<bool> _requestPermissions() async {
    final permissions = [
      Permission.camera,
      Permission.microphone,
      Permission.storage, // For saving logs/cache
    ];
    
    final statuses = await permissions.request();
    
    return statuses.values.every((status) => status == PermissionStatus.granted);
  }

  void _stopStreaming() {
    _isStreaming = false;
    _retryAttempts = 0;
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
    _networkMonitor?.cancel();
    _performanceMonitor?.cancel();
    _nativeEventsSubscription?.cancel();
    super.dispose();
  }
}