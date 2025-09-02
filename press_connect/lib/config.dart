import 'dart:convert';
import 'package:flutter/services.dart';

class AppConfig {
  static late Map<String, dynamic> _config;

  static String get backendBaseUrl => _config['backendBaseUrl'];
  static String get googleClientId => _config['googleClientId'];
  static List<String> get youtubeScopes => List<String>.from(_config['youtubeScopes']);
  static String get appName => _config['app']['name'];
  static String get appVersion => _config['app']['version'];
  static int get defaultBitrate => _config['streaming']['defaultBitrate'];
  static Map<String, int> get defaultResolution => {
    'width': _config['streaming']['defaultResolution']['width'],
    'height': _config['streaming']['defaultResolution']['height'],
  };
  
  static Map<String, dynamic> get qualityOptions => 
    Map<String, dynamic>.from(_config['streaming']['qualityOptions']);
  
  static List<String> get visibilityOptions => 
    List<String>.from(_config['streaming']['visibilityOptions']);
    
  static List<String> get statusOptions => 
    List<String>.from(_config['streaming']['statusOptions']);

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