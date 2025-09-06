import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'youtube_connect_screen.dart';
import 'go_live_screen.dart';

class NavigationWrapper extends StatelessWidget {
  const NavigationWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        switch (authService.authState) {
          case AuthState.initial:
          case AuthState.error:
            return const LoginScreen();
          
          case AuthState.loading:
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          
          case AuthState.appAuthenticated:
            // Admin needs YouTube authentication, users go straight to go live
            if (authService.isAdmin) {
              return const YouTubeConnectScreen();
            } else {
              return const GoLiveScreen();
            }
          
          case AuthState.youtubeAuthenticated:
            return const GoLiveScreen();
        }
      },
    );
  }
}