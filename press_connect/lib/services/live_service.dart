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
  live,
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
  final _rtmpStreamingService = RTMPStreamingService();
  
  StreamState _streamState = StreamState.idle;
  String? _errorMessage;
  LiveStreamInfo? _currentStream;
  CameraController? _cameraController;
  WatermarkService? _watermarkService;
  
  StreamState get streamState => _streamState;
  String? get errorMessage => _errorMessage;
  LiveStreamInfo? get currentStream => _currentStream;
  bool get isLive => _streamState == StreamState.live;
  bool get canStartStream => _streamState == StreamState.idle && _currentStream != null;
  bool get canStopStream => _streamState == StreamState.live;
  RTMPStreamingService get rtmpStreamingService => _rtmpStreamingService;

  void initialize({
    required CameraController cameraController,
    required WatermarkService watermarkService,
  }) async {
    _cameraController = cameraController;
    _watermarkService = watermarkService;
    await _rtmpStreamingService.initialize(
      cameraController: cameraController,
      watermarkService: watermarkService,
    );
  }

  Future<bool> createLiveStream() async {
    if (_streamState != StreamState.idle) {
      _handleError('Cannot create stream: already in progress');
      return false;
    }

    _setState(StreamState.preparing);

    try {
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
        
        // Auto-start streaming after creation
        return await startStream();
      } else {
        _handleError('Failed to create live stream: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _handleError('Failed to create live stream: $e');
      return false;
    }
  }

  Future<bool> startStream() async {
    if (_currentStream == null) {
      _handleError('No stream created');
      return false;
    }

    if (_cameraController == null || _watermarkService == null) {
      _handleError('Camera or watermark service not initialized');
      return false;
    }

    _setState(StreamState.live);

    try {
      // Start RTMP streaming to YouTube
      final rtmpUrl = _currentStream!.rtmpUrl;
      final streamingStarted = await _rtmpStreamingService.startStreaming(rtmpUrl);
      
      if (!streamingStarted) {
        _handleError('Failed to start RTMP streaming: ${_rtmpStreamingService.errorMessage}');
        _setState(StreamState.idle);
        return false;
      }

      // Notify backend to transition broadcast to live
      await _transitionBroadcastToLive();
      
      return true;
    } catch (e) {
      _handleError('Failed to start stream: $e');
      _setState(StreamState.idle);
      return false;
    }
  }

  Future<void> _transitionBroadcastToLive() async {
    try {
      if (_currentStream?.broadcastId != null) {
        final sessionToken = await _secureStorage.read(key: 'app_session');
        await _dio.post(
          '${AppConfig.backendBaseUrl}/live/transition',
          data: {
            'broadcastId': _currentStream!.broadcastId,
            'broadcastStatus': 'live',
          },
          options: Options(
            headers: {
              'Authorization': 'Bearer $sessionToken',
            },
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to transition broadcast to live: $e');
      }
      // Don't fail the stream for this - it's not critical
    }
  }

  Future<bool> stopStream() async {
    if (_streamState != StreamState.live) {
      return true;
    }

    _setState(StreamState.stopping);

    try {
      // Stop RTMP streaming
      await _rtmpStreamingService.stopStreaming();
      
      // Optionally call backend to end the broadcast
      if (_currentStream?.broadcastId != null) {
        final sessionToken = await _secureStorage.read(key: 'app_session');
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

      _currentStream = null;
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
    _rtmpStreamingService.dispose();
    super.dispose();
  }