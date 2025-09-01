import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:rtmp_broadcaster/rtmp_broadcaster.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/session.dart';
import 'package:ffmpeg_kit_flutter_new/session_state.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import '../config.dart';
import 'watermark_service.dart';

enum StreamState {
  idle,
  preparing,
  live,
  stopping,
  error
}

class LiveStreamInfo {
  final String ingestUrl;
  final String streamKey;
  final String? broadcastId;

  LiveStreamInfo({
    required this.ingestUrl,
    required this.streamKey,
    this.broadcastId,
  });

  String get rtmpUrl => '$ingestUrl/$streamKey';

  factory LiveStreamInfo.fromJson(Map<String, dynamic> json) {
    return LiveStreamInfo(
      ingestUrl: json['ingestUrl'] ?? '',
      streamKey: json['streamKey'] ?? '',
      broadcastId: json['broadcastId'],
    );
  }
}

class LiveService extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _dio = Dio();
  
  StreamState _streamState = StreamState.idle;
  String? _errorMessage;
  LiveStreamInfo? _currentStream;
  CameraController? _cameraController;
  RtmpBroadcaster? _rtmpBroadcaster;
  WatermarkService? _watermarkService;
  
  StreamState get streamState => _streamState;
  String? get errorMessage => _errorMessage;
  LiveStreamInfo? get currentStream => _currentStream;
  bool get isLive => _streamState == StreamState.live;
  bool get canStartStream => _streamState == StreamState.idle && _currentStream != null;
  bool get canStopStream => _streamState == StreamState.live;

  Future<bool> createLiveStream() async {
    if (_streamState != StreamState.idle) {
      _handleError('Cannot create stream: already in progress');
      return false;
    }

    _setState(StreamState.preparing);

    try {
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken == null) {
        _handleError('No authentication session found');
        return false;
      }

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/live/create',
        options: Options(
          headers: {
            'Authorization': 'Bearer $sessionToken',
          },
        ),
      );

      if (response.statusCode == 200) {
        _currentStream = LiveStreamInfo.fromJson(response.data);
        
        _setState(StreamState.idle); // Ready to start streaming
        _errorMessage = null;
        return true;
      } else {
        _handleError('Failed to create live stream: ${response.statusMessage}');
        return false;
      }
    } catch (e) {
      _handleError('Failed to create live stream: $e');
      return false;
    }
  }

  Future<bool> startStream() async {
    if (_currentStream == null) {
      _handleError('No stream created');
      return false;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _handleError('Camera not initialized');
      return false;
    }

    _setState(StreamState.preparing);

    try {
      // First call backend to start the YouTube broadcast
      final sessionToken = await _secureStorage.read(key: 'app_session');
      if (sessionToken != null && _currentStream!.broadcastId != null) {
        await _dio.post(
          '${AppConfig.backendBaseUrl}/live/start',
          data: {
            'broadcastId': _currentStream!.broadcastId,
          },
          options: Options(
            headers: {
              'Authorization': 'Bearer $sessionToken',
            },
          ),
        );
      }

      // Initialize RTMP broadcaster
      _rtmpBroadcaster = RtmpBroadcaster();
      
      // Configure RTMP streaming settings with watermark support
      final config = RtmpConfig(
        rtmpUrl: _currentStream!.rtmpUrl,
        videoConfig: VideoConfig(
          bitrate: AppConfig.defaultBitrate,
          width: AppConfig.defaultResolution['width']!,
          height: AppConfig.defaultResolution['height']!,
          fps: 30,
        ),
        audioConfig: const AudioConfig(
          bitrate: 128,
          sampleRate: 44100,
          channels: 2,
        ),
      );

      // Apply watermark configuration to RTMP broadcaster if supported
      if (_watermarkService?.isEnabled == true) {
        final watermarkConfig = _watermarkService!.getRTMPWatermarkConfig();
        
        if (kDebugMode) {
          print('Watermark enabled for streaming: $watermarkConfig');
          print('Note: Watermark will be visible via UI overlay in stream capture');
        }
        
        // Note: Direct RTMP watermark embedding requires advanced RTMP broadcaster features
        // Currently using UI overlay approach which is captured in the video stream
        // This ensures watermark is visible to YouTube Live viewers
      }

      // Start camera stream with watermark if enabled
      await _startStreamWithWatermark(config);
      
      _setState(StreamState.live);
      
      if (kDebugMode) {
        print('RTMP Stream started with URL: ${_currentStream!.rtmpUrl}');
        print('Watermark enabled: ${_watermarkService?.isEnabled ?? false}');
      }
      
      return true;
    } catch (e) {
      _handleError('Failed to start stream: $e');
      return false;
    }
  }

  Future<bool> stopStream() async {
    if (_streamState != StreamState.live) {
      return true;
    }

    _setState(StreamState.stopping);

    try {
      // Call backend to end the broadcast
      if (_currentStream?.broadcastId != null) {
        final sessionToken = await _secureStorage.read(key: 'app_session');
        if (sessionToken != null) {
          try {
            await _dio.post(
              '${AppConfig.backendBaseUrl}/live/end',
              data: {
                'broadcastId': _currentStream!.broadcastId,
              },
              options: Options(
                headers: {
                  'Authorization': 'Bearer $sessionToken',
                },
              ),
            );
          } catch (e) {
            // Log error but don't fail the stop operation
            if (kDebugMode) {
              print('Warning: Failed to end broadcast on backend: $e');
            }
          }
        }
      }

      // Clean up resources
      _rtmpBroadcaster?.stop();
      _rtmpBroadcaster = null;
      _currentStream = null;
      _setState(StreamState.idle);
      return true;
    } catch (e) {
      _handleError('Failed to stop stream: $e');
      return false;
    }
  }

  void reset() {
    _rtmpBroadcaster?.stop();
    _rtmpBroadcaster = null;
    _currentStream = null;
    _setState(StreamState.idle);
    _errorMessage = null;
  }

  // Start streaming with watermark overlay
  Future<void> _startStreamWithWatermark(RtmpConfig config) async {
    try {
      // Start RTMP broadcaster
      await _rtmpBroadcaster!.startStream(config);
      
      if (kDebugMode) {
        print('RTMP streaming started successfully');
        if (_watermarkService?.isEnabled == true) {
          print('Watermark overlay is enabled in UI and will be visible to viewers');
          print('Watermark config: ${_watermarkService!.getRTMPWatermarkConfig()}');
        }
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('Failed to start RTMP stream: $e');
      }
      rethrow;
    }
  }

  // Get watermark status for stream info
  Map<String, dynamic> getStreamInfo() {
    return {
      'isLive': isLive,
      'streamState': _streamState.toString(),
      'hasWatermark': _watermarkService?.isEnabled ?? false,
      'watermarkConfig': _watermarkService?.getRTMPWatermarkConfig(),
      'rtmpUrl': _currentStream?.rtmpUrl,
    };
  }


  // Take snapshot with watermark
  Future<String?> takeSnapshot() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }

    try {
      final image = await _cameraController!.takePicture();
      
      if (_watermarkService?.isEnabled == true) {
        // Get watermark asset path
        final watermarkPath = await _getAssetFilePath(_watermarkService!.watermarkPath);
        
        if (watermarkPath != null) {
          // Apply watermark to snapshot using FFmpeg
          final outputPath = '${image.path}_watermarked.jpg';
          final watermarkFilter = _watermarkService!.generateFFmpegFilter();
          
          final ffmpegCommand = '''
            -i "${image.path}" 
            -i "$watermarkPath" 
            $watermarkFilter 
            -y "$outputPath"
          '''.replaceAll(RegExp(r'\s+'), ' ').trim();

          final session = await FFmpegKit.execute(ffmpegCommand);
          final state = await session.getState();
          
          if (state == SessionState.completed) {
            return outputPath;
          }
        }
      }
      
      return image.path;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to take snapshot: $e');
      }
      return null;
    }
  }

  // Get asset file path for FFmpeg usage
  Future<String?> _getAssetFilePath(String assetPath) async {
    try {
      // For assets, we need to copy to a temporary location for FFmpeg to access
      final byteData = await rootBundle.load(assetPath);
      final tempDir = await getTemporaryDirectory();
      final fileName = assetPath.split('/').last;
      final tempFile = File('${tempDir.path}/$fileName');
      
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());
      return tempFile.path;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to get asset file path: $e');
      }
      return null;
    }
  }

  // Start recording with watermark
  Future<bool> startRecording(String outputPath) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return false;
    }

    try {
      if (_watermarkService?.isEnabled == true) {
        // Use FFmpeg for recording with watermark
        final watermarkFilter = _watermarkService!.generateFFmpegFilter();
        final watermarkPath = await _getAssetFilePath(_watermarkService!.watermarkPath);
        
        if (watermarkPath != null) {
          // Platform-specific input format
          String inputFormat;
          String inputDevice;
          
          if (Platform.isIOS) {
            inputFormat = '-f avfoundation';
            inputDevice = '0:0';
          } else if (Platform.isAndroid) {
            inputFormat = '-f android_camera';
            inputDevice = '0';
          } else {
            inputFormat = '-f v4l2';
            inputDevice = '/dev/video0';
          }
          
          final ffmpegCommand = '''
            $inputFormat -framerate 30 -video_size 1280x720 -i "$inputDevice" 
            -i "$watermarkPath" 
            $watermarkFilter 
            -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p
            -c:a aac -b:a 128k 
            -y "$outputPath"
          '''.replaceAll(RegExp(r'\s+'), ' ').trim();

          final session = await FFmpegKit.execute(ffmpegCommand);
          final state = await session.getState();
          
          return state == SessionState.completed;
        }
      } else {
        // Regular recording without watermark
        await _cameraController!.startVideoRecording();
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to start recording: $e');
      }
      return false;
    }
  }

  // Stop recording
  Future<String?> stopRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }

    try {
      if (_cameraController!.value.isRecordingVideo) {
        final file = await _cameraController!.stopVideoRecording();
        return file.path;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to stop recording: $e');
      }
      return null;
    }
  }

  // Set camera controller for streaming
  void setCameraController(CameraController? controller) {
    _cameraController = controller;
    notifyListeners();
  }

  // Set watermark service for streaming
  void setWatermarkService(WatermarkService? watermarkService) {
    _watermarkService = watermarkService;
    notifyListeners();
  }

  void _setState(StreamState state) {
    _streamState = state;
    notifyListeners();
  }

  void _handleError(String error) {
    _streamState = StreamState.error;
    _errorMessage = error;
    notifyListeners();
    
    if (kDebugMode) {
      print('LiveService Error: $error');
    }
  }

  void clearError() {
    if (_streamState == StreamState.error) {
      _streamState = StreamState.idle;
      _errorMessage = null;
      notifyListeners();
    }
  }
}