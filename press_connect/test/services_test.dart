import 'package:flutter_test/flutter_test.dart';
import 'package:press_connect/services/rtmp_streaming_service.dart';
import 'package:press_connect/services/watermark_service.dart';
import 'package:camera/camera.dart';

void main() {
  group('RTMPStreamingService Tests', () {
    late RTMPStreamingService streamingService;
    late WatermarkService watermarkService;

    setUp(() {
      streamingService = RTMPStreamingService();
      watermarkService = WatermarkService();
    });

    test('should initialize with idle state', () {
      expect(streamingService.state, RTMPStreamState.idle);
      expect(streamingService.canStart, true);
      expect(streamingService.canStop, false);
      expect(streamingService.isStreaming, false);
    });

    test('should not start streaming without camera', () async {
      final result = await streamingService.startStreaming('rtmp://test.url');
      expect(result, false);
      expect(streamingService.state, RTMPStreamState.error);
      expect(streamingService.errorMessage, contains('Camera not initialized'));
    });

    test('should transition states correctly', () {
      streamingService.clearError();
      expect(streamingService.state, RTMPStreamState.idle);
      expect(streamingService.errorMessage, null);
    });
  });

  group('WatermarkService Tests', () {
    late WatermarkService watermarkService;

    setUp(() {
      watermarkService = WatermarkService();
    });

    test('should have default values', () {
      expect(watermarkService.isEnabled, true);
      expect(watermarkService.opacity, 0.3);
      expect(watermarkService.opacityPercentage, 30);
    });

    test('should generate FFmpeg filter when enabled', () {
      watermarkService.setEnabled(true);
      final filter = watermarkService.generateFFmpegFilter();
      expect(filter, isNotEmpty);
      expect(filter, contains('overlay'));
    });

    test('should return empty filter when disabled', () {
      watermarkService.setEnabled(false);
      final filter = watermarkService.generateFFmpegFilter();
      expect(filter, isEmpty);
    });

    test('should clamp opacity values', () {
      watermarkService.setOpacity(1.5);
      expect(watermarkService.opacity, 1.0);

      watermarkService.setOpacity(-0.5);
      expect(watermarkService.opacity, 0.0);
    });
  });
}