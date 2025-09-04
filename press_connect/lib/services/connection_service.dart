import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:io';

enum ConnectionStatus {
  unknown,
  connected,
  disconnected,
  weak,
  unstable
}

enum NetworkType {
  wifi,
  mobile,
  ethernet,
  none,
  unknown
}

class NetworkMetrics {
  final int ping; // in milliseconds
  final double downloadSpeed; // in Mbps
  final double uploadSpeed; // in Mbps
  final int signalStrength; // percentage (0-100)
  final DateTime timestamp;

  NetworkMetrics({
    required this.ping,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.signalStrength,
    required this.timestamp,
  });

  bool get isGoodForStreaming {
    return ping < 100 && 
           uploadSpeed >= 2.0 && 
           signalStrength >= 60;
  }

  bool get isExcellentForStreaming {
    return ping < 50 && 
           uploadSpeed >= 5.0 && 
           signalStrength >= 80;
  }

  @override
  String toString() {
    return 'NetworkMetrics(ping: ${ping}ms, upload: ${uploadSpeed.toStringAsFixed(1)}Mbps, signal: $signalStrength%)';
  }
}

class ConnectionService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  
  ConnectionStatus _status = ConnectionStatus.unknown;
  NetworkType _networkType = NetworkType.unknown;
  NetworkMetrics? _currentMetrics;
  String? _errorMessage;
  
  // Monitoring
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _metricsTimer;
  Timer? _pingTimer;
  
  // Connection history for trend analysis
  final List<NetworkMetrics> _metricsHistory = [];
  static const int _maxHistoryLength = 20;
  
  // Thresholds and settings
  static const Duration _metricsCheckInterval = Duration(seconds: 10);
  static const Duration _pingCheckInterval = Duration(seconds: 5);
  static const int _pingTimeoutMs = 5000;
  static const String _pingHost = '8.8.8.8'; // Google DNS
  static const int _retryAttempts = 3;

  // Getters
  ConnectionStatus get status => _status;
  NetworkType get networkType => _networkType;
  NetworkMetrics? get currentMetrics => _currentMetrics;
  String? get errorMessage => _errorMessage;
  List<NetworkMetrics> get metricsHistory => List.unmodifiable(_metricsHistory);
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isGoodForStreaming => _currentMetrics?.isGoodForStreaming ?? false;
  bool get isExcellentForStreaming => _currentMetrics?.isExcellentForStreaming ?? false;
  
  // Quality indicators
  String get connectionQuality {
    if (_currentMetrics == null) return 'Unknown';
    if (_currentMetrics!.isExcellentForStreaming) return 'Excellent';
    if (_currentMetrics!.isGoodForStreaming) return 'Good';
    return 'Poor';
  }

  /// Initialize connection monitoring
  Future<void> initialize() async {
    try {
      // Check initial connectivity
      await _checkConnectivity();
      
      // Start listening to connectivity changes
      _startConnectivityMonitoring();
      
      // Start metrics monitoring
      _startMetricsMonitoring();
      
      if (kDebugMode) {
        print('ConnectionService: Initialized successfully');
      }
    } catch (e) {
      _handleError('Failed to initialize connection service: $e');
    }
  }

  /// Start monitoring connection changes
  void _startConnectivityMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _onConnectivityChanged(results);
      },
      onError: (error) {
        _handleError('Connectivity monitoring error: $error');
      },
    );
  }

  /// Start monitoring network metrics
  void _startMetricsMonitoring() {
    _stopMetricsMonitoring();
    
    // Start periodic metrics collection
    _metricsTimer = Timer.periodic(_metricsCheckInterval, (timer) {
      _collectNetworkMetrics();
    });
    
    // Start periodic ping tests
    _pingTimer = Timer.periodic(_pingCheckInterval, (timer) {
      _performPingTest();
    });
    
    // Collect initial metrics
    _collectNetworkMetrics();
  }

  /// Stop monitoring network metrics
  void _stopMetricsMonitoring() {
    _metricsTimer?.cancel();
    _pingTimer?.cancel();
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      _setNetworkType(NetworkType.none);
      _setStatus(ConnectionStatus.disconnected);
      return;
    }

    // Use the first (primary) connection result
    final result = results.first;
    
    switch (result) {
      case ConnectivityResult.wifi:
        _setNetworkType(NetworkType.wifi);
        break;
      case ConnectivityResult.mobile:
        _setNetworkType(NetworkType.mobile);
        break;
      case ConnectivityResult.ethernet:
        _setNetworkType(NetworkType.ethernet);
        break;
      case ConnectivityResult.none:
        _setNetworkType(NetworkType.none);
        _setStatus(ConnectionStatus.disconnected);
        return;
      default:
        _setNetworkType(NetworkType.unknown);
    }

    // Check actual internet connectivity
    _verifyInternetConnection();
  }

  /// Verify actual internet connectivity
  Future<void> _verifyInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _setStatus(ConnectionStatus.connected);
        _clearError();
      } else {
        _setStatus(ConnectionStatus.disconnected);
      }
    } catch (e) {
      _setStatus(ConnectionStatus.disconnected);
      _handleError('Internet connectivity verification failed: $e');
    }
  }

  /// Check current connectivity
  Future<void> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _onConnectivityChanged(result);
    } catch (e) {
      _handleError('Failed to check connectivity: $e');
    }
  }

  /// Collect comprehensive network metrics
  Future<void> _collectNetworkMetrics() async {
    if (_status != ConnectionStatus.connected) {
      return;
    }

    try {
      // For now, create basic metrics
      // In a real implementation, you would use platform-specific APIs
      // to get actual network speed and signal strength
      
      final ping = await _measurePing();
      final uploadSpeed = await _estimateUploadSpeed();
      final downloadSpeed = await _estimateDownloadSpeed();
      final signalStrength = _getSignalStrength();

      final metrics = NetworkMetrics(
        ping: ping,
        downloadSpeed: downloadSpeed,
        uploadSpeed: uploadSpeed,
        signalStrength: signalStrength,
        timestamp: DateTime.now(),
      );

      _currentMetrics = metrics;
      _addToHistory(metrics);
      _evaluateConnectionQuality(metrics);

      if (kDebugMode) {
        print('ConnectionService: Updated metrics - $metrics');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('ConnectionService: Failed to collect metrics: $e');
      }
    }
  }

  /// Perform ping test
  Future<void> _performPingTest() async {
    if (_status != ConnectionStatus.connected) {
      return;
    }

    final ping = await _measurePing();
    
    // Update current metrics if available
    if (_currentMetrics != null) {
      _currentMetrics = NetworkMetrics(
        ping: ping,
        downloadSpeed: _currentMetrics!.downloadSpeed,
        uploadSpeed: _currentMetrics!.uploadSpeed,
        signalStrength: _currentMetrics!.signalStrength,
        timestamp: DateTime.now(),
      );
      
      _evaluateConnectionQuality(_currentMetrics!);
      notifyListeners();
    }
  }

  /// Measure ping to test server
  Future<int> _measurePing() async {
    try {
      final stopwatch = Stopwatch()..start();
      
      await Socket.connect(_pingHost, 53, timeout: const Duration(milliseconds: _pingTimeoutMs));
      
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (e) {
      // Return high ping value for failed connections
      return _pingTimeoutMs;
    }
  }

  /// Estimate upload speed (simplified implementation)
  Future<double> _estimateUploadSpeed() async {
    // This is a simplified estimation
    // In a real implementation, you would upload test data to measure speed
    
    switch (_networkType) {
      case NetworkType.wifi:
        return 10.0; // Assume good WiFi
      case NetworkType.ethernet:
        return 50.0; // Assume excellent ethernet
      case NetworkType.mobile:
        return 5.0;  // Assume decent mobile
      default:
        return 1.0;  // Conservative estimate
    }
  }

  /// Estimate download speed (simplified implementation)
  Future<double> _estimateDownloadSpeed() async {
    // This is a simplified estimation
    // In a real implementation, you would download test data to measure speed
    
    switch (_networkType) {
      case NetworkType.wifi:
        return 25.0; // Assume good WiFi
      case NetworkType.ethernet:
        return 100.0; // Assume excellent ethernet
      case NetworkType.mobile:
        return 15.0;  // Assume decent mobile
      default:
        return 5.0;   // Conservative estimate
    }
  }

  /// Get signal strength estimation
  int _getSignalStrength() {
    // This is a simplified estimation
    // In a real implementation, you would use platform-specific APIs
    
    switch (_networkType) {
      case NetworkType.wifi:
        return 85; // Assume good WiFi signal
      case NetworkType.ethernet:
        return 100; // Ethernet is always 100%
      case NetworkType.mobile:
        return 70;  // Assume decent mobile signal
      default:
        return 50;  // Unknown connection
    }
  }

  /// Evaluate overall connection quality
  void _evaluateConnectionQuality(NetworkMetrics metrics) {
    if (metrics.isExcellentForStreaming) {
      _setStatus(ConnectionStatus.connected);
    } else if (metrics.isGoodForStreaming) {
      _setStatus(ConnectionStatus.connected);
    } else if (metrics.ping > 200 || metrics.uploadSpeed < 1.0) {
      _setStatus(ConnectionStatus.weak);
    } else {
      _setStatus(ConnectionStatus.unstable);
    }
  }

  /// Add metrics to history
  void _addToHistory(NetworkMetrics metrics) {
    _metricsHistory.add(metrics);
    
    // Keep only recent history
    if (_metricsHistory.length > _maxHistoryLength) {
      _metricsHistory.removeAt(0);
    }
  }

  /// Get average metrics over recent history
  NetworkMetrics? getAverageMetrics({int? lastN}) {
    if (_metricsHistory.isEmpty) return null;
    
    final count = lastN ?? _metricsHistory.length;
    final recentMetrics = _metricsHistory.take(count).toList();
    
    if (recentMetrics.isEmpty) return null;
    
    final avgPing = recentMetrics.map((m) => m.ping).reduce((a, b) => a + b) ~/ recentMetrics.length;
    final avgDownload = recentMetrics.map((m) => m.downloadSpeed).reduce((a, b) => a + b) / recentMetrics.length;
    final avgUpload = recentMetrics.map((m) => m.uploadSpeed).reduce((a, b) => a + b) / recentMetrics.length;
    final avgSignal = recentMetrics.map((m) => m.signalStrength).reduce((a, b) => a + b) ~/ recentMetrics.length;
    
    return NetworkMetrics(
      ping: avgPing,
      downloadSpeed: avgDownload,
      uploadSpeed: avgUpload,
      signalStrength: avgSignal,
      timestamp: DateTime.now(),
    );
  }

  /// Check if connection is stable for streaming
  bool isStableForStreaming() {
    if (_metricsHistory.length < 3) {
      return _currentMetrics?.isGoodForStreaming ?? false;
    }
    
    // Check if recent metrics show consistent good performance
    final recentMetrics = _metricsHistory.takeLast(3);
    return recentMetrics.every((metrics) => metrics.isGoodForStreaming);
  }

  /// Get connection recommendations for streaming
  List<String> getStreamingRecommendations() {
    final recommendations = <String>[];
    
    if (_currentMetrics == null) {
      recommendations.add('Unable to assess connection quality');
      return recommendations;
    }
    
    final metrics = _currentMetrics!;
    
    if (metrics.ping > 100) {
      recommendations.add('High latency detected. Consider moving closer to WiFi router or switching networks.');
    }
    
    if (metrics.uploadSpeed < 2.0) {
      recommendations.add('Upload speed is below recommended 2 Mbps for HD streaming.');
    }
    
    if (metrics.signalStrength < 70) {
      recommendations.add('Weak signal detected. Try moving to a location with better reception.');
    }
    
    if (_networkType == NetworkType.mobile && metrics.uploadSpeed < 5.0) {
      recommendations.add('Consider using WiFi for better streaming quality and to avoid mobile data charges.');
    }
    
    if (recommendations.isEmpty) {
      recommendations.add('Connection is optimal for streaming!');
    }
    
    return recommendations;
  }

  /// Force a connection check
  Future<void> refreshConnection() async {
    try {
      await _checkConnectivity();
      await _collectNetworkMetrics();
    } catch (e) {
      _handleError('Failed to refresh connection: $e');
    }
  }

  void _setStatus(ConnectionStatus status) {
    if (_status != status) {
      _status = status;
      notifyListeners();
      
      if (kDebugMode) {
        print('ConnectionService: Status changed to $status');
      }
    }
  }

  void _setNetworkType(NetworkType type) {
    if (_networkType != type) {
      _networkType = type;
      notifyListeners();
      
      if (kDebugMode) {
        print('ConnectionService: Network type changed to $type');
      }
    }
  }

  void _handleError(String error) {
    _errorMessage = error;
    notifyListeners();

    if (kDebugMode) {
      print('ConnectionService Error: $error');
    }
  }

  void _clearError() {
    _errorMessage = null;
  }

  /// Clear current error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopMetricsMonitoring();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}