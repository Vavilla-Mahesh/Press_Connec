import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:camera/camera.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'dart:io';
import '../config.dart';

enum StreamState {
  idle,
  preparing,
  live,
  stopping,
  error
}

enum StreamQuality {
  quality720p('720p'),
  quality1080p('1080p');

  const StreamQuality(this.value);
  final String value;
}

enum StreamVisibility {
  public('public'),
  unlisted('unlisted'),
  private('private');

  const StreamVisibility(this.value);
  final String value;
}

enum StreamStatus {
  live('live'),
  scheduled('scheduled'),
  offline('offline');

  const StreamStatus(this.value);
  final String value;
}

class LiveStreamInfo {
  final String ingestUrl;
  final String streamKey;
  final String? broadcastId;
  final String? streamId;
  final StreamQuality quality;
  final StreamVisibility visibility;
  final StreamStatus status;
  final String? title;
  final String? watchUrl;

  LiveStreamInfo({
    required this.ingestUrl,
    required this.streamKey,
    this.broadcastId,
    this.streamId,
    this.quality = StreamQuality.quality720p,
    this.visibility = StreamVisibility.public,
    this.status = StreamStatus.live,
    this.title,
    this.watchUrl,
  });

  String get rtmpUrl => '$ingestUrl/$streamKey';

  factory LiveStreamInfo.fromJson(Map<String, dynamic> json) {
    return LiveStreamInfo(
      ingestUrl: json['ingestUrl'] ?? '',
      streamKey: json['streamKey'] ?? '',
      broadcastId: json['broadcastId'],
      streamId: json['streamId'],
      quality: StreamQuality.values.firstWhere(
        (q) => q.value == json['quality'],
        orElse: () => StreamQuality.quality720p,
      ),
      visibility: StreamVisibility.values.firstWhere(
        (v) => v.value == json['visibility'],
        orElse: () => StreamVisibility.public,
      ),
      status: StreamStatus.values.firstWhere(
        (s) => s.value == json['status'],
        orElse: () => StreamStatus.live,
      ),
      title: json['title'],
      watchUrl: json['watchUrl'],
    );
  }
}

class StreamConfiguration {
  final String? title;
  final String? description;
  final StreamQuality quality;
  final StreamVisibility visibility;
  final StreamStatus status;

  StreamConfiguration({
    this.title,
    this.description,
    this.quality = StreamQuality.quality720p,
    this.visibility = StreamVisibility.public,
    this.status = StreamStatus.live,
  });

  Map<String, dynamic> toJson() {
    return {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      'quality': quality.value,
      'visibility': visibility.value,
      'status': status.value,
    };
  }
}

class LiveService extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _dio = Dio();
  
  StreamState _streamState = StreamState.idle;
  String? _errorMessage;
  LiveStreamInfo? _currentStream;
  StreamConfiguration _configuration = StreamConfiguration();
  
  StreamState get streamState => _streamState;
  String? get errorMessage => _errorMessage;
  LiveStreamInfo? get currentStream => _currentStream;
  StreamConfiguration get configuration => _configuration;
  
  bool get isLive => _streamState == StreamState.live;
  bool get canStartStream => _streamState == StreamState.idle;
  bool get canStopStream => _streamState == StreamState.live;

  void updateConfiguration(StreamConfiguration config) {
    _configuration = config;
    notifyListeners();
  }

  Future<bool> createLiveStream({StreamConfiguration? config}) async {
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

      final streamConfig = config ?? _configuration;

      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/live/create',
        data: streamConfig.toJson(),
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

    _setState(StreamState.live);
    return true;
  }

  Future<bool> stopStream() async {
    if (_streamState != StreamState.live) {
      return true;
    }

    _setState(StreamState.stopping);

    try {
      // Optionally call backend to end the broadcast
      if (_currentStream?.broadcastId != null) {
        final sessionToken = await _secureStorage.read(key: 'app_session');
        if (sessionToken != null) {
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
        }
      }

      _currentStream = null;
      _setState(StreamState.idle);
      return true;
    } catch (e) {
      _handleError('Failed to stop stream: $e');
      return false;
    }
  }

  /// Capture snapshot from camera and save to gallery
  Future<bool> captureSnapshot(CameraController cameraController) async {
    try {
      if (!cameraController.value.isInitialized) {
        _handleError('Camera not initialized');
        return false;
      }

      final XFile image = await cameraController.takePicture();
      
      // Save to gallery
      final result = await ImageGallerySaver.saveFile(image.path);
      
      if (result['isSuccess'] == true) {
        if (kDebugMode) {
          print('Snapshot saved to gallery');
        }
        return true;
      } else {
        _handleError('Failed to save snapshot to gallery');
        return false;
      }
    } catch (e) {
      _handleError('Failed to capture snapshot: $e');
      return false;
    }
  }

  /// Start recording video to save locally
  Future<bool> startVideoRecording(CameraController cameraController) async {
    try {
      if (!cameraController.value.isInitialized) {
        _handleError('Camera not initialized');
        return false;
      }

      if (cameraController.value.isRecordingVideo) {
        _handleError('Already recording video');
        return false;
      }

      await cameraController.startVideoRecording();
      
      if (kDebugMode) {
        print('Video recording started');
      }
      return true;
    } catch (e) {
      _handleError('Failed to start video recording: $e');
      return false;
    }
  }

  /// Stop recording video and save to gallery
  Future<bool> stopVideoRecording(CameraController cameraController) async {
    try {
      if (!cameraController.value.isRecordingVideo) {
        _handleError('Not recording video');
        return false;
      }

      final XFile video = await cameraController.stopVideoRecording();
      
      // Save to gallery
      final result = await ImageGallerySaver.saveFile(video.path);
      
      if (result['isSuccess'] == true) {
        if (kDebugMode) {
          print('Video saved to gallery');
        }
        
        // Clean up temporary file
        final file = File(video.path);
        if (await file.exists()) {
          await file.delete();
        }
        
        return true;
      } else {
        _handleError('Failed to save video to gallery');
        return false;
      }
    } catch (e) {
      _handleError('Failed to stop video recording: $e');
      return false;
    }
  }

  void reset() {
    _currentStream = null;
    _setState(StreamState.idle);
    _errorMessage = null;
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

  @override
  void dispose() {
    super.dispose();
  }
}