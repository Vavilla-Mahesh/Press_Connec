import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import '../config.dart';

class WatermarkService extends ChangeNotifier {
  double _opacity = AppConfig.defaultWatermarkOpacity;
  String _watermarkPath = AppConfig.defaultWatermarkPath;
  bool _isEnabled = true;
  
  double get opacity => _opacity;
  String get watermarkPath => _watermarkPath;
  bool get isEnabled => _isEnabled;
  
  // Convert opacity percentage (0-100) to alpha value (0.0-1.0)
  double get alphaValue => _opacity.clamp(0.0, 1.0);
  
  // Convert opacity to percentage for UI display
  int get opacityPercentage => (_opacity * 100).round();

  void setOpacity(double opacity) {
    _opacity = opacity.clamp(AppConfig.minWatermarkOpacity, AppConfig.maxWatermarkOpacity);
    notifyListeners();
  }

  void setOpacityFromPercentage(double percentage) {
    setOpacity(percentage / 100.0);
  }

  void setWatermarkPath(String path) {
    _watermarkPath = path;
    notifyListeners();
  }

  void toggleEnabled() {
    _isEnabled = !_isEnabled;
    notifyListeners();
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    notifyListeners();
  }

  void reset() {
    _opacity = AppConfig.defaultWatermarkOpacity;
    _watermarkPath = AppConfig.defaultWatermarkPath;
    _isEnabled = true;
    notifyListeners();
  }

  // Generate FFmpeg filter string for watermark overlay
  String generateFFmpegFilter() {
    if (!_isEnabled) {
      return '';
    }

    // Simplified overlay filter that works better on mobile
    final opacity = alphaValue.toStringAsFixed(2);
    return '[1:v]scale=320:240,format=rgba,colorchannelmixer=aa=$opacity[wm];'
           '[0:v][wm]overlay=(W-w)-20:(H-h)-20:enable=1';
  }

  // Configuration for RTMP broadcaster watermark
  Map<String, dynamic> getRTMPWatermarkConfig() {
    return {
      'enabled': _isEnabled,
      'path': _watermarkPath,
      'opacity': _opacity,
      'position': 'center',
      'scale': 'cover',
    };
  }
}