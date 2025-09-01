import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/session.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'watermark_service.dart';

enum RTMPStreamState {
  idle,
  preparing,
  streaming,
  stopping,
  error
}

class RTMPStreamingService extends ChangeNotifier {
  CameraController? _cameraController;
  RTMPStreamState _state = RTMPStreamState.idle;
  String? _errorMessage;
  String? _rtmpUrl;
  WatermarkService? _watermarkService;
  FFmpegSession? _streamingSession;
  String? _watermarkTempPath;
  
  RTMPStreamState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isStreaming => _state == RTMPStreamState.streaming;
  bool get canStart => _state == RTMPStreamState.idle;
  bool get canStop => _state == RTMPStreamState.streaming;

  Future<void> initialize({
    required CameraController cameraController,
    required WatermarkService watermarkService,
  }) async {
    _cameraController = cameraController;
    _watermarkService = watermarkService;
    
    // Prepare watermark file
    await _prepareWatermarkFile();
  }

  Future<void> _prepareWatermarkFile() async {
    try {
      if (_watermarkService?.watermarkPath.startsWith('assets/') == true) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/watermark.png');
        
        final byteData = await rootBundle.load(_watermarkService!.watermarkPath);
        await tempFile.writeAsBytes(byteData.buffer.asUint8List());
        _watermarkTempPath = tempFile.path;
        
        if (kDebugMode) {
          print('Watermark asset copied to: $_watermarkTempPath');
        }
      } else {
        _watermarkTempPath = _watermarkService?.watermarkPath;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to prepare watermark file: $e');
      }
      _watermarkTempPath = null;
    }
  }

  Future<bool> startStreaming(String rtmpUrl) async {
    if (_state != RTMPStreamState.idle) {
      _setError('Cannot start streaming: not in idle state');
      return false;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _setError('Camera not initialized');
      return false;
    }

    _rtmpUrl = rtmpUrl;
    _setState(RTMPStreamState.preparing);

    try {
      // Start the RTMP streaming using FFmpeg
      await _startFFmpegStreaming(rtmpUrl);
      
      _setState(RTMPStreamState.streaming);
      
      if (kDebugMode) {
        print('RTMP Streaming started to: $rtmpUrl');
        print('Watermark enabled: ${_watermarkService?.isEnabled}');
        if (_watermarkService?.isEnabled == true) {
          print('Watermark opacity: ${_watermarkService!.opacity}');
          print('Watermark path: ${_watermarkService!.watermarkPath}');
        }
      }
      
      return true;
    } catch (e) {
      _setError('Failed to start streaming: $e');
      return false;
    }
  }

  Future<void> _startFFmpegStreaming(String rtmpUrl) async {
    try {
      // Build FFmpeg command for RTMP streaming
      String ffmpegCommand = await _buildFFmpegCommand(rtmpUrl);
      
      if (kDebugMode) {
        print('FFmpeg command: $ffmpegCommand');
      }
      
      // Execute FFmpeg streaming command
      _streamingSession = await FFmpegKit.executeAsync(
        ffmpegCommand,
        (session) async {
          final returnCode = await session.getReturnCode();
          if (kDebugMode) {
            print('FFmpeg session completed with return code: $returnCode');
          }
          
          if (!ReturnCode.isSuccess(returnCode)) {
            final logs = await session.getLogs();
            String errorMessage = 'FFmpeg streaming failed';
            if (logs.isNotEmpty) {
              errorMessage += ': ${logs.last.getMessage()}';
            }
            _setError(errorMessage);
          }
        },
        (log) {
          if (kDebugMode) {
            print('FFmpeg log: ${log.getMessage()}');
          }
        },
        (statistics) {
          if (kDebugMode && statistics.getVideoFrameNumber() > 0) {
            print('Streaming stats: ${statistics.getVideoFrameNumber()} frames, ${statistics.getBitrate()} kbps');
          }
        },
      );
      
    } catch (e) {
      throw Exception('Failed to start FFmpeg streaming: $e');
    }
  }

  Future<String> _buildFFmpegCommand(String rtmpUrl) async {
    List<String> commandParts = [];
    
    // Input source (camera)
    if (Platform.isAndroid) {
      commandParts.addAll([
        '-f', 'android_camera',
        '-camera_index', '0',
        '-i', '-',
      ]);
    } else if (Platform.isIOS) {
      commandParts.addAll([
        '-f', 'avfoundation',
        '-video_size', '1280x720',
        '-framerate', '30',
        '-i', '0:0', // Video:Audio input
      ]);
    } else {
      // Fallback for other platforms
      commandParts.addAll([
        '-f', 'v4l2',
        '-video_size', '1280x720',
        '-framerate', '30',
        '-i', '/dev/video0',
      ]);
    }
    
    // Add watermark if enabled
    if (_watermarkService?.isEnabled == true && _watermarkTempPath != null) {
      commandParts.addAll([
        '-i', _watermarkTempPath!,
        '-filter_complex', _buildWatermarkFilter(),
      ]);
    }
    
    // Video encoding settings
    commandParts.addAll([
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-tune', 'zerolatency',
      '-b:v', '2500k',
      '-maxrate', '2500k',
      '-bufsize', '5000k',
      '-g', '60', // GOP size (2 seconds at 30fps)
      '-keyint_min', '30',
      '-sc_threshold', '0',
    ]);
    
    // Audio encoding settings
    commandParts.addAll([
      '-c:a', 'aac',
      '-b:a', '128k',
      '-ar', '44100',
      '-ac', '2',
    ]);
    
    // Output format and URL
    commandParts.addAll([
      '-f', 'flv',
      '-flvflags', 'no_duration_filesize',
      rtmpUrl,
    ]);
    
    return commandParts.join(' ');
  }

  String _buildWatermarkFilter() {
    final opacity = _watermarkService!.alphaValue;
    
    // Position watermark in top-right corner with 20px margin
    return '[1:v]scale=200:200,format=rgba,colorchannelmixer=aa=$opacity[wm];'
           '[0:v][wm]overlay=W-w-20:20:enable=always';
  }

  Future<bool> stopStreaming() async {
    if (_state != RTMPStreamState.streaming) {
      return true;
    }

    _setState(RTMPStreamState.stopping);

    try {
      // Cancel FFmpeg session
      if (_streamingSession != null) {
        await _streamingSession!.cancel();
        _streamingSession = null;
      }
      
      // Wait a moment for cleanup
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (kDebugMode) {
        print('RTMP streaming stopped');
      }
      
      _setState(RTMPStreamState.idle);
      return true;
    } catch (e) {
      _setError('Failed to stop streaming: $e');
      return false;
    }
  }

  void _setState(RTMPStreamState state) {
    _state = state;
    _errorMessage = null;
    notifyListeners();
  }

  void _setError(String error) {
    _state = RTMPStreamState.error;
    _errorMessage = error;
    notifyListeners();
    
    if (kDebugMode) {
      print('RTMPStreamingService Error: $error');
    }
  }

  void clearError() {
    if (_state == RTMPStreamState.error) {
      _state = RTMPStreamState.idle;
      _errorMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_streamingSession != null) {
      _streamingSession!.cancel();
    }
    super.dispose();
  }
}