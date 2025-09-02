import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import '../config.dart';

class StreamAnalytics {
  final String? streamId;
  final String? broadcastId;
  final DateTime dateRange;
  final DateTime endDate;
  final int totalViews;
  final int totalWatchTime;
  final double averageViewDuration;
  final List<DailyData> dailyData;
  final LiveMetrics? liveMetrics;

  StreamAnalytics({
    this.streamId,
    this.broadcastId,
    required this.dateRange,
    required this.endDate,
    required this.totalViews,
    required this.totalWatchTime,
    required this.averageViewDuration,
    required this.dailyData,
    this.liveMetrics,
  });

  factory StreamAnalytics.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'] ?? {};
    final liveMetricsData = json['liveMetrics'];
    
    return StreamAnalytics(
      streamId: json['streamInfo']?['id'],
      broadcastId: json['streamInfo']?['id'],
      dateRange: DateTime.parse(metrics['dateRange']?['startDate'] ?? DateTime.now().toIso8601String()),
      endDate: DateTime.parse(metrics['dateRange']?['endDate'] ?? DateTime.now().toIso8601String()),
      totalViews: metrics['totalViews'] ?? 0,
      totalWatchTime: metrics['totalWatchTime'] ?? 0,
      averageViewDuration: (metrics['averageViewDuration'] ?? 0).toDouble(),
      dailyData: (metrics['dailyData'] as List<dynamic>? ?? [])
          .map((data) => DailyData.fromList(data))
          .toList(),
      liveMetrics: liveMetricsData != null ? LiveMetrics.fromJson(liveMetricsData) : null,
    );
  }
}

class DailyData {
  final DateTime date;
  final int views;
  final int watchTime;
  final double avgDuration;

  DailyData({
    required this.date,
    required this.views,
    required this.watchTime,
    required this.avgDuration,
  });

  factory DailyData.fromList(List<dynamic> data) {
    return DailyData(
      date: DateTime.parse(data[0] ?? DateTime.now().toIso8601String()),
      views: data[1] ?? 0,
      watchTime: data[2] ?? 0,
      avgDuration: (data[3] ?? 0).toDouble(),
    );
  }
}

class LiveMetrics {
  final String broadcastId;
  final String status;
  final int concurrentViewers;
  final int totalChatMessages;
  final DateTime timestamp;

  LiveMetrics({
    required this.broadcastId,
    required this.status,
    required this.concurrentViewers,
    required this.totalChatMessages,
    required this.timestamp,
  });

  factory LiveMetrics.fromJson(Map<String, dynamic> json) {
    return LiveMetrics(
      broadcastId: json['broadcastId'] ?? '',
      status: json['status'] ?? 'unknown',
      concurrentViewers: json['concurrentViewers'] ?? 0,
      totalChatMessages: json['totalChatMessages'] ?? 0,
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class AnalyticsService extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _dio = Dio();
  
  StreamAnalytics? _currentAnalytics;
  LiveMetrics? _liveMetrics;
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  StreamAnalytics? get currentAnalytics => _currentAnalytics;
  LiveMetrics? get liveMetrics => _liveMetrics;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Get analytics for a specific stream
  Future<bool> getStreamAnalytics({
    String? streamId,
    String? broadcastId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (streamId == null && broadcastId == null) {
      _setError('Stream ID or Broadcast ID required');
      return false;
    }

    _setLoading(true);

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _setError('No authentication session found');
        return false;
      }

      final queryParams = <String, dynamic>{};
      if (streamId != null) queryParams['streamId'] = streamId;
      if (broadcastId != null) queryParams['broadcastId'] = broadcastId;
      if (startDate != null) queryParams['startDate'] = startDate.toIso8601String().split('T')[0];
      if (endDate != null) queryParams['endDate'] = endDate.toIso8601String().split('T')[0];

      final response = await _dio.get(
        '${AppConfig.backendBaseUrl}/analytics/stream',
        queryParameters: queryParams,
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        _currentAnalytics = StreamAnalytics.fromJson(response.data['analytics']);
        _setError(null);
        _setLoading(false);
        return true;
      } else {
        _setError('Failed to get analytics: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _setError('Failed to get analytics: $e');
      return false;
    }
  }

  /// Get real-time metrics for live streams
  Future<bool> getLiveMetrics(String broadcastId) async {
    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _setError('No authentication session found');
        return false;
      }

      final response = await _dio.get(
        '${AppConfig.backendBaseUrl}/analytics/live',
        queryParameters: {'broadcastId': broadcastId},
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        _liveMetrics = LiveMetrics.fromJson(response.data['metrics']);
        notifyListeners();
        return true;
      } else {
        if (kDebugMode) {
          print('Failed to get live metrics: ${response.statusMessage}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to get live metrics: $e');
      }
      return false;
    }
  }

  /// Start periodic updates for live metrics
  void startLiveMetricsUpdates(String broadcastId, {Duration interval = const Duration(seconds: 30)}) {
    // Cancel any existing timer
    stopLiveMetricsUpdates();
    
    // Start new periodic updates
    _liveMetricsTimer = Timer.periodic(interval, (_) {
      getLiveMetrics(broadcastId);
    });
    
    // Get initial metrics
    getLiveMetrics(broadcastId);
  }

  /// Stop periodic updates for live metrics
  void stopLiveMetricsUpdates() {
    _liveMetricsTimer?.cancel();
    _liveMetricsTimer = null;
  }

  /// Clear current analytics data
  void clearAnalytics() {
    _currentAnalytics = null;
    _liveMetrics = null;
    _setError(null);
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _errorMessage = error;
    _isLoading = false;
    notifyListeners();
  }

  // Private timer for live metrics updates
  Timer? _liveMetricsTimer;

  @override
  void dispose() {
    stopLiveMetricsUpdates();
    super.dispose();
  }
}