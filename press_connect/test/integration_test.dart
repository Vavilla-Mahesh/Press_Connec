import 'package:flutter_test/flutter_test.dart';
import 'package:press_connect/services/live_service.dart';
import 'package:press_connect/services/apivideo_live_stream_service.dart';

void main() {
  group('Live Streaming Integration Tests', () {
    test('LiveService should create stream info with proper RTMP URL', () {
      const ingestUrl = 'rtmp://a.rtmp.youtube.com/live2';
      const streamKey = 'test-stream-key-1234';
      
      final streamInfo = LiveStreamInfo(
        ingestUrl: ingestUrl,
        streamKey: streamKey,
        broadcastId: 'test-broadcast-123',
      );
      
      expect(streamInfo.rtmpUrl, '$ingestUrl/$streamKey');
      expect(streamInfo.ingestUrl, ingestUrl);
      expect(streamInfo.streamKey, streamKey);
      expect(streamInfo.broadcastId, 'test-broadcast-123');
    });

    test('LiveService should properly parse backend response', () {
      final json = {
        'ingestUrl': 'rtmp://a.rtmp.youtube.com/live2',
        'streamKey': 'test-key-5678',
        'broadcastId': 'broadcast-abc',
        'autoLiveEnabled': true,
      };
      
      final streamInfo = LiveStreamInfo.fromJson(json);
      
      expect(streamInfo.ingestUrl, 'rtmp://a.rtmp.youtube.com/live2');
      expect(streamInfo.streamKey, 'test-key-5678');
      expect(streamInfo.broadcastId, 'broadcast-abc');
      expect(streamInfo.autoLiveEnabled, true);
      expect(streamInfo.rtmpUrl, 'rtmp://a.rtmp.youtube.com/live2/test-key-5678');
    });

    test('ApiVideoLiveStreamService should accept RTMP URLs', () {
      final service = ApiVideoLiveStreamService();
      const rtmpUrl = 'rtmp://a.rtmp.youtube.com/live2/test-stream';
      
      // This should not throw
      service.setRtmpUrl(rtmpUrl);
      expect(service.state, StreamingState.idle);
    });

    test('Services should handle state transitions correctly', () {
      final liveService = LiveService();
      
      expect(liveService.streamState, StreamState.idle);
      expect(liveService.canStartStream, true);
      expect(liveService.canStopStream, false);
      expect(liveService.isLive, false);
    });
  });
}