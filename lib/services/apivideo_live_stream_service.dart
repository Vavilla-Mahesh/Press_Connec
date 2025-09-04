import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

enum StreamingState {
  idle,
  initializing,
  ready,
  streaming,
  stopping,
  error
}

class ApiVideoLiveStreamService extends ChangeNotifier with WidgetsBindingObserver {
  ApiVideoLiveStreamController? _controller;
  StreamingState _state = StreamingState.idle;
  String? _errorMessage;
  String? _streamKey;
  bool _isMuted = false;
  CameraPosition _cameraPosition = CameraPosition.back;

  // Getters
  StreamingState get state => _state;
  String? get errorMessage => _errorMessage;
  ApiVideoLiveStreamController? get controller => _controller;
  bool get isStreaming => _state == StreamingState.streaming;
  bool get canStartStream => _state == StreamingState.ready && _streamKey != null && !isStreaming;
  bool get canStopStream => isStreaming;
  bool get isMuted => _isMuted;
  CameraPosition get cameraPosition => _cameraPosition;

  Future<bool> initialize() async {
    if (_state != StreamingState.idle) {
      return false;
    }

    _setState(StreamingState.initializing);

    try {
      // Force landscape orientation for streaming
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // Request permissions
      final cameraPermission = await Permission.camera.request();
      final microphonePermission = await Permission.microphone.request();

      if (cameraPermission != PermissionStatus.granted) {
        _handleError('Camera permission denied');
        return false;
      }

      if (microphonePermission != PermissionStatus.granted) {
        _handleError('Microphone permission denied');
        return false;
      }

      // Initialize ApiVideo Live Stream Controller
      _controller = ApiVideoLiveStreamController(
        initialAudioConfig: AudioConfig(),
        initialVideoConfig: VideoConfig.withDefaultBitrate(
          resolution: Resolution.RESOLUTION_720,
        ),
        onConnectionSuccess: () {
          if (kDebugMode) {
            print('Live stream connection successful');
          }
        },
        onConnectionFailed: (String reason) {
          _handleError('Connection failed: $reason');
        },
        onDisconnection: () {
          if (kDebugMode) {
            print('Live stream disconnected');
          }
          if (_state == StreamingState.streaming) {
            _setState(StreamingState.ready);
          }
        },
        onError: (String error) {
          _handleError('Live stream error: $error');
        },
      );

      // Add lifecycle observer
      WidgetsBinding.instance.addObserver(this);

      _setState(StreamingState.ready);
      return true;
    } catch (e) {
      _handleError('Initialization failed: $e');
      return false;
    }
  }

  Future<bool> startStreaming(String streamKey) async {
    _streamKey = streamKey;

    if (!canStartStream || _controller == null) {
      _handleError('Cannot start streaming in current state');
      return false;
    }

    try {
      // Enable wakelock to keep device awake
      await WakelockPlus.enable();

      // Start streaming
      await _controller!.startStreaming(streamKey: streamKey);

      _setState(StreamingState.streaming);
      return true;
    } catch (e) {
      _handleError('Failed to start streaming: $e');
      await WakelockPlus.disable();
      return false;
    }
  }

  Future<bool> stopStreaming() async {
    if (!canStopStream || _controller == null) {
      return true;
    }

    _setState(StreamingState.stopping);

    try {
      await _controller!.stopStreaming();
      await WakelockPlus.disable();
      _setState(StreamingState.ready);
      return true;
    } catch (e) {
      _handleError('Failed to stop streaming: $e');
      return false;
    }
  }

  Future<bool> switchCamera() async {
    if (_controller == null) {
      return false;
    }

    try {
      _cameraPosition = _cameraPosition == CameraPosition.back 
          ? CameraPosition.front 
          : CameraPosition.back;
      
      await _controller!.switchCamera();
      notifyListeners();
      return true;
    } catch (e) {
      _handleError('Failed to switch camera: $e');
      return false;
    }
  }

  Future<bool> toggleMute() async {
    if (_controller == null) {
      return false;
    }

    try {
      _isMuted = !_isMuted;
      if (_isMuted) {
        await _controller!.setAudioConfig(AudioConfig(bitrate: 0));
      } else {
        await _controller!.setAudioConfig(AudioConfig());
      }
      notifyListeners();
      return true;
    } catch (e) {
      _handleError('Failed to toggle mute: $e');
      return false;
    }
  }

  void setStreamKey(String streamKey) {
    _streamKey = streamKey;
    notifyListeners();
  }

  void reset() {
    _streamKey = null;
    _errorMessage = null;
    _isMuted = false;
    _cameraPosition = CameraPosition.back;
    if (_state != StreamingState.streaming) {
      _setState(StreamingState.idle);
    }
  }

  void _setState(StreamingState state) {
    _state = state;
    notifyListeners();
  }

  void _handleError(String error) {
    _state = StreamingState.error;
    _errorMessage = error;
    notifyListeners();

    if (kDebugMode) {
      print('ApiVideoLiveStreamService Error: $error');
    }
  }

  void clearError() {
    if (_state == StreamingState.error) {
      _errorMessage = null;
      _setState(StreamingState.ready);
    }
  }

  // WidgetsBindingObserver methods
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (isStreaming) {
          stopStreaming();
        }
        break;
      case AppLifecycleState.resumed:
        // App resumed - controller should auto-reconnect if needed
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Stop streaming if active
    if (isStreaming) {
      stopStreaming();
    }
    
    // Restore orientation to all when disposing
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // Disable wakelock
    WakelockPlus.disable();
    
    // Dispose controller
    _controller?.dispose();
    
    super.dispose();
  }
}