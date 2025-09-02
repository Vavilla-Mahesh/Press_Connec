import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import '../config.dart';
import 'rtmp_streaming_service.dart';
import 'watermark_service.dart';

enum StreamState {
  idle,
  preparing,
  testing,      // YouTube broadcast in testing state
  live,         // YouTube broadcast is live
  stopping,
  error
}

class LiveStreamInfo {
  final String ingestUrl;
  final String streamKey;
  final String? broadcastId;

  LiveStreamInfo({
    required this.ingestUrl,
    required this.streamKey,
    this.broadcastId,
  });

  String get rtmpUrl => '$ingestUrl/$streamKey';

  factory LiveStreamInfo.fromJson(Map<String, dynamic> json) {
    return LiveStreamInfo(
      ingestUrl: json['ingestUrl'] ?? '',
      streamKey: json['streamKey'] ?? '',
      broadcastId: json['broadcastId'],
    );
  }
}

class LiveService extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _dio = Dio();
  final _rtmpService = RTMPStreamingService();
  
  StreamState _streamState = StreamState.idle;
  String? _errorMessage;
  LiveStreamInfo? _currentStream;
  String? _serverStreamId;
  String? _recordingId;
  bool _isRecording = false;
  
  StreamState get streamState => _streamState;
  String? get errorMessage => _errorMessage;
  LiveStreamInfo? get currentStream => _currentStream;
  RTMPStreamingService get rtmpService => _rtmpService;
  String? get serverStreamId => _serverStreamId;
  String? get recordingId => _recordingId;
  bool get isRecording => _isRecording;
  
  bool get isLive => _streamState == StreamState.live;
  bool get isTesting => _streamState == StreamState.testing;
  bool get canStartStream => _streamState == StreamState.idle;
  bool get canStopStream => _streamState == StreamState.live || _streamState == StreamState.testing;

  Future<bool> createLiveStream() async {
    if (_streamState != StreamState.idle) {
      _handleError('Cannot create stream: already in progress');
      return false;
    }

    _setState(StreamState.preparing);

    try {
      // Initialize RTMP service if not already done
      if (!_rtmpService.isInitialized) {
        final rtmpInitialized = await _rtmpService.initialize();
        if (!rtmpInitialized) {
          _handleError('Failed to initialize streaming service: ${_rtmpService.errorMessage}');
          return false;
        }
      }

      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return false;
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/live/create',
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        _currentStream = LiveStreamInfo.fromJson(response.data);
        _setState(StreamState.idle); // Ready to start streaming
        _errorMessage = null;
        return true;
      } else {
        _handleError('Failed to create live stream: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _handleError('Failed to create live stream: $e');
      return false;
    }
  }

  Future<bool> startStream({
    required CameraController cameraController,
    WatermarkService? watermarkService,
    bool testMode = false,
  }) async {
    if (_currentStream == null) {
      _handleError('No stream created');
      return false;
    }

    if (!_rtmpService.isInitialized) {
      _handleError('Streaming service not initialized');
      return false;
    }

    try {
      _setState(testMode ? StreamState.testing : StreamState.preparing);

      // Start server-side stream processing with watermark first
      final serverStreamStarted = await _startServerSideStream(watermarkService);
      if (!serverStreamStarted) {
        return false;
      }

      // Now start RTMP streaming to backend endpoint
      final streamingStarted = await _rtmpService.startStreaming(
        cameraController: cameraController,
        streamInfo: _currentStream!,
        watermarkService: watermarkService,
      );

      if (!streamingStarted) {
        _handleError('Failed to start RTMP streaming: ${_rtmpService.errorMessage}');
        await _stopServerSideStream();
        return false;
      }

      if (!testMode) {
        // Transition YouTube broadcast to live
        final transitioned = await _transitionBroadcast('live');
        if (!transitioned) {
          await _stopServerSideStream();
          await _rtmpService.stopStreaming(cameraController: cameraController);
          return false;
        }
      }

      _setState(testMode ? StreamState.testing : StreamState.live);
      return true;
    } catch (e) {
      _handleError('Failed to start stream: $e');
      return false;
    }
  }

  Future<bool> stopStream({CameraController? cameraController}) async {
    if (_streamState != StreamState.live && _streamState != StreamState.testing) {
      return true;
    }

    _setState(StreamState.stopping);

    try {
      // Stop recording if active
      if (_isRecording && _recordingId != null) {
        await stopRecording();
      }

      // Stop server-side stream processing
      if (_serverStreamId != null) {
        await _stopServerSideStream();
      }

      // Stop RTMP streaming first
      await _rtmpService.stopStreaming(cameraController: cameraController);

      // End the YouTube broadcast if it was live
      if (_currentStream?.broadcastId != null && _streamState == StreamState.live) {
        final sessionToken = await _secureStorage.read(key: 'app_session');
        if (sessionToken != null) {
          await _dio.post(
            '${AppConfig.backendBaseUrl}/live/end',
            data: {
              'broadcastId': _currentStream!.broadcastId,
            },
            options: Options(
              headers: {
                'Authorization': 'Bearer $sessionToken',
              },
            ),
          );
        }
      }

      _currentStream = null;
      _serverStreamId = null;
      _setState(StreamState.idle);
      return true;
    } catch (e) {
      _handleError('Failed to stop stream: $e');
      return false;
    }
  }

  void reset() {
    _currentStream = null;
    _setState(StreamState.idle);
    _errorMessage = null;
    _serverStreamId = null;
    _recordingId = null;
    _isRecording = false;
  }

  /// Start server-side stream processing with watermark
  Future<bool> _startServerSideStream(WatermarkService? watermarkService) async {
    if (_currentStream == null) return false;

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return false;
      }

      final youtubeRtmpOutput = _currentStream!.rtmpUrl;

      Map<String, dynamic> watermarkConfig = {
        'enabled': false,
      };
      if (watermarkService != null && watermarkService.isEnabled) {
        watermarkConfig = watermarkService.getRTMPWatermarkConfig();
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/streaming/start',
        data: {
          'youtubeRtmpUrl': youtubeRtmpOutput,
          'watermarkConfig': watermarkConfig,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        _serverStreamId = response.data['streamKey'];
        // Update the current stream to use the backend RTMP endpoint
        final backendRtmpEndpoint = response.data['rtmpEndpoint'];
        final streamKey = response.data['streamKey'];
        
        // Parse the RTMP endpoint to get ingest URL and stream key
        final uri = Uri.parse(backendRtmpEndpoint);
        final ingestUrl = '${uri.scheme}://${uri.host}:${uri.port}${uri.path.split('/').take(uri.path.split('/').length - 1).join('/')}';
        
        _currentStream = LiveStreamInfo(
          ingestUrl: ingestUrl,
          streamKey: streamKey,
          broadcastId: _currentStream!.broadcastId,
        );
        
        return true;
      } else {
        _handleError('Failed to start server stream: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _handleError('Failed to start server stream: $e');
      return false;
    }
  }

  /// Stop server-side stream processing
  Future<bool> _stopServerSideStream() async {
    if (_serverStreamId == null) return true;

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) return false;

      await _dio.post(
        '${AppConfig.backendBaseUrl}/streaming/stop',
        data: {
          'streamKey': _serverStreamId,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      _serverStreamId = null;
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to stop server stream: $e');
      }
      return false;
    }
  }

  /// Capture a snapshot from the live stream
  Future<Map<String, dynamic>?> captureSnapshot() async {
    if (_streamState != StreamState.live && _streamState != StreamState.testing) {
      _handleError('No active stream to capture snapshot from');
      return null;
    }

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return null;
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/streaming/snapshot',
        data: {
          'streamKey': _serverStreamId,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        _handleError('Failed to capture snapshot: ${response.statusMessage}');
        return null;
      }
    } catch (e) {
      _handleError('Failed to capture snapshot: $e');
      return null;
    }
  }

  /// Start recording the live stream
  Future<bool> startRecording() async {
    if (_streamState != StreamState.live && _streamState != StreamState.testing) {
      _handleError('No active stream to record');
      return false;
    }

    if (_isRecording) {
      _handleError('Recording already in progress');
      return false;
    }

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return false;
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/streaming/recording/start',
        data: {
          'streamKey': _serverStreamId,
          'recordingConfig': {
            'quality': 'high',
            'format': 'mp4',
          },
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        _recordingId = response.data['recordingId'];
        _isRecording = true;
        notifyListeners();
        return true;
      } else {
        _handleError('Failed to start recording: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _handleError('Failed to start recording: $e');
      return false;
    }
  }

  /// Stop recording the live stream
  Future<Map<String, dynamic>?> stopRecording() async {
    if (!_isRecording || _recordingId == null) {
      return null;
    }

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return null;
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/streaming/recording/stop',
        data: {
          'streamKey': _serverStreamId,
          'recordingId': _recordingId,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        _isRecording = false;
        _recordingId = null;
        notifyListeners();
        return response.data;
      } else {
        _handleError('Failed to stop recording: ${response.statusMessage}');
        return null;
      }
    } catch (e) {
      _handleError('Failed to stop recording: $e');
      return null;
    }
  }

  /// Transition YouTube broadcast to specified status
  Future<bool> _transitionBroadcast(String status) async {
    if (_currentStream?.broadcastId == null) {
      _handleError('No broadcast ID available');
      return false;
    }

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return false;
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/live/transition',
        data: {
          'broadcastId': _currentStream!.broadcastId,
          'broadcastStatus': status,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        _handleError('Failed to transition broadcast: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _handleError('Failed to transition broadcast: $e');
      return false;
    }
  }

  /// Start test stream (allows testing without going live)
  Future<bool> startTestStream({
    required CameraController cameraController,
    WatermarkService? watermarkService,
  }) async {
    return startStream(
      cameraController: cameraController,
      watermarkService: watermarkService,
      testMode: true,
    );
  }

  /// Go live from test mode
  Future<bool> goLiveFromTest() async {
    if (_streamState != StreamState.testing) {
      _handleError('Not in test mode');
      return false;
    }

    try {
      final transitioned = await _transitionBroadcast('live');
      if (transitioned) {
        _setState(StreamState.live);
        return true;
      }
      return false;
    } catch (e) {
      _handleError('Failed to go live: $e');
      return false;
    }
  }

  void _setState(StreamState state) {
    _streamState = state;
    notifyListeners();
  }

  void _handleError(String error) {
    _streamState = StreamState.error;
    _errorMessage = error;
    notifyListeners();
    
    if (kDebugMode) {
      print('LiveService Error: $error');
    }
  }

  void clearError() {
    if (_streamState == StreamState.error) {
      _streamState = StreamState.idle;
      _errorMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _rtmpService.dispose();
    super.dispose();
  }
}