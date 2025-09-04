import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import '../config.dart';

enum StreamState {
  idle,
  preparing,
  starting,
  live,
  stopping,
  error
}

class LiveStreamInfo {
  final String ingestUrl;
  final String streamKey;
  final String? broadcastId;
  final bool? autoLiveEnabled;

  LiveStreamInfo({
    required this.ingestUrl,
    required this.streamKey,
    this.broadcastId,
    this.autoLiveEnabled,
  });

  String get rtmpUrl => '$ingestUrl/$streamKey';

  factory LiveStreamInfo.fromJson(Map<String, dynamic> json) {
    return LiveStreamInfo(
      ingestUrl: json['ingestUrl'] ?? '',
      streamKey: json['streamKey'] ?? '',
      broadcastId: json['broadcastId'],
      autoLiveEnabled: json['autoLiveEnabled'] ?? false,
    );
  }
}

class LiveService extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _dio = Dio();

  StreamState _streamState = StreamState.idle;
  String? _errorMessage;
  LiveStreamInfo? _currentStream;
  Timer? _autoLiveTimer;
  int _retryCount = 0;
  static const int _maxRetries = 10;
  static const int _retryIntervalSeconds = 5;

  StreamState get streamState => _streamState;
  String? get errorMessage => _errorMessage;
  LiveStreamInfo? get currentStream => _currentStream;
  bool get isLive => _streamState == StreamState.live;
  bool get canStartStream => _streamState == StreamState.idle;
  bool get canStopStream => _streamState == StreamState.live || _streamState == StreamState.starting;

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
        if (kDebugMode) print('createLiveStream: Got stream from backend: rtmpUrl=${_currentStream?.rtmpUrl}');
        _setState(StreamState.idle);
        _errorMessage = null;
        return true;
      } else {
        _handleError('Failed to create live stream: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      if (kDebugMode) print('createLiveStream: Error - $e');
      _handleError('Failed to create live stream: $e');
      return false;
    }
  }

  Future<bool> startStream() async {
    if (_currentStream == null) {
      if (kDebugMode) print('startStream: _currentStream is null');
      _handleError('No stream created');
      return false;
    }

    if (kDebugMode) print('startStream: RTMP URL: ${_currentStream?.rtmpUrl}');

    _setState(StreamState.starting);
    _retryCount = 0;

    try {
      // Start auto-live monitoring to detect when YouTube broadcast becomes live
      _startAutoLiveMonitoring();
      return true;
    } catch (e) {
      _handleError('Failed to start stream: $e');
      return false;
    }
  }

  void _startAutoLiveMonitoring() {
    if (kDebugMode) print('Starting auto-live monitoring for broadcast: ${_currentStream!.broadcastId}');

    // Check immediately and then every 5 seconds
    _checkAndGoLive();

    _autoLiveTimer = Timer.periodic(
      Duration(seconds: _retryIntervalSeconds),
          (timer) => _checkAndGoLive(),
    );
  }

  Future<void> _checkAndGoLive() async {
    if (_streamState != StreamState.starting || _currentStream?.broadcastId == null) {
      _autoLiveTimer?.cancel();
      return;
    }

    if (_retryCount >= _maxRetries) {
      _autoLiveTimer?.cancel();
      if (kDebugMode) print('Max retries reached for auto-live');
      // Still consider it "live" even if YouTube didn't automatically transition
      _setState(StreamState.live);
      return;
    }

    _retryCount++;

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _autoLiveTimer?.cancel();
        _handleError('Session expired during auto-live');
        return;
      }

      if (kDebugMode) print('Checking live status (attempt $_retryCount/$_maxRetries)');

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/live/check-and-go-live',
        data: {
          'broadcastId': _currentStream!.broadcastId,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
          sendTimeout: Duration(seconds: 10),
          receiveTimeout: Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        _autoLiveTimer?.cancel();
        _setState(StreamState.live);
        if (kDebugMode) print('Successfully went live automatically!');
      } else {
        final status = response.data['status'] ?? 'unknown';
        final message = response.data['message'] ?? 'Unknown status';
        if (kDebugMode) print('Auto-live check: $status - $message');

        // If the broadcast is already complete or error, stop trying
        if (status == 'complete' || (response.data['canRetry'] == false)) {
          _autoLiveTimer?.cancel();
          _setState(StreamState.live); // Consider it live anyway
        }
      }
    } catch (e) {
      if (kDebugMode) print('Auto-live check failed: $e');
      // Continue retrying on network errors
    }
  }

  Future<bool> stopStream() async {
    if (_streamState != StreamState.live && _streamState != StreamState.starting) {
      return true;
    }

    _setState(StreamState.stopping);

    // Cancel auto-live monitoring
    _autoLiveTimer?.cancel();
    _autoLiveTimer = null;

    try {
      // End the YouTube broadcast
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
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
              ),
            );
            if (kDebugMode) print('YouTube broadcast ended successfully');
          } catch (e) {
            if (kDebugMode) print('Failed to end YouTube broadcast: $e');
            // Continue anyway
          }
        }
      }

      _currentStream = null;
      _retryCount = 0;
      _setState(StreamState.idle);
      return true;
    } catch (e) {
      _handleError('Failed to stop stream: $e');
      return false;
    }
  }

  void reset() {
    _autoLiveTimer?.cancel();
    _autoLiveTimer = null;
    _currentStream = null;
    _retryCount = 0;
    _setState(StreamState.idle);
    _errorMessage = null;
  }

  void _setState(StreamState state) {
    if (kDebugMode) print('LiveService state changed: $_streamState -> $state');
    _streamState = state;
    notifyListeners();
  }

  void _handleError(String error) {
    _autoLiveTimer?.cancel();
    _autoLiveTimer = null;
    _streamState = StreamState.error;
    _errorMessage = error;
    notifyListeners();

    if (kDebugMode) {
      print('LiveService Error: $error');
    }
    
    // Auto-clear error after 10 seconds in production
    if (!kDebugMode) {
      Timer(const Duration(seconds: 10), () {
        if (_streamState == StreamState.error) {
          clearError();
        }
      });
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
    _autoLiveTimer?.cancel();
    super.dispose();
  }
}