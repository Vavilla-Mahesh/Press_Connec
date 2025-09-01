import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import '../config.dart';

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
  
  StreamState _streamState = StreamState.idle;
  String? _errorMessage;
  LiveStreamInfo? _currentStream;
  CameraController? _cameraController;
  
  StreamState get streamState => _streamState;
  String? get errorMessage => _errorMessage;
  LiveStreamInfo? get currentStream => _currentStream;
  bool get isLive => _streamState == StreamState.live;
  bool get canStartStream => _streamState == StreamState.idle && _currentStream != null;
  bool get canStopStream => _streamState == StreamState.live;

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

  Future<bool> startStream() async {
    if (_currentStream == null) {
      _handleError('No stream created');
      return false;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _handleError('Camera not initialized');
      return false;
    }

    _setState(StreamState.preparing);

    try {
      // First call backend to start the YouTube broadcast
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken != null && _currentStream!.broadcastId != null) {
        await _dio.post(
          '${AppConfig.backendBaseUrl}/live/start',
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

      // TODO: Implement actual RTMP streaming using rtmp_broadcaster
      // For now, just mark as live for UI purposes
      _setState(StreamState.live);
      
      if (kDebugMode) {
        print('Stream started with RTMP URL: ${_currentStream!.rtmpUrl}');
      }
      
      return true;
    } catch (e) {
      _handleError('Failed to start stream: $e');
      return false;
    }
  }

  Future<bool> stopStream() async {
    if (_streamState != StreamState.live) {
      return true;
    }

    _setState(StreamState.stopping);

    try {
      // Call backend to end the broadcast
      if (_currentStream?.broadcastId != null) {
        final sessionToken = await _secureStorage.read(key: 'app_session');
        if (sessionToken != null) {
          try {
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
          } catch (e) {
            // Log error but don't fail the stop operation
            if (kDebugMode) {
              print('Warning: Failed to end broadcast on backend: $e');
            }
          }
        }
      }

      // Clean up resources
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

  // Set camera controller for streaming
  void setCameraController(CameraController? controller) {
    _cameraController = controller;
    notifyListeners();
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
}