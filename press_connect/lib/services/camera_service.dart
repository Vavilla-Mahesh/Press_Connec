import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

enum CameraState {
  uninitialized,
  initializing,
  ready,
  error,
  disposed
}

enum CameraType {
  back,
  front
}

class CameraService extends ChangeNotifier {
  ApiVideoLiveStreamController? _controller;
  CameraState _state = CameraState.uninitialized;
  String? _errorMessage;
  CameraType _currentCameraType = CameraType.back;
  
  // Camera settings optimized for landscape streaming
  bool _isFlashEnabled = false;
  double _zoomLevel = 1.0;
  
  // Aspect ratio for landscape (16:9)
  static const double landscapeAspectRatio = 16.0 / 9.0;

  // Getters
  CameraState get state => _state;
  String? get errorMessage => _errorMessage;
  ApiVideoLiveStreamController? get controller => _controller;
  bool get isInitialized => _controller?.isInitialized ?? false;
  bool get canSwitchCamera => _controller?.isInitialized ?? false;
  CameraType get currentCameraType => _currentCameraType;
  bool get isFlashEnabled => _isFlashEnabled;
  double get zoomLevel => _zoomLevel;
  double get maxZoomLevel => 3.0; // Default max zoom
  double get minZoomLevel => 1.0;

  /// Initialize camera service with landscape-optimized settings
  Future<bool> initialize({
    CameraType preferredCamera = CameraType.back,
  }) async {
    if (_state == CameraState.initializing) {
      return false;
    }

    _setState(CameraState.initializing);
    _currentCameraType = preferredCamera;

    try {
      // Request camera permission
      final cameraPermission = await Permission.camera.request();
      if (cameraPermission != PermissionStatus.granted) {
        _handleError('Camera permission denied');
        return false;
      }

      // Force landscape orientation for camera
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      _setState(CameraState.ready);
      _clearError();

      if (kDebugMode) {
        print('CameraService: Initialized successfully');
        print('Landscape orientation set');
      }

      return true;
    } catch (e) {
      _handleError('Failed to initialize camera: $e');
      return false;
    }
  }

  /// Set the controller from StreamingService
  void setController(ApiVideoLiveStreamController? controller) {
    _controller = controller;
    if (controller != null && controller.isInitialized) {
      _setState(CameraState.ready);
      _clearError();
    }
    notifyListeners();
  }

  /// Switch between front and back cameras
  Future<bool> switchCamera() async {
    if (!canSwitchCamera || _controller == null) {
      return false;
    }

    try {
      await _controller!.switchCamera();
      
      // Toggle camera type
      _currentCameraType = _currentCameraType == CameraType.back 
          ? CameraType.front 
          : CameraType.back;

      if (kDebugMode) {
        print('CameraService: Switched to ${_currentCameraType.name} camera');
      }

      notifyListeners();
      return true;
    } catch (e) {
      _handleError('Failed to switch camera: $e');
      return false;
    }
  }

  /// Toggle flash (if supported and available)
  Future<bool> toggleFlash() async {
    if (_controller == null || !isInitialized) {
      return false;
    }

    try {
      // Note: The apivideo package may not have direct flash control
      // This would be implemented if the package provides flash methods
      _isFlashEnabled = !_isFlashEnabled;

      if (kDebugMode) {
        print('CameraService: Flash ${_isFlashEnabled ? "enabled" : "disabled"}');
      }

      notifyListeners();
      return true;
    } catch (e) {
      _handleError('Failed to toggle flash: $e');
      return false;
    }
  }

  /// Set zoom level (if supported)
  Future<bool> setZoomLevel(double zoom) async {
    if (_controller == null || !isInitialized) {
      return false;
    }

    try {
      final clampedZoom = zoom.clamp(minZoomLevel, maxZoomLevel);
      // Note: The apivideo package may not have direct zoom control
      // This would be implemented if the package provides zoom methods
      _zoomLevel = clampedZoom;

      if (kDebugMode) {
        print('CameraService: Zoom level set to $clampedZoom');
      }

      notifyListeners();
      return true;
    } catch (e) {
      _handleError('Failed to set zoom level: $e');
      return false;
    }
  }

  /// Get camera preview size optimized for landscape
  Size getPreviewSize() {
    // Default 16:9 landscape size for streaming
    return const Size(1280, 720);
  }

  /// Get the optimal aspect ratio for landscape streaming
  double getAspectRatio() {
    return landscapeAspectRatio;
  }

  /// Check if current camera supports flash
  bool get hasFlash {
    // Most back cameras have flash, front cameras typically don't
    return _currentCameraType == CameraType.back;
  }

  /// Get camera specifications
  Map<String, dynamic> getCameraSpecs() {
    return {
      'cameraType': _currentCameraType.toString(),
      'hasFlash': hasFlash,
      'aspectRatio': getAspectRatio(),
      'previewSize': getPreviewSize().toString(),
      'isInitialized': isInitialized,
    };
  }

  void _setState(CameraState state) {
    _state = state;
    notifyListeners();
  }

  void _handleError(String error) {
    _state = CameraState.error;
    _errorMessage = error;
    notifyListeners();

    if (kDebugMode) {
      print('CameraService Error: $error');
    }
  }

  void _clearError() {
    _errorMessage = null;
  }

  /// Clear current error and reset to ready state
  void clearError() {
    if (_state == CameraState.error) {
      _errorMessage = null;
      _setState(CameraState.ready);
    }
  }

  /// Reset camera settings to defaults
  void resetSettings() {
    _isFlashEnabled = false;
    _zoomLevel = 1.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _state = CameraState.disposed;
    
    // Restore all orientations when disposing
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    super.dispose();
  }
}