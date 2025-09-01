import 'dart:convert';
import 'package:flutter/services.dart';

class AppConfig {
  static late Map<String, dynamic> _config;

  static String get backendBaseUrl => _config['backendBaseUrl'];
  static String get googleClientId => _config['googleClientId'];
  static List<String> get youtubeScopes => List<String>.from(_config['youtubeScopes']);
  static double get defaultWatermarkOpacity => _config['defaultWatermarkOpacity']?.toDouble() ?? 0.3;
  static String get appName => _config['app']['name'];
  static String get appVersion => _config['app']['version'];
  static String get defaultWatermarkPath => _config['watermark']['defaultImagePath'];
  static double get maxWatermarkOpacity => _config['watermark']['maxOpacity']?.toDouble() ?? 1.0;
  static double get minWatermarkOpacity => _config['watermark']['minOpacity']?.toDouble() ?? 0.0;
  static int get defaultBitrate => _config['streaming']['defaultBitrate'];
  static Map<String, int> get defaultResolution => {
    'width': _config['streaming']['defaultResolution']['width'],
    'height': _config['streaming']['defaultResolution']['height'],
  };

  static Future<void> init() async {
    try {
      final configString = await rootBundle.loadString('assets/config.json');
      _config = json.decode(configString);
    } catch (e) {
      throw Exception('Failed to load app configuration: $e');
    }
  }

  static bool get isInitialized => _config.isNotEmpty;
}