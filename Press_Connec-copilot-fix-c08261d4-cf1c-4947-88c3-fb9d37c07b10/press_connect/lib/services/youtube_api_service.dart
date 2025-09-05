import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import '../config.dart';

enum YouTubeStreamStatus {
  idle,
  creating,
  ready,
  testing,
  live,
  ending,
  ended,
  error
}

class YouTubeBroadcast {
  final String broadcastId;
  final String streamId;
  final String title;
  final String description;
  final DateTime scheduledStartTime;
  final DateTime? actualStartTime;
  final DateTime? actualEndTime;
  final String status;

  YouTubeBroadcast({
    required this.broadcastId,
    required this.streamId,
    required this.title,
    required this.description,
    required this.scheduledStartTime,
    this.actualStartTime,
    this.actualEndTime,
    required this.status,
  });

  factory YouTubeBroadcast.fromJson(Map<String, dynamic> json) {
    return YouTubeBroadcast(
      broadcastId: json['broadcastId'] ?? '',
      streamId: json['streamId'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      scheduledStartTime: DateTime.parse(json['scheduledStartTime']),
      actualStartTime: json['actualStartTime'] != null
          ? DateTime.parse(json['actualStartTime']) : null,
      actualEndTime: json['actualEndTime'] != null
          ? DateTime.parse(json['actualEndTime']) : null,
      status: json['status'] ?? '',
    );
  }
}

class YouTubeStreamInfo {
  final String streamKey;
  final String ingestUrl;
  final String broadcastId;
  final String streamId;
  final bool autoLiveEnabled;
  final YouTubeBroadcast? broadcast;

  YouTubeStreamInfo({
    required this.streamKey,
    required this.ingestUrl,
    required this.broadcastId,
    required this.streamId,
    this.autoLiveEnabled = false,
    this.broadcast,
  });

  factory YouTubeStreamInfo.fromJson(Map<String, dynamic> json) {
    return YouTubeStreamInfo(
      streamKey: json['streamKey'] ?? '',
      ingestUrl: json['ingestUrl'] ?? '',
      broadcastId: json['broadcastId'] ?? '',
      streamId: json['streamId'] ?? '',
      autoLiveEnabled: json['autoLiveEnabled'] ?? false,
      broadcast: json['broadcast'] != null
          ? YouTubeBroadcast.fromJson(json['broadcast']) : null,
    );
  }
}

class YouTubeApiService extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _dio = Dio();

  YouTubeStreamStatus _status = YouTubeStreamStatus.idle;
  String? _errorMessage;
  YouTubeStreamInfo? _currentStreamInfo;

  // Stream monitoring
  DateTime? _streamStartTime;
  Timer? _statusCheckTimer;
  int _viewerCount = 0;
  bool _isLive = false;
  int _statusCheckAttempts = 0;
  static const int _maxStatusCheckAttempts = 30; // 5 minutes with 10-second intervals

  // Getters
  YouTubeStreamStatus get status => _status;
  String? get errorMessage => _errorMessage;
  YouTubeStreamInfo? get currentStreamInfo => _currentStreamInfo;
  bool get hasActiveStream => _currentStreamInfo != null;
  bool get canCreateStream => _status == YouTubeStreamStatus.idle;
  bool get canEndStream => _status == YouTubeStreamStatus.live;
  String? get streamKey => _currentStreamInfo?.streamKey;
  int get viewerCount => _viewerCount;
  bool get isLive => _isLive;
  Duration? get liveStreamDuration => _streamStartTime != null
      ? DateTime.now().difference(_streamStartTime!) : null;

  /// Create a new YouTube Live stream
  Future<YouTubeStreamInfo?> createYouTubeLiveStream({
    String? title,
    String? description,
    String privacy = 'public',
    DateTime? scheduledStartTime,
  }) async {
    if (_status != YouTubeStreamStatus.idle) {
      _handleError('YouTube stream creation already in progress');
      return null;
    }

    _setStatus(YouTubeStreamStatus.creating);

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return null;
      }

      // Prepare request data
      final requestData = <String, dynamic>{
        'title': title ?? 'Press Connect Live - ${DateTime.now().toIso8601String()}',
        'description': description ?? 'Live stream from Press Connect app',
        'privacy': privacy,
        'scheduledStartTime': (scheduledStartTime ?? DateTime.now()).toIso8601String(),
      };

      if (kDebugMode) {
        print('YouTubeApiService: Creating live stream with data: $requestData');
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/live/create',
        data: requestData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
            'Content-Type': 'application/json',
          },
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        _currentStreamInfo = YouTubeStreamInfo.fromJson(response.data);
        _setStatus(YouTubeStreamStatus.ready);
        _clearError();

        if (kDebugMode) {
          print('YouTubeApiService: Stream created successfully');
          print('Broadcast ID: ${_currentStreamInfo!.broadcastId}');
          print('Stream Key: ${_currentStreamInfo!.streamKey.substring(0, 8)}...');
          print('Auto-live enabled: ${_currentStreamInfo!.autoLiveEnabled}');
        }

        return _currentStreamInfo;
      } else {
        _handleError('Failed to create YouTube stream: ${response.statusMessage}');
        return null;
      }
    } on DioException catch (e) {
      String errorMessage = 'Network error occurred';

      if (e.response != null) {
        switch (e.response!.statusCode) {
          case 401:
            errorMessage = 'YouTube authentication expired. Please reconnect.';
            break;
          case 403:
            errorMessage = 'YouTube Live streaming not enabled for this account.';
            break;
          case 429:
            errorMessage = 'Too many requests. Please wait and try again.';
            break;
          case 500:
            errorMessage = 'YouTube API server error. Please try again later.';
            break;
          default:
            errorMessage = e.response?.data?['error'] ??
                'Failed to create YouTube stream: ${e.response?.statusMessage}';
        }
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = 'Connection timeout. Please check your internet connection.';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Request timeout. Please try again.';
      }

      _handleError(errorMessage);
      return null;
    } catch (e) {
      _handleError('Unexpected error creating YouTube stream: $e');
      return null;
    }
  }

  /// Start the YouTube Live broadcast with status monitoring
  Future<bool> startYouTubeBroadcast() async {
    if (_currentStreamInfo == null || _status != YouTubeStreamStatus.ready) {
      _handleError('No stream ready to start');
      return false;
    }

    try {
      // Start monitoring first - this will check if auto-live works
      _startStatusMonitoring();

      if (kDebugMode) {
        print('YouTubeApiService: Starting broadcast monitoring');
        print('Auto-live enabled: ${_currentStreamInfo!.autoLiveEnabled}');
      }

      return true;
    } catch (e) {
      _handleError('Failed to start YouTube broadcast monitoring: $e');
      return false;
    }
  }

  /// Monitor broadcast status and transition to live when ready
  void _startStatusMonitoring() {
    _statusCheckAttempts = 0;
    _statusCheckTimer?.cancel();

    _statusCheckTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      await _checkBroadcastStatus();
    });

    // Also check immediately
    _checkBroadcastStatus();
  }

  /// Check current broadcast status and transition if needed
  Future<void> _checkBroadcastStatus() async {
    if (_currentStreamInfo == null) {
      _statusCheckTimer?.cancel();
      return;
    }

    _statusCheckAttempts++;

    if (_statusCheckAttempts > _maxStatusCheckAttempts) {
      _statusCheckTimer?.cancel();
      _handleError('Stream failed to go live after maximum wait time. Please try again.');
      return;
    }

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _statusCheckTimer?.cancel();
        _handleError('No authentication session found');
        return;
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/live/check-and-go-live',
        data: {
          'broadcastId': _currentStreamInfo!.broadcastId,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final result = response.data;
        final broadcastStatus = result['status'] as String?;
        final isSuccess = result['success'] as bool? ?? false;

        if (kDebugMode) {
          print('YouTubeApiService: Broadcast status check - Status: $broadcastStatus, Success: $isSuccess');
        }

        if (isSuccess && broadcastStatus == 'live') {
          // Successfully transitioned to live
          _statusCheckTimer?.cancel();
          _setStatus(YouTubeStreamStatus.live);
          _streamStartTime = DateTime.now();
          _isLive = true;
          _clearError();

          if (kDebugMode) {
            print('YouTubeApiService: Broadcast is now live!');
          }

        } else if (broadcastStatus == 'testing') {
          // Stream is being tested, update status but keep monitoring
          _setStatus(YouTubeStreamStatus.testing);

          if (kDebugMode) {
            print('YouTubeApiService: Broadcast is in testing status, waiting for live...');
          }

        } else if (!result['canRetry']) {
          // Cannot retry, stop monitoring
          _statusCheckTimer?.cancel();
          _handleError('Broadcast cannot be started: ${result['message']}');

        } else {
          // Keep waiting, status is still transitioning
          if (kDebugMode) {
            print('YouTubeApiService: Waiting for broadcast to be ready... (attempt $_statusCheckAttempts/$_maxStatusCheckAttempts)');
          }
        }
      } else {
        if (kDebugMode) {
          print('YouTubeApiService: Status check failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('YouTubeApiService: Status check error: $e');
      }

      // Don't stop monitoring for network errors, keep trying
      if (_statusCheckAttempts >= _maxStatusCheckAttempts) {
        _statusCheckTimer?.cancel();
        _handleError('Failed to monitor broadcast status: $e');
      }
    }
  }

  /// Manually trigger transition to live (fallback method)
  Future<bool> forceTransitionToLive() async {
    if (_currentStreamInfo == null) {
      _handleError('No active broadcast to transition');
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
          'broadcastId': _currentStreamInfo!.broadcastId,
          'broadcastStatus': 'live',
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        _setStatus(YouTubeStreamStatus.live);
        _streamStartTime = DateTime.now();
        _isLive = true;
        _clearError();

        // Stop status monitoring since we're now live
        _statusCheckTimer?.cancel();

        if (kDebugMode) {
          print('YouTubeApiService: Successfully transitioned to live');
        }

        return true;
      } else {
        _handleError('Failed to transition to live: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _handleError('Failed to transition to live: $e');
      return false;
    }
  }

  /// End the YouTube Live broadcast
  Future<bool> endYouTubeBroadcast() async {
    if (_currentStreamInfo == null) {
      return true; // Already ended or no active stream
    }

    _setStatus(YouTubeStreamStatus.ending);
    _statusCheckTimer?.cancel();

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return false;
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/live/end',
        data: {
          'broadcastId': _currentStreamInfo!.broadcastId,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        _setStatus(YouTubeStreamStatus.ended);
        _streamStartTime = null;
        _isLive = false;
        _viewerCount = 0;
        _statusCheckAttempts = 0;

        if (kDebugMode) {
          print('YouTubeApiService: Broadcast ended successfully');
        }

        return true;
      } else {
        _handleError('Failed to end YouTube broadcast: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _handleError('Failed to end YouTube broadcast: $e');
      return false;
    }
  }

  /// Get YouTube Live stream statistics
  Future<Map<String, dynamic>?> getStreamStatistics() async {
    if (_currentStreamInfo == null) {
      return null;
    }

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        return null;
      }

      final response = await _dio.get(
        '${AppConfig.backendBaseUrl}/live/stats/${_currentStreamInfo!.broadcastId}',
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final stats = response.data as Map<String, dynamic>;

        // Update local statistics
        _viewerCount = stats['viewerCount'] ?? 0;

        return stats;
      }
    } catch (e) {
      if (kDebugMode) {
        print('YouTubeApiService: Failed to get stream statistics: $e');
      }
    }

    return null;
  }

  /// Check YouTube connection status
  Future<bool> checkYouTubeConnection() async {
    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        return false;
      }

      final response = await _dio.get(
        '${AppConfig.backendBaseUrl}/auth/youtube-status',
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      return response.statusCode == 200 &&
          (response.data['connected'] ?? false);
    } catch (e) {
      if (kDebugMode) {
        print('YouTubeApiService: Failed to check YouTube connection: $e');
      }
      return false;
    }
  }

  /// Reset the service to initial state
  void reset() {
    _statusCheckTimer?.cancel();
    _currentStreamInfo = null;
    _errorMessage = null;
    _streamStartTime = null;
    _viewerCount = 0;
    _isLive = false;
    _statusCheckAttempts = 0;

    if (_status != YouTubeStreamStatus.live && _status != YouTubeStreamStatus.ending) {
      _setStatus(YouTubeStreamStatus.idle);
    }
  }

  /// Clear current error
  void clearError() {
    if (_status == YouTubeStreamStatus.error) {
      _errorMessage = null;
      _setStatus(YouTubeStreamStatus.idle);
    }
  }

  void _setStatus(YouTubeStreamStatus status) {
    _status = status;
    notifyListeners();
  }

  void _handleError(String error) {
    _status = YouTubeStreamStatus.error;
    _errorMessage = error;
    _statusCheckTimer?.cancel();
    notifyListeners();

    if (kDebugMode) {
      print('YouTubeApiService Error: $error');
    }
  }

  void _clearError() {
    _errorMessage = null;
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }
}