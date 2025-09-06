import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../config.dart';

class User {
  final String username;
  final String? associatedWith;
  final DateTime createdAt;
  final int activeSessions;

  User({
    required this.username,
    this.associatedWith,
    required this.createdAt,
    required this.activeSessions,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      username: json['username'],
      associatedWith: json['associated_with'],
      createdAt: DateTime.parse(json['created_at']),
      activeSessions: json['active_sessions'] ?? 0,
    );
  }

  bool get isAdmin => associatedWith == null;
}

class UserStats {
  final int totalUsers;
  final int adminUsers;
  final int regularUsers;
  final int activeSessions;
  final int usersWithYoutubeAuth;

  UserStats({
    required this.totalUsers,
    required this.adminUsers,
    required this.regularUsers,
    required this.activeSessions,
    required this.usersWithYoutubeAuth,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalUsers: int.parse(json['total_users'].toString()),
      adminUsers: int.parse(json['admin_users'].toString()),
      regularUsers: int.parse(json['regular_users'].toString()),
      activeSessions: int.parse(json['active_sessions'].toString()),
      usersWithYoutubeAuth: int.parse(json['users_with_youtube_auth'].toString()),
    );
  }
}

class UserManagementService {
  final Dio _dio = Dio();
  
  String get _baseUrl => AppConfig.backendBaseUrl;

  /// Get authorization headers with JWT token
  Map<String, String> _getAuthHeaders(String token) {
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Get all users (admin only)
  Future<List<User>> getUsers(String token) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/admin/users',
        options: Options(headers: _getAuthHeaders(token)),
      );

      if (response.statusCode == 200 && response.data['success']) {
        final List<dynamic> usersData = response.data['users'];
        return usersData.map((user) => User.fromJson(user)).toList();
      } else {
        throw Exception(response.data['error'] ?? 'Failed to fetch users');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('Admin access required');
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Failed to fetch users: $e');
    }
  }

  /// Create a new user (admin only)
  Future<bool> createUser({
    required String token,
    required String username,
    required String password,
    String? associatedWith,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/admin/users',
        options: Options(headers: _getAuthHeaders(token)),
        data: {
          'username': username,
          'password': password,
          'associatedWith': associatedWith,
        },
      );

      if (response.statusCode == 201 && response.data['success']) {
        if (kDebugMode) {
          print('User created successfully: $username');
        }
        return true;
      } else {
        throw Exception(response.data['error'] ?? 'Failed to create user');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw Exception('User already exists');
      } else if (e.response?.statusCode == 403) {
        throw Exception('Admin access required');
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  /// Update user (admin only)
  Future<bool> updateUser({
    required String token,
    required String username,
    String? password,
    String? associatedWith,
  }) async {
    try {
      final Map<String, dynamic> data = {};
      if (password != null && password.isNotEmpty) {
        data['password'] = password;
      }
      if (associatedWith != null) {
        data['associatedWith'] = associatedWith.isEmpty ? null : associatedWith;
      }

      if (data.isEmpty) {
        throw Exception('No fields to update');
      }

      final response = await _dio.put(
        '$_baseUrl/admin/users/$username',
        options: Options(headers: _getAuthHeaders(token)),
        data: data,
      );

      if (response.statusCode == 200 && response.data['success']) {
        if (kDebugMode) {
          print('User updated successfully: $username');
        }
        return true;
      } else {
        throw Exception(response.data['error'] ?? 'Failed to update user');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Exception('User not found');
      } else if (e.response?.statusCode == 403) {
        throw Exception('Admin access required');
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Failed to update user: $e');
    }
  }

  /// Delete user (admin only)
  Future<bool> deleteUser({
    required String token,
    required String username,
  }) async {
    try {
      final response = await _dio.delete(
        '$_baseUrl/admin/users/$username',
        options: Options(headers: _getAuthHeaders(token)),
      );

      if (response.statusCode == 200 && response.data['success']) {
        if (kDebugMode) {
          print('User deleted successfully: $username');
        }
        return true;
      } else {
        throw Exception(response.data['error'] ?? 'Failed to delete user');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw Exception('User not found');
      } else if (e.response?.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (e.response?.statusCode == 400) {
        throw Exception('Cannot delete your own account');
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Failed to delete user: $e');
    }
  }

  /// Get user statistics (admin only)
  Future<UserStats> getUserStats(String token) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/admin/stats',
        options: Options(headers: _getAuthHeaders(token)),
      );

      if (response.statusCode == 200 && response.data['success']) {
        return UserStats.fromJson(response.data['stats']);
      } else {
        throw Exception(response.data['error'] ?? 'Failed to fetch user statistics');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        throw Exception('Admin access required');
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      throw Exception('Failed to fetch user statistics: $e');
    }
  }
}