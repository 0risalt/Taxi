import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Проверка разрешений и разовое получение позиции.
class LocationHelper {
  LocationHelper._();

  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return p != LocationPermission.denied &&
        p != LocationPermission.deniedForever;
  }

  static Future<Position?> currentPosition() async {
    try {
      if (!await ensurePermission()) return null;
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('currentPosition error: $e');
      return null;
    }
  }
}

/// Передаёт позицию водителя в таблицу driver_locations, пока он «на линии».
/// Один экземпляр на всё приложение: работает и на главном экране водителя,
/// и на экране поездки. Работает, пока приложение на экране (фоновой службы нет).
class DriverLocationService {
  final StreamController<Position> _positions =
      StreamController<Position>.broadcast();
  StreamSubscription<Position>? _sub;
  Position? _last;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  SupabaseClient get _c => Supabase.instance.client;

  bool get isRunning => _sub != null;
  Position? get last => _last;
  Stream<Position> get positions => _positions.stream;

  Future<bool> start() async {
    if (isRunning) return true;
    if (!await LocationHelper.ensurePermission()) return false;

    final first = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    _last = first;
    _positions.add(first);
    await _upsert(first, online: true);

    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((p) {
      _last = p;
      _positions.add(p);
      final now = DateTime.now();
      if (now.difference(_lastSent) >= const Duration(seconds: 4)) {
        _lastSent = now;
        _upsert(p, online: true);
      }
    }, onError: (Object e) => debugPrint('position stream error: $e'));
    return true;
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final p = _last;
    if (p != null) {
      await _upsert(p, online: false);
    }
  }

  Future<void> _upsert(Position p, {required bool online}) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _c.from('driver_locations').upsert({
        'driver_id': uid,
        'lat': p.latitude,
        'lon': p.longitude,
        'is_online': online,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('driver location upsert error: $e');
    }
  }
}

final DriverLocationService driverLocationService = DriverLocationService();
