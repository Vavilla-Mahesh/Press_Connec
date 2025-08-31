import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:dio/dio.dart';
import '../config.dart';

enum AuthState {
  initial,
  appAuthenticated,
  youtubeAuthenticated,
  loading,
  error
}

class AuthService extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _dio = Dio();
  
  AuthState _authState = AuthState.initial;
  String? _errorMessage;
  GoogleSignInAccount? _googleUser;
  
  AuthState get authState => _authState;
  String? get errorMessage => _errorMessage;
  GoogleSignInAccount? get googleUser => _googleUser;
  bool get isAppAuthenticated => _authState == AuthState.appAuthenticated || 
                                 _authState == AuthState.youtubeAuthenticated;
  bool get isYouTubeAuthenticated => _authState == AuthState.youtubeAuthenticated;

  GoogleSignIn? _googleSignIn;

  AuthService() {
    _initializeGoogleSignIn();
    _checkAuthState();
  }

  void _initializeGoogleSignIn() {
    _googleSignIn = GoogleSignIn(
      clientId: AppConfig.googleClientId,
      scopes: AppConfig.youtubeScopes,
    );
  }

  Future<void> _checkAuthState() async {
    try {
      final appAuth = await _secureStorage.read(key: 'app_authenticated');
      final youtubeAuth = await _secureStorage.read(key: 'youtube_authenticated');
      
      if (youtubeAuth == 'true') {
        _authState = AuthState.youtubeAuthenticated;
      } else if (appAuth == 'true') {
        _authState = AuthState.appAuthenticated;
      } else {
        _authState = AuthState.initial;
      }
      notifyListeners();
    } catch (e) {
      _handleError('Failed to check authentication state: $e');
    }
  }

  Future<bool> loginWithCredentials(String username, String password) async {
    _setLoading();
    
    try {
      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/auth/app-login',
        data: {
          'username': username,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        await _secureStorage.write(key: 'app_authenticated', value: 'true');
        await _secureStorage.write(key: 'app_session', value: response.data['token'] ?? '');
        
        _authState = AuthState.appAuthenticated;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _handleError('Invalid credentials');
        return false;
      }
    } catch (e) {
      _handleError('Login failed: $e');
      return false;
    }
  }

  Future<bool> connectYouTube() async {
    if (_googleSignIn == null) {
      _handleError('Google Sign In not initialized');
      return false;
    }

    _setLoading();

    try {
      // Sign out first to ensure fresh authentication
      await _googleSignIn!.signOut();
      
      final GoogleSignInAccount? account = await _googleSignIn!.signIn();
      if (account == null) {
        _handleError('YouTube authentication cancelled');
        return false;
      }
      // Use the serverAuthCode from the account object (not from auth)
      final String? serverAuthCode = account.serverAuthCode;
      if (serverAuthCode == null) {
        _handleError('Failed to get server auth code');
        return false;
      }

      // Exchange server auth code with backend
      final response = await _dio.post(
        '${AppConfig.backendBaseUrl}/auth/exchange',
        data: {
          'serverAuthCode': serverAuthCode,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${await _secureStorage.read(key: 'app_session')}',
          },
        ),
      );

      if (response.statusCode == 200) {
        await _secureStorage.write(key: 'youtube_authenticated', value: 'true');
        _googleUser = account;
        _authState = AuthState.youtubeAuthenticated;
        _errorMessage = null;
        notifyListeners();
        return true;
      } else {
        _handleError('Failed to exchange YouTube authentication');
        return false;
      }
    } catch (e) {
      _handleError('YouTube authentication failed: $e');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _googleSignIn?.signOut();
      await _secureStorage.deleteAll();
      
      _googleUser = null;
      _authState = AuthState.initial;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _handleError('Logout failed: $e');
    }
  }

  void _setLoading() {
    _authState = AuthState.loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _handleError(String error) {
    _authState = AuthState.error;
    _errorMessage = error;
    notifyListeners();
    
    if (kDebugMode) {
      print('AuthService Error: $error');
    }
  }

  void clearError() {
    if (_authState == AuthState.error) {
      _authState = AuthState.initial;
      _errorMessage = null;
      notifyListeners();
    }
  }
}