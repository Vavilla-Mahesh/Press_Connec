import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Platform channel for native RTMP streaming implementation
class NativeRTMPChannel {
  static const MethodChannel _channel = MethodChannel('press_connect/rtmp_streaming');
  
  /// Initialize native RTMP streaming
  static Future<bool> initialize() async {
    try {
      final result = await _channel.invokeMethod<bool>('initialize');
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Failed to initialize native RTMP: ${e.message}');
      }
      return false;
    }
  }
  
  /// Start RTMP streaming to the specified URL
  static Future<bool> startStreaming({
    required String rtmpUrl,
    required String quality,
    required int bitrate,
    required int frameRate,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('startStreaming', {
        'rtmpUrl': rtmpUrl,
        'quality': quality,
        'bitrate': bitrate,
        'frameRate': frameRate,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Failed to start native RTMP streaming: ${e.message}');
      }
      return false;
    }
  }
  
  /// Stop RTMP streaming
  static Future<bool> stopStreaming() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopStreaming');
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Failed to stop native RTMP streaming: ${e.message}');
      }
      return false;
    }
  }
  
  /// Update streaming quality dynamically
  static Future<bool> updateQuality({
    required String quality,
    required int bitrate,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('updateQuality', {
        'quality': quality,
        'bitrate': bitrate,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Failed to update streaming quality: ${e.message}');
      }
      return false;
    }
  }
  
  /// Get streaming statistics
  static Future<Map<String, dynamic>?> getStreamingStats() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('getStreamingStats');
      return result?.cast<String, dynamic>();
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('Failed to get streaming stats: ${e.message}');
      }
      return null;
    }
  }
  
  /// Set up event channel for streaming events
  static const EventChannel _eventChannel = EventChannel('press_connect/rtmp_events');
  
  /// Stream of RTMP events (connection, errors, stats updates)
  static Stream<Map<String, dynamic>> get streamingEvents {
    return _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return Map<String, dynamic>.from(event);
      }
      return <String, dynamic>{};
    });
  }
}