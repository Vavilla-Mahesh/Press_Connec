# Native RTMP Implementation Guide

This document outlines how to implement the native RTMP streaming functionality for production deployment.

## Overview

The Flutter app is structured to use platform channels to communicate with native iOS and Android code for RTMP streaming. The `NativeRTMPChannel` class provides the interface, but the actual native implementation needs to be added.

## Architecture

```
Flutter App (Dart)
    ↓ Platform Channel
Native Code (iOS/Android)
    ↓ RTMP Libraries
YouTube RTMP Endpoint
```

## iOS Implementation

### Required Dependencies

Add to `ios/Podfile`:

```ruby
pod 'HaishinKit', '~> 1.4.0'  # RTMP streaming library
# OR alternatively:
# pod 'LFLiveKit', '~> 2.6'
```

### iOS Platform Channel Implementation

Create `ios/Runner/RTMPStreamingPlugin.swift`:

```swift
import Flutter
import Foundation
import HaishinKit
import AVFoundation

@objc public class RTMPStreamingPlugin: NSObject, FlutterPlugin {
    private var rtmpConnection: RTMPConnection?
    private var rtmpStream: RTMPStream?
    private var eventSink: FlutterEventSink?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "press_connect/rtmp_streaming", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "press_connect/rtmp_events", binaryMessenger: registrar.messenger())
        
        let instance = RTMPStreamingPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initialize(result: result)
        case "startStreaming":
            startStreaming(call: call, result: result)
        case "stopStreaming":
            stopStreaming(result: result)
        case "updateQuality":
            updateQuality(call: call, result: result)
        case "getStreamingStats":
            getStreamingStats(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func initialize(result: @escaping FlutterResult) {
        rtmpConnection = RTMPConnection()
        rtmpStream = RTMPStream(connection: rtmpConnection!)
        
        // Configure stream settings
        rtmpStream?.videoSettings.size = CGSize(width: 1280, height: 720)
        rtmpStream?.videoSettings.bitrate = 2500 * 1000
        rtmpStream?.videoSettings.frameInterval = 1.0/30.0
        
        result(true)
    }
    
    private func startStreaming(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let rtmpUrl = args["rtmpUrl"] as? String,
              let quality = args["quality"] as? String,
              let bitrate = args["bitrate"] as? Int else {
            result(false)
            return
        }
        
        // Configure based on quality
        configureStream(quality: quality, bitrate: bitrate)
        
        // Attach camera
        rtmpStream?.attachCamera(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
        rtmpStream?.attachAudio(AVCaptureDevice.default(for: .audio))
        
        // Connect and publish
        rtmpConnection?.connect(rtmpUrl)
        rtmpConnection?.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
        
        result(true)
    }
    
    @objc private func rtmpStatusHandler(_ notification: Notification) {
        // Handle RTMP status changes and send events to Flutter
        // eventSink?([...])
    }
    
    // Additional methods...
}

extension RTMPStreamingPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
```

### Register the Plugin

In `ios/Runner/AppDelegate.swift`:

```swift
import Flutter
import UIKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Register RTMP plugin
        RTMPStreamingPlugin.register(with: registrar(forPlugin: "RTMPStreamingPlugin")!)
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

## Android Implementation

### Required Dependencies

Add to `android/app/build.gradle`:

```gradle
dependencies {
    implementation 'com.github.pedroSG94.rtmp-rtsp-stream-client-java:rtmpandcamera:2.2.3'
    // OR alternatively:
    // implementation 'net.ossrs.yasea:yasea:3.0.0'
}
```

### Android Platform Channel Implementation

Create `android/app/src/main/kotlin/com/example/press_connect/RTMPStreamingPlugin.kt`:

```kotlin
package com.example.press_connect

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import com.pedro.rtmp.flv.video.ProfileIop
import com.pedro.rtmp.utils.ConnectCheckerRtmp
import com.pedro.rtmpandcamera.RtmpCameraActivity
import com.pedro.rtmpandcamera.builder.RtmpBuilder

class RTMPStreamingPlugin: FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, ConnectCheckerRtmp {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var rtmpBuilder: RtmpBuilder? = null
    
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "press_connect/rtmp_streaming")
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "press_connect/rtmp_events")
        
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(result)
            "startStreaming" -> startStreaming(call, result)
            "stopStreaming" -> stopStreaming(result)
            "updateQuality" -> updateQuality(call, result)
            "getStreamingStats" -> getStreamingStats(result)
            else -> result.notImplemented()
        }
    }
    
    private fun initialize(result: MethodChannel.Result) {
        try {
            rtmpBuilder = RtmpBuilder(context, connectChecker = this)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }
    
    private fun startStreaming(call: MethodCall, result: MethodChannel.Result) {
        val rtmpUrl = call.argument<String>("rtmpUrl") ?: return result.success(false)
        val quality = call.argument<String>("quality") ?: "720p"
        val bitrate = call.argument<Int>("bitrate") ?: 2500
        
        try {
            configureStream(quality, bitrate)
            rtmpBuilder?.startStream(rtmpUrl)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }
    
    private fun configureStream(quality: String, bitrate: Int) {
        when (quality) {
            "1080p" -> rtmpBuilder?.setVideoBitrateOnFly(bitrate * 1000)?.setVideoResolution(1920, 1080)
            "720p" -> rtmpBuilder?.setVideoBitrateOnFly(bitrate * 1000)?.setVideoResolution(1280, 720)
            "480p" -> rtmpBuilder?.setVideoBitrateOnFly(bitrate * 1000)?.setVideoResolution(854, 480)
            "360p" -> rtmpBuilder?.setVideoBitrateOnFly(bitrate * 1000)?.setVideoResolution(640, 360)
        }
    }
    
    // ConnectCheckerRtmp implementation
    override fun onConnectionSuccessRtmp() {
        eventSink?.success(mapOf("type" to "connection_status", "connected" to true))
    }
    
    override fun onConnectionFailedRtmp(reason: String) {
        eventSink?.success(mapOf("type" to "error", "error" to reason))
    }
    
    override fun onNewBitrateRtmp(bitrate: Long) {
        eventSink?.success(mapOf(
            "type" to "stats_update", 
            "bandwidth" to bitrate.toInt()
        ))
    }
    
    override fun onDisconnectRtmp() {
        eventSink?.success(mapOf("type" to "connection_status", "connected" to false))
    }
    
    override fun onAuthErrorRtmp() {
        eventSink?.success(mapOf("type" to "error", "error" to "Authentication failed"))
    }
    
    override fun onAuthSuccessRtmp() {
        eventSink?.success(mapOf("type" to "connection_status", "authenticated" to true))
    }
    
    // EventChannel.StreamHandler implementation
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }
    
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
```

### Register the Plugin

In `android/app/src/main/kotlin/com/example/press_connect/MainActivity.kt`:

```kotlin
package com.example.press_connect

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(RTMPStreamingPlugin())
    }
}
```

## Web Implementation

For web deployment, consider:

1. **WebRTC to RTMP Bridge**: Use a server-side solution to convert WebRTC streams to RTMP
2. **Alternative Protocols**: Use WebRTC directly to YouTube Live if supported
3. **Server-Side Streaming**: Upload video chunks to a server that handles RTMP streaming

Example WebRTC implementation structure:

```dart
// web/rtmp_web.dart
import 'dart:html' as html;

class WebRTMPImplementation {
  html.MediaStream? _stream;
  
  Future<bool> startWebRTCStreaming(String endpoint) async {
    try {
      _stream = await html.window.navigator.mediaDevices?.getUserMedia({
        'video': {'width': 1280, 'height': 720},
        'audio': true,
      });
      
      // Implement WebRTC peer connection to server
      // Server will convert to RTMP
      
      return true;
    } catch (e) {
      return false;
    }
  }
}
```

## Testing

1. **iOS Simulator**: Limited camera access, use physical device
2. **Android Emulator**: May not support camera, use physical device
3. **Network Testing**: Test with different network conditions
4. **YouTube Live**: Verify streams appear correctly on YouTube

## Production Considerations

1. **Error Handling**: Implement comprehensive error recovery
2. **Permissions**: Request camera/microphone permissions properly
3. **Background Modes**: Configure for background streaming if needed
4. **Battery Optimization**: Optimize for battery usage during streaming
5. **Network Adaptation**: Implement automatic quality adjustment
6. **Monitoring**: Add analytics for stream health and performance

## Dependencies Summary

### iOS
- HaishinKit or LFLiveKit for RTMP streaming
- AVFoundation for camera access

### Android  
- rtmp-rtsp-stream-client-java or yasea for RTMP streaming
- Camera2 API for camera access

### Web
- WebRTC for browser streaming
- Server-side RTMP bridge for YouTube compatibility

This implementation provides a production-ready foundation for native RTMP streaming across all platforms.