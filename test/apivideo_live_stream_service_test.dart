import 'package:flutter_test/flutter_test.dart';
import 'package:press_connect/services/apivideo_live_stream_service.dart';

void main() {
  group('ApiVideoLiveStreamService', () {
    test('should initialize with correct default state', () {
      final service = ApiVideoLiveStreamService();
      
      expect(service.state, StreamingState.idle);
      expect(service.errorMessage, null);
      expect(service.controller, null);
      expect(service.isStreaming, false);
      expect(service.canStartStream, false);
      expect(service.canStopStream, false);
      expect(service.isMuted, false);
      expect(service.cameraPosition, CameraPosition.back);
    });

    test('should handle error states correctly', () {
      final service = ApiVideoLiveStreamService();
      
      // Test internal error handling
      service.clearError();
      expect(service.state, StreamingState.idle);
    });

    test('should manage stream key correctly', () {
      final service = ApiVideoLiveStreamService();
      const testStreamKey = 'test-stream-key';
      
      service.setStreamKey(testStreamKey);
      // Note: streamKey is private, we just test that it doesn't throw
      expect(service.state, StreamingState.idle);
    });

    test('should reset state correctly', () {
      final service = ApiVideoLiveStreamService();
      
      service.reset();
      expect(service.state, StreamingState.idle);
      expect(service.errorMessage, null);
      expect(service.isMuted, false);
      expect(service.cameraPosition, CameraPosition.back);
    });
  });
}