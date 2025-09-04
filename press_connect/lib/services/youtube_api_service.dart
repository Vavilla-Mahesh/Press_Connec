import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import '../config.dart';

enum YouTubeStreamStatus {
  idle,
  creating,
  ready,
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
  final YouTubeBroadcast? broadcast;

  YouTubeStreamInfo({
    required this.streamKey,
    required this.ingestUrl,
    required this.broadcastId,
    required this.streamId,
    this.broadcast,
  });

  factory YouTubeStreamInfo.fromJson(Map<String, dynamic> json) {
    return YouTubeStreamInfo(
      streamKey: json['streamKey'] ?? '',
      ingestUrl: json['ingestUrl'] ?? '',
      broadcastId: json['broadcastId'] ?? '',
      streamId: json['streamId'] ?? '',
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
  int _viewerCount = 0;
  bool _isLive = false;

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

  /// Start the YouTube Live broadcast
  Future<bool> startYouTubeBroadcast() async {
    if (_currentStreamInfo == null || _status != YouTubeStreamStatus.ready) {
      _handleError('No stream ready to start');
      return false;
    }

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return false;
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/live/start',
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
        _setStatus(YouTubeStreamStatus.live);
        _streamStartTime = DateTime.now();
        _isLive = true;
        _clearError();

        if (kDebugMode) {
          print('YouTubeApiService: Broadcast started successfully');
        }

        // Start monitoring the stream
        _startStreamMonitoring();

        return true;
      } else {
        _handleError('Failed to start YouTube broadcast: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _handleError('Failed to start YouTube broadcast: $e');
      return false;
    }
  }

  /// End the YouTube Live broadcast
  Future<bool> endYouTubeBroadcast() async {
    if (_currentStreamInfo == null || _status != YouTubeStreamStatus.live) {
      return true; // Already ended or no active stream
    }

    _setStatus(YouTubeStreamStatus.ending);

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
        
        // Stop monitoring
        _stopStreamMonitoring();

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

  /// Update stream information (title, description, etc.)
  Future<bool> updateStreamInfo({
    String? title,
    String? description,
    String? privacy,
  }) async {
    if (_currentStreamInfo == null) {
      _handleError('No active stream to update');
      return false;
    }

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return false;
      }

      final updateData = <String, dynamic>{
        'broadcastId': _currentStreamInfo!.broadcastId,
      };

      if (title != null) updateData['title'] = title;
      if (description != null) updateData['description'] = description;
      if (privacy != null) updateData['privacy'] = privacy;

      final response = await _dio.put(
        '${AppConfig.backendBaseUrl}/live/update',
        data: updateData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        if (kDebugMode) {
          print('YouTubeApiService: Stream info updated successfully');
        }
        return true;
      } else {
        _handleError('Failed to update stream info: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _handleError('Failed to update stream info: $e');
      return false;
    }
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

  /// Start monitoring the live stream
  void _startStreamMonitoring() {
    // Implement periodic checks for stream health, viewer count, etc.
    // This could be expanded to include real-time monitoring
  }

  /// Stop monitoring the live stream
  void _stopStreamMonitoring() {
    // Stop any monitoring timers or listeners
  }

  /// Reset the service to initial state
  void reset() {
    _stopStreamMonitoring();
    _currentStreamInfo = null;
    _errorMessage = null;
    _streamStartTime = null;
    _viewerCount = 0;
    _isLive = false;
    
    if (_status != YouTubeStreamStatus.live) {
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
    _stopStreamMonitoring();
    super.dispose();
  }
}