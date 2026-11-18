import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../config.dart';
import '../data/app_database.dart';
import '../models/ride.dart';
import 'auth_service.dart';

class RideException implements Exception {
  RideException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// У пользователя уже есть активный заказ.
class ActiveRideExistsException extends RideException {
  ActiveRideExistsException() : super('У вас уже есть активный заказ');
}

/// Заказы такси в локальной базе. Каждое изменение статуса — одна атомарная
/// операция UPDATE с проверкой роли и допустимого перехода.
class RideService {
  final AppDatabase _db = AppDatabase.instance;

  static const _clientActive =
      "('searching', 'accepted', 'arrived', 'in_progress')";
  static const _driverActive = "('accepted', 'arrived', 'in_progress')";

  String _uid() {
    final id = AuthService().currentUserId;
    if (id == null) throw RideException('Войдите в аккаунт');
    return id;
  }

  Future<void> _requireRole(String uid, String role, String message) async {
    final db = await _db.database;
    final rows = await db.query('users',
        columns: ['role'], where: 'id = ?', whereArgs: [uid], limit: 1);
    if (rows.isEmpty || rows.first['role'] != role) {
      throw RideException(message);
    }
  }

  // ----------------------------------------------------------- клиент

  Future<Ride> createRide({
    required String fromAddress,
    required double fromLat,
    required double fromLon,
    required String toAddress,
    required double toLat,
    required double toLon,
    required List<RideStop> waypoints,
    required int distanceM,
    required int durationS,
    required String paymentMethod,
  }) async {
    final uid = _uid();
    await _requireRole(uid, 'client', 'Заказывать такси могут только пассажиры');

    final db = await _db.database;
    final id = newId();
    try {
      await db.insert('rides', {
        'id': id,
        'client_id': uid,
        'status': 'searching',
        'from_address': fromAddress,
        'from_lat': fromLat,
        'from_lon': fromLon,
        'to_address': toAddress,
        'to_lat': toLat,
        'to_lon': toLon,
        'waypoints': jsonEncode(waypoints.map((e) => e.toJson()).toList()),
        'distance_m': distanceM,
        'duration_s': durationS,
        'price': Tariff.estimate(distanceM, durationS),
        'payment_method': paymentMethod,
        'payment_status': 'pending',
        'created_at': nowIso(),
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw ActiveRideExistsException();
      rethrow;
    }
    _db.notifyChanged('rides');
    return (await _getRide(id))!;
  }

  Future<void> cancelRide(String id) async {
    final db = await _db.database;
    final n = await db.rawUpdate(
      '''
      UPDATE rides SET status = 'cancelled_by_client'
      WHERE id = ? AND client_id = ?
        AND status IN ('searching', 'accepted', 'arrived')
      ''',
      [id, _uid()],
    );
    if (n != 1) throw RideException('Заказ уже нельзя отменить');
    _db.notifyChanged('rides');
  }

  /// Тестовая оплата: отмечает заказ оплаченным (см. PaymentService).
  Future<void> markPaid(String id) async {
    final db = await _db.database;
    await db.rawUpdate(
      '''
      UPDATE rides SET payment_status = 'paid'
      WHERE id = ? AND client_id = ? AND status = 'completed'
        AND payment_method = 'card'
      ''',
      [id, _uid()],
    );
    _db.notifyChanged('rides');
  }

  // ---------------------------------------------------------- водитель

  /// true — заказ достался этому водителю, false — уже занят.
  Future<bool> acceptRide(String id) async {
    final uid = _uid();
    await _requireRole(uid, 'driver', 'Принимать заказы могут только водители');

    final db = await _db.database;
    var n = 0;
    try {
      n = await db.rawUpdate(
        '''
        UPDATE rides SET driver_id = ?, status = 'accepted', accepted_at = ?
        WHERE id = ? AND status = 'searching' AND driver_id IS NULL
        ''',
        [uid, nowIso(), id],
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw ActiveRideExistsException();
      rethrow;
    }
    if (n == 1) _db.notifyChanged('rides');
    return n == 1;
  }

  /// accepted -> arrived -> in_progress -> completed.
  /// Наличные считаются оплаченными в момент завершения поездки.
  Future<void> advanceRide(String id) async {
    final db = await _db.database;
    final now = nowIso();
    final n = await db.rawUpdate(
      '''
      UPDATE rides SET
        status = CASE status
                   WHEN 'accepted'    THEN 'arrived'
                   WHEN 'arrived'     THEN 'in_progress'
                   WHEN 'in_progress' THEN 'completed'
                 END,
        started_at   = CASE WHEN status = 'arrived' THEN ? ELSE started_at END,
        completed_at = CASE WHEN status = 'in_progress' THEN ? ELSE completed_at END,
        payment_status = CASE
                           WHEN status = 'in_progress' AND payment_method = 'cash'
                             THEN 'paid'
                           ELSE payment_status
                         END
      WHERE id = ? AND driver_id = ?
        AND status IN ('accepted', 'arrived', 'in_progress')
      ''',
      [now, now, id, _uid()],
    );
    if (n != 1) throw RideException('Статус заказа изменить нельзя');
    _db.notifyChanged('rides');
  }

  /// Водитель отказывается: заказ возвращается в поиск.
  Future<void> releaseRide(String id) async {
    final db = await _db.database;
    final n = await db.rawUpdate(
      '''
      UPDATE rides SET driver_id = NULL, status = 'searching', accepted_at = NULL
      WHERE id = ? AND driver_id = ? AND status IN ('accepted', 'arrived')
      ''',
      [id, _uid()],
    );
    if (n != 1) throw RideException('От заказа уже нельзя отказаться');
    _db.notifyChanged('rides');
  }

  // ------------------------------------------------------------ общее

  Future<Ride?> _getRide(String id) async {
    final db = await _db.database;
    final rows =
        await db.query('rides', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Ride.fromMap(rows.first);
  }

  Future<Ride?> getActiveRide({required bool asDriver}) async {
    final uid = AuthService().currentUserId;
    if (uid == null) return null;
    final db = await _db.database;
    final column = asDriver ? 'driver_id' : 'client_id';
    final statuses = asDriver ? _driverActive : _clientActive;
    final rows = await db.rawQuery(
      'SELECT * FROM rides WHERE $column = ? AND status IN $statuses '
      'ORDER BY created_at DESC LIMIT 1',
      [uid],
    );
    return rows.isEmpty ? null : Ride.fromMap(rows.first);
  }

  Stream<Ride?> watchRide(String id) =>
      watchQuery<Ride?>(() => _getRide(id), tables: {'rides'});

  /// Свободные заказы для водителей (поиск не старше 10 минут).
  Stream<List<Ride>> watchOpenRides() {
    return watchQuery<List<Ride>>(
      () async {
        final db = await _db.database;
        final cutoff = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 10))
            .toIso8601String();
        final rows = await db.rawQuery(
          "SELECT * FROM rides WHERE status = 'searching' AND created_at > ? "
          'ORDER BY created_at DESC LIMIT 50',
          [cutoff],
        );
        return rows.map(Ride.fromMap).toList();
      },
      tables: {'rides'},
      // Заказы «стареют» сами по себе — обновляем список по таймеру.
      refreshEvery: const Duration(seconds: 15),
    );
  }

  Stream<DriverLocation?> watchDriverLocation(String driverId) {
    return watchQuery<DriverLocation?>(
      () async {
        final db = await _db.database;
        final rows = await db.query('driver_locations',
            where: 'driver_id = ?', whereArgs: [driverId], limit: 1);
        return rows.isEmpty ? null : DriverLocation.fromMap(rows.first);
      },
      tables: {'driver_locations'},
    );
  }
}
