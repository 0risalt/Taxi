import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../models/profile.dart';

/// Ошибка входа/регистрации с текстом для пользователя.
class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Локальные аккаунты: email + пароль, хранятся в SQLite на этом устройстве.
/// Один экземпляр на приложение; уведомляет роутер о входе и выходе.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;

  final AppDatabase _db = AppDatabase.instance;
  String? _currentUserId;

  String? get currentUserId => _currentUserId;
  bool get isLoggedIn => _currentUserId != null;

  /// Восстанавливает вход после перезапуска приложения. Вызывать в main().
  Future<void> init() async {
    final db = await _db.database;
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: ['current_user_id'], limit: 1);
    if (rows.isEmpty) return;
    final id = rows.first['value'] as String?;
    if (id == null) return;
    final exists = await db.query('users',
        columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (exists.isNotEmpty) _currentUserId = id;
  }

  Future<Profile> signUp({
    required String email,
    required String password,
    required String role,
    required String fullName,
    required String phone,
    String? carModel,
    String? carPlate,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (!normalized.contains('@')) {
      throw AuthFailure('Введите корректный email');
    }
    if (password.length < 6) {
      throw AuthFailure('Пароль должен быть не короче 6 символов');
    }
    if (role != 'client' && role != 'driver') {
      throw AuthFailure('Неизвестная роль');
    }

    final db = await _db.database;
    final id = newId();
    final salt = newId();
    try {
      await db.insert('users', {
        'id': id,
        'email': normalized,
        'password_hash': _hash(password, salt),
        'salt': salt,
        'role': role,
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'car_model': role == 'driver' ? carModel?.trim() : null,
        'car_plate': role == 'driver' ? carPlate?.trim() : null,
        'created_at': nowIso(),
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw AuthFailure('Аккаунт с таким email уже существует');
      }
      rethrow;
    }

    await _setSession(id);
    return (await getProfile(id))!;
  }

  Future<void> signIn(String email, String password) async {
    final db = await _db.database;
    final rows = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    if (rows.isEmpty) throw AuthFailure('Неверный email или пароль');

    final user = rows.first;
    final expected = user['password_hash'] as String;
    final actual = _hash(password, user['salt'] as String);
    if (actual != expected) throw AuthFailure('Неверный email или пароль');

    await _setSession(user['id'] as String);
  }

  Future<void> signOut() async {
    final db = await _db.database;
    await db.delete('settings', where: 'key = ?', whereArgs: ['current_user_id']);
    _currentUserId = null;
    notifyListeners();
  }

  Future<Profile?> loadMyProfile() async {
    final id = _currentUserId;
    if (id == null) return null;
    return getProfile(id);
  }

  Future<Profile?> getProfile(String id) async {
    final db = await _db.database;
    final rows = await db.query('users',
        columns: ['id', 'role', 'full_name', 'phone', 'car_model', 'car_plate'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1);
    return rows.isEmpty ? null : Profile.fromMap(rows.first);
  }

  Future<void> _setSession(String userId) async {
    final db = await _db.database;
    await db.insert(
      'settings',
      {'key': 'current_user_id', 'value': userId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _currentUserId = userId;
    notifyListeners();
  }

  /// Хеш пароля: SHA-256 с солью и 5000 повторений. Данные хранятся только
  /// на этом телефоне, этого достаточно для разделения аккаунтов.
  String _hash(String password, String salt) {
    final saltBytes = utf8.encode(salt);
    var digest = sha256.convert([...saltBytes, ...utf8.encode(password)]).bytes;
    for (var i = 0; i < 5000; i++) {
      digest = sha256.convert([...digest, ...saltBytes]).bytes;
    }
    return base64Encode(digest);
  }
}
