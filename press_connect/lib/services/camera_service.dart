import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
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
  CameraController? _controller;
  CameraState _state = CameraState.uninitialized;
  String? _errorMessage;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  CameraType _currentCameraType = CameraType.back;
  
  // Camera settings optimized for landscape streaming
  ResolutionPreset _resolution = ResolutionPreset.high;
  bool _isFlashEnabled = false;
  bool _isAutoFocusEnabled = true;
  double _zoomLevel = 1.0;
  
  // Aspect ratio for landscape (16:9)
  static const double landscapeAspectRatio = 16.0 / 9.0;

  // Getters
  CameraState get state => _state;
  String? get errorMessage => _errorMessage;
  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get canSwitchCamera => _cameras.length > 1;
  CameraType get currentCameraType => _currentCameraType;
  List<CameraDescription> get availableCameras => _cameras;
  bool get isFlashEnabled => _isFlashEnabled;
  bool get isAutoFocusEnabled => _isAutoFocusEnabled;
  double get zoomLevel => _zoomLevel;
  double get maxZoomLevel => _controller?.value.maxZoomLevel ?? 1.0;
  double get minZoomLevel => _controller?.value.minZoomLevel ?? 1.0;
  ResolutionPreset get resolution => _resolution;

  /// Initialize camera service with landscape-optimized settings
  Future<bool> initialize({
    ResolutionPreset resolution = ResolutionPreset.high,
    CameraType preferredCamera = CameraType.back,
  }) async {
    if (_state == CameraState.initializing) {
      return false;
    }

    _setState(CameraState.initializing);
    _resolution = resolution;

    try {
      // Request camera permission
      final cameraPermission = await Permission.camera.request();
      if (cameraPermission != PermissionStatus.granted) {
        _handleError('Camera permission denied');
        return false;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _handleError('No cameras found on device');
        return false;
      }

      // Select preferred camera
      _selectedCameraIndex = _findCameraIndex(preferredCamera);
      _currentCameraType = preferredCamera;

      // Initialize camera controller
      await _initializeCameraController();
      
      // Force landscape orientation for camera
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      _setState(CameraState.ready);
      _clearError();

      if (kDebugMode) {
        print('CameraService: Initialized successfully');
        print('Camera: ${_cameras[_selectedCameraIndex].name}');
        print('Resolution: $_resolution');
        print('Landscape orientation set');
      }

      return true;
    } catch (e) {
      _handleError('Failed to initialize camera: $e');
      return false;
    }
  }

  /// Switch between front and back cameras
  Future<bool> switchCamera() async {
    if (!canSwitchCamera || _state != CameraState.ready) {
      return false;
    }

    try {
      // Determine next camera type
      final nextCameraType = _currentCameraType == CameraType.back 
          ? CameraType.front 
          : CameraType.back;

      final nextCameraIndex = _findCameraIndex(nextCameraType);
      if (nextCameraIndex == -1) {
        _handleError('Requested camera type not available');
        return false;
      }

      // Dispose current controller
      await _controller?.dispose();

      // Switch to new camera
      _selectedCameraIndex = nextCameraIndex;
      _currentCameraType = nextCameraType;

      // Initialize new camera controller
      await _initializeCameraController();

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

  /// Set camera resolution
  Future<bool> setResolution(ResolutionPreset resolution) async {
    if (_state != CameraState.ready || _resolution == resolution) {
      return false;
    }

    try {
      _resolution = resolution;
      
      // Reinitialize with new resolution
      await _controller?.dispose();
      await _initializeCameraController();

      if (kDebugMode) {
        print('CameraService: Resolution changed to $resolution');
      }

      notifyListeners();
      return true;
    } catch (e) {
      _handleError('Failed to set resolution: $e');
      return false;
    }
  }

  /// Toggle flash (if supported)
  Future<bool> toggleFlash() async {
    if (_controller == null || !isInitialized) {
      return false;
    }

    try {
      final newFlashMode = _isFlashEnabled ? FlashMode.off : FlashMode.torch;
      await _controller!.setFlashMode(newFlashMode);
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

  /// Set zoom level
  Future<bool> setZoomLevel(double zoom) async {
    if (_controller == null || !isInitialized) {
      return false;
    }

    try {
      final clampedZoom = zoom.clamp(minZoomLevel, maxZoomLevel);
      await _controller!.setZoomLevel(clampedZoom);
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

  /// Focus on a specific point (for touch-to-focus)
  Future<bool> focusOnPoint(Offset point) async {
    if (_controller == null || !isInitialized) {
      return false;
    }

    try {
      await _controller!.setFocusPoint(point);
      await _controller!.setExposurePoint(point);

      if (kDebugMode) {
        print('CameraService: Focus set to point $point');
      }

      return true;
    } catch (e) {
      _handleError('Failed to focus on point: $e');
      return false;
    }
  }

  /// Enable/disable auto focus
  Future<bool> setAutoFocus(bool enabled) async {
    if (_controller == null || !isInitialized) {
      return false;
    }

    try {
      final focusMode = enabled ? FocusMode.auto : FocusMode.locked;
      await _controller!.setFocusMode(focusMode);
      _isAutoFocusEnabled = enabled;

      if (kDebugMode) {
        print('CameraService: Auto focus ${enabled ? "enabled" : "disabled"}');
      }

      notifyListeners();
      return true;
    } catch (e) {
      _handleError('Failed to set auto focus: $e');
      return false;
    }
  }

  /// Take a picture (optional feature)
  Future<XFile?> takePicture() async {
    if (_controller == null || !isInitialized) {
      _handleError('Camera not ready for taking pictures');
      return null;
    }

    try {
      final image = await _controller!.takePicture();
      
      if (kDebugMode) {
        print('CameraService: Picture taken successfully');
      }

      return image;
    } catch (e) {
      _handleError('Failed to take picture: $e');
      return null;
    }
  }

  /// Get camera preview size optimized for landscape
  Size getPreviewSize() {
    if (_controller?.value.previewSize == null) {
      // Default 16:9 landscape size
      return const Size(1280, 720);
    }

    final previewSize = _controller!.value.previewSize!;
    
    // Ensure landscape orientation (width > height)
    if (previewSize.width > previewSize.height) {
      return previewSize;
    } else {
      // Swap dimensions for landscape
      return Size(previewSize.height, previewSize.width);
    }
  }

  /// Get the optimal aspect ratio for landscape streaming
  double getAspectRatio() {
    final previewSize = getPreviewSize();
    return previewSize.width / previewSize.height;
  }

  /// Check if current camera supports flash
  bool get hasFlash {
    if (_cameras.isEmpty || _selectedCameraIndex >= _cameras.length) {
      return false;
    }
    
    // Most back cameras have flash, front cameras typically don't
    return _currentCameraType == CameraType.back;
  }

  /// Get camera specifications
  Map<String, dynamic> getCameraSpecs() {
    if (_cameras.isEmpty || _selectedCameraIndex >= _cameras.length) {
      return {};
    }

    final camera = _cameras[_selectedCameraIndex];
    return {
      'name': camera.name,
      'lensDirection': camera.lensDirection.toString(),
      'sensorOrientation': camera.sensorOrientation,
      'hasFlash': hasFlash,
      'resolution': _resolution.toString(),
      'aspectRatio': getAspectRatio(),
      'previewSize': getPreviewSize().toString(),
    };
  }

  /// Initialize camera controller with landscape-optimized settings
  Future<void> _initializeCameraController() async {
    if (_cameras.isEmpty || _selectedCameraIndex >= _cameras.length) {
      throw Exception('Invalid camera selection');
    }

    final camera = _cameras[_selectedCameraIndex];
    
    _controller = CameraController(
      camera,
      _resolution,
      enableAudio: true,
      // Optimize for landscape streaming
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    // Add error listener
    _controller!.addListener(() {
      if (_controller!.value.hasError) {
        _handleError('Camera error: ${_controller!.value.errorDescription}');
      }
    });

    await _controller!.initialize();

    // Set initial camera settings
    await _controller!.setFlashMode(_isFlashEnabled ? FlashMode.torch : FlashMode.off);
    await _controller!.setFocusMode(_isAutoFocusEnabled ? FocusMode.auto : FocusMode.locked);

    if (kDebugMode) {
      final specs = getCameraSpecs();
      print('CameraService: Controller initialized with specs: $specs');
    }
  }

  /// Find camera index by type
  int _findCameraIndex(CameraType type) {
    final targetLensDirection = type == CameraType.back 
        ? CameraLensDirection.back 
        : CameraLensDirection.front;

    final index = _cameras.indexWhere(
      (camera) => camera.lensDirection == targetLensDirection
    );

    return index != -1 ? index : 0; // Fallback to first camera
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
    _isAutoFocusEnabled = true;
    _zoomLevel = 1.0;
    _resolution = ResolutionPreset.high;
    
    if (_controller != null && isInitialized) {
      _controller!.setFlashMode(FlashMode.off);
      _controller!.setFocusMode(FocusMode.auto);
      _controller!.setZoomLevel(1.0);
    }
    
    notifyListeners();
  }

  @override
  void dispose() {
    _state = CameraState.disposed;
    _controller?.dispose();
    
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