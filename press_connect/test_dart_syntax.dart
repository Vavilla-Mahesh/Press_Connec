// Test imports and basic syntax
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rtmp_broadcaster/camera.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  // Test orientation values exist
  final orientations = [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ];
  
  print('✅ All DeviceOrientation values available: ${orientations.length}');
  print('✅ SystemChrome import successful');
  print('✅ Dart syntax validation passed');
}
