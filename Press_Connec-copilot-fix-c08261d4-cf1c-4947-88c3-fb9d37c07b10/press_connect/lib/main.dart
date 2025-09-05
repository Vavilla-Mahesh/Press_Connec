import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'config.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/live_service.dart';
import 'services/streaming_service.dart';
import 'services/youtube_api_service.dart';
import 'services/camera_service.dart';
import 'services/connection_service.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/youtube_connect_screen.dart';
import 'ui/screens/go_live_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Force landscape orientation for entire app
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  try {
    await AppConfig.init();
    runApp(const PressConnectApp());
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Configuration Error: $e'),
        ),
      ),
    ));
  }
}

class PressConnectApp extends StatelessWidget {
  const PressConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => LiveService()),
        ChangeNotifierProvider(create: (_) => StreamingService()),
        ChangeNotifierProvider(create: (_) => YouTubeApiService()),
        ChangeNotifierProvider(create: (_) => CameraService()),
        ChangeNotifierProvider(create: (_) => ConnectionService()),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: themeService.lightTheme,
            darkTheme: themeService.darkTheme,
            themeMode: themeService.themeMode,
            initialRoute: '/login',
            routes: {
              '/login': (context) => const LoginScreen(),
              '/youtube-connect': (context) => const YouTubeConnectScreen(),
              '/go-live': (context) => const GoLiveScreen(),
            },
          );
        },
      ),
    );
  }
}