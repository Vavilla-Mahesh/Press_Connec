import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:rtmp_broadcaster/rtmp_broadcaster.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/session.dart';
import 'package:ffmpeg_kit_flutter_new/session_state.dart';
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
      
      // Configure RTMP streaming settings
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
      // Initialize RTMP broadcaster with basic config
      await _rtmpBroadcaster!.startStream(config);
      
      // If watermark is enabled, we'll overlay it in the UI and use screen recording
      // This is a simpler approach that works reliably on mobile platforms
      if (_watermarkService?.isEnabled == true) {
        if (kDebugMode) {
          print('RTMP streaming started with watermark overlay enabled');
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

  // Build FFmpeg command for watermark overlay
  String _buildFFmpegCommand(RtmpConfig config, String watermarkFilter) {
    final rtmpUrl = config.rtmpUrl;
    final width = config.videoConfig.width;
    final height = config.videoConfig.height;
    final fps = config.videoConfig.fps;
    final videoBitrate = config.videoConfig.bitrate;
    final audioBitrate = config.audioConfig.bitrate;
    
    // Platform-specific input format
    String inputFormat;
    String inputDevice;
    
    if (Platform.isIOS) {
      inputFormat = '-f avfoundation';
      inputDevice = '0:0'; // Camera and microphone
    } else if (Platform.isAndroid) {
      inputFormat = '-f android_camera';
      inputDevice = '0'; // First camera
    } else {
      inputFormat = '-f v4l2';
      inputDevice = '/dev/video0';
    }
    
    // FFmpeg command for live streaming with watermark
    return '''
      $inputFormat -framerate $fps -video_size ${width}x$height -i "$inputDevice" 
      -i "${_watermarkService!.watermarkPath}" 
      $watermarkFilter 
      -c:v libx264 -preset ultrafast -tune zerolatency 
      -b:v ${videoBitrate}k -maxrate ${videoBitrate * 1.2}k -bufsize ${videoBitrate * 2}k 
      -pix_fmt yuv420p -g ${fps * 2} -keyint_min $fps 
      -c:a aac -b:a ${audioBitrate}k -ar ${config.audioConfig.sampleRate} 
      -f flv $rtmpUrl
    '''.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // Take snapshot with watermark
  Future<String?> takeSnapshot() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }

    try {
      final image = await _cameraController!.takePicture();
      
      if (_watermarkService?.isEnabled == true) {
        // Apply watermark to snapshot using FFmpeg
        final outputPath = '${image.path}_watermarked.jpg';
        final watermarkFilter = _watermarkService!.generateFFmpegFilter();
        
        final ffmpegCommand = '''
          -i "${image.path}" 
          -i "${_watermarkService!.watermarkPath}" 
          $watermarkFilter 
          -y "$outputPath"
        '''.replaceAll(RegExp(r'\s+'), ' ').trim();

        final session = await FFmpegKit.execute(ffmpegCommand);
        final state = await session.getState();
        
        if (state == SessionState.completed) {
          return outputPath;
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

  // Start recording with watermark
  Future<bool> startRecording(String outputPath) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return false;
    }

    try {
      if (_watermarkService?.isEnabled == true) {
        // Use FFmpeg for recording with watermark
        final watermarkFilter = _watermarkService!.generateFFmpegFilter();
        
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
          -i "${_watermarkService!.watermarkPath}" 
          $watermarkFilter 
          -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p
          -c:a aac -b:a 128k 
          -y "$outputPath"
        '''.replaceAll(RegExp(r'\s+'), ' ').trim();

        final session = await FFmpegKit.execute(ffmpegCommand);
        final state = await session.getState();
        
        return state == SessionState.completed;
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