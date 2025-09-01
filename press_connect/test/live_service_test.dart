import 'package:flutter_test/flutter_test.dart';
import 'package:press_connect/services/live_service.dart';

void main() {
  group('LiveService Tests', () {
    late LiveService liveService;

    setUp(() {
      liveService = LiveService();
    });

    test('should initialize with idle state', () {
      expect(liveService.streamState, StreamState.idle);
      expect(liveService.isLive, false);
      expect(liveService.canStartStream, false); // No stream created yet
      expect(liveService.canStopStream, false);
    });

    test('should handle error states correctly', () {
      expect(liveService.errorMessage, null);
      
      // Simulate an error condition
      liveService.clearError();
      expect(liveService.streamState, StreamState.idle);
    });

    test('should reset properly', () {
      liveService.reset();
      
      expect(liveService.streamState, StreamState.idle);
      expect(liveService.currentStream, null);
      expect(liveService.errorMessage, null);
    });

    test('should not allow starting stream without creation', () async {
      final result = await liveService.startStream();
      
      expect(result, false);
      expect(liveService.streamState, StreamState.error);
      expect(liveService.errorMessage, contains('No stream created'));
    });
  });

  group('LiveStreamInfo Tests', () {
    test('should create from JSON correctly', () {
      final json = {
        'ingestUrl': 'rtmp://a.rtmp.youtube.com/live2',
        'streamKey': 'test-stream-key',
        'broadcastId': 'test-broadcast-id'
      };

      final info = LiveStreamInfo.fromJson(json);

      expect(info.ingestUrl, 'rtmp://a.rtmp.youtube.com/live2');
      expect(info.streamKey, 'test-stream-key');
      expect(info.broadcastId, 'test-broadcast-id');
      expect(info.rtmpUrl, 'rtmp://a.rtmp.youtube.com/live2/test-stream-key');
    });

    test('should handle missing fields gracefully', () {
      final json = <String, dynamic>{};

      final info = LiveStreamInfo.fromJson(json);

      expect(info.ingestUrl, '');
      expect(info.streamKey, '');
      expect(info.broadcastId, null);
      expect(info.rtmpUrl, '/');
    });
  });
}