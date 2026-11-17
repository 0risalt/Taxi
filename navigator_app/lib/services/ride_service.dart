import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ride.dart';

/// Все изменения статуса заказа идут через SQL-функции (RPC): они проверяют
/// роль и допустимость перехода на сервере, прямых UPDATE у клиентов нет.
class RideService {
  SupabaseClient get _c => Supabase.instance.client;

  static const _activeForClient = [
    'searching',
    'accepted',
    'arrived',
    'in_progress',
  ];
  static const _activeForDriver = ['accepted', 'arrived', 'in_progress'];

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
    final m = await _c
        .from('rides')
        .insert({
          'from_address': fromAddress,
          'from_lat': fromLat,
          'from_lon': fromLon,
          'to_address': toAddress,
          'to_lat': toLat,
          'to_lon': toLon,
          'waypoints': waypoints.map((e) => e.toJson()).toList(),
          'distance_m': distanceM,
          'duration_s': durationS,
          'payment_method': paymentMethod,
        })
        .select()
        .single();
    return Ride.fromMap(m);
  }

  Future<void> cancelRide(String id) async {
    await _c.rpc('cancel_ride', params: {'p_ride_id': id});
  }

  /// Тестовая оплата: отмечает заказ оплаченным (см. PaymentService).
  Future<void> markPaid(String id) async {
    await _c.rpc('mark_ride_paid', params: {'p_ride_id': id});
  }

  // ---------------------------------------------------------- водитель

  /// true — заказ достался этому водителю, false — уже занят.
  Future<bool> acceptRide(String id) async {
    final res = await _c.rpc('accept_ride', params: {'p_ride_id': id});
    return res == true;
  }

  Future<void> advanceRide(String id) async {
    await _c.rpc('advance_ride', params: {'p_ride_id': id});
  }

  Future<void> releaseRide(String id) async {
    await _c.rpc('release_ride', params: {'p_ride_id': id});
  }

  // ------------------------------------------------------------ общее

  Future<Ride?> getActiveRide({required bool asDriver}) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return null;
    final m = await _c
        .from('rides')
        .select()
        .eq(asDriver ? 'driver_id' : 'client_id', uid)
        .inFilter('status', asDriver ? _activeForDriver : _activeForClient)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return m == null ? null : Ride.fromMap(m);
  }

  Stream<Ride?> watchRide(String id) {
    return _c
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) => rows.isEmpty ? null : Ride.fromMap(rows.first));
  }

  /// Открытые заказы для водителей. Фильтр по статусу делаем на клиенте:
  /// Realtime не присылает событие, когда строка перестаёт подходить под
  /// серверный фильтр (например, заказ взял другой водитель).
  Stream<List<Ride>> watchOpenRides() {
    return _c
        .from('rides')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(50)
        .map((rows) {
      final now = DateTime.now();
      return rows
          .map(Ride.fromMap)
          .where((r) =>
              r.status == RideStatus.searching &&
              now.difference(r.createdAt) < const Duration(minutes: 10))
          .toList();
    });
  }

  Stream<DriverLocation?> watchDriverLocation(String driverId) {
    return _c
        .from('driver_locations')
        .stream(primaryKey: ['driver_id'])
        .eq('driver_id', driverId)
        .map((rows) => rows.isEmpty ? null : DriverLocation.fromMap(rows.first));
  }
}
