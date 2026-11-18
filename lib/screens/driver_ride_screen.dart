import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;

import '../models/profile.dart';
import '../models/ride.dart';
import '../services/auth_service.dart';
import '../services/driver_location_service.dart';
import '../services/ride_service.dart';
import '../services/yandex_api.dart';
import '../theme/app_colors.dart';
import '../utils/format.dart';
import '../widgets/taxi_map.dart';

class DriverRideScreen extends StatefulWidget {
  const DriverRideScreen({super.key, required this.rideId});

  final String rideId;

  @override
  State<DriverRideScreen> createState() => _DriverRideScreenState();
}

class _DriverRideScreenState extends State<DriverRideScreen> {
  final _rides = RideService();
  final _auth = AuthService();
  final _api = YandexApi();
  final _map = TaxiMapController();

  StreamSubscription<Ride?>? _rideSub;
  StreamSubscription<Position>? _posSub;

  Ride? _ride;
  Profile? _client;
  RideStatus? _drawnFor;
  bool _mapReady = false;
  bool _busy = false;
  String? _error;

  ymk.PlacemarkMapObject? _carMarker;
  final List<ymk.PlacemarkMapObject> _pins = [];

  @override
  void initState() {
    super.initState();
    // Позиция должна передаваться и во время поездки.
    if (!driverLocationService.isRunning) {
      driverLocationService.start();
    }
    _posSub = driverLocationService.positions.listen(_onPosition);
    _rideSub = _rides.watchRide(widget.rideId).listen(
      _onRide,
      onError: (Object e) {
        if (mounted) setState(() => _error = 'Нет связи с сервером');
      },
    );
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------ данные

  void _onRide(Ride? ride) {
    if (ride == null || !mounted) return;
    final first = _ride == null;
    setState(() {
      _ride = ride;
      _error = null;
    });
    if (first) _loadClient(ride.clientId);
    _drawScene();
  }

  Future<void> _loadClient(String id) async {
    try {
      final p = await _auth.getProfile(id);
      if (mounted) setState(() => _client = p);
    } catch (_) {}
  }

  // ------------------------------------------------------------- карта

  void _onMapReady() {
    _mapReady = true;
    final p = driverLocationService.last;
    if (p != null) _onPosition(p);
    _drawScene();
  }

  void _onPosition(Position p) {
    if (!_mapReady) return;
    if (_carMarker == null) {
      _carMarker = _map.addCar(p.latitude, p.longitude);
    } else {
      _map.moveMarker(_carMarker, p.latitude, p.longitude);
    }
  }

  /// Перерисовываем маршрут только при смене статуса.
  Future<void> _drawScene() async {
    final ride = _ride;
    if (!_mapReady || ride == null || _drawnFor == ride.status) return;
    _drawnFor = ride.status;

    _pins
      ..forEach(_map.removeMarker)
      ..clear();
    _map.clearRoute();

    final me = driverLocationService.last;
    final pickup = LatLon(ride.fromLat, ride.fromLon);
    final dest = LatLon(ride.toLat, ride.toLon);
    final stops = [for (final w in ride.waypoints) LatLon(w.lat, w.lon)];

    List<LatLon>? path;
    switch (ride.status) {
      case RideStatus.accepted:
        _addPin(pickup);
        _map.moveTo(pickup.lat, pickup.lon, zoom: 14);
        if (me != null) {
          path = [LatLon(me.latitude, me.longitude), pickup];
        }
      case RideStatus.arrived:
        _addPin(pickup);
        _map.moveTo(pickup.lat, pickup.lon, zoom: 16);
      case RideStatus.inProgress:
        _addPin(dest);
        for (final s in stops) {
          _addPin(s);
        }
        path = [
          me != null ? LatLon(me.latitude, me.longitude) : pickup,
          ...stops,
          dest,
        ];
      default:
        break;
    }

    if (path != null) {
      final status = ride.status;
      final route = await _api.buildRoute(path);
      if (route != null && mounted && _drawnFor == status) {
        _map.setRoute(route.points);
      }
    }
  }

  void _addPin(LatLon p) {
    final m = _map.addPin(p.lat, p.lon);
    if (m != null) _pins.add(m);
  }

  // ----------------------------------------------------------- действия

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _advance() async {
    setState(() => _busy = true);
    try {
      await _rides.advanceRide(widget.rideId);
    } catch (e) {
      _snack('Не удалось сменить статус. Возможно, заказ отменён.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _release() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отказаться от заказа?'),
        content: const Text('Заказ вернётся в поиск другим водителям.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Нет')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Отказаться',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _rides.releaseRide(widget.rideId);
      if (mounted) context.go('/');
    } catch (e) {
      _snack('Не удалось отказаться от заказа');
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            TaxiMap(controller: _map, onReady: _onMapReady),
            Align(alignment: Alignment.bottomCenter, child: _buildPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel() {
    final bottom = MediaQuery.of(context).padding.bottom;
    final ride = _ride;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
      ),
      child: ride == null
          ? Center(
              heightFactor: 1,
              child: _error != null
                  ? Text(_error!,
                      style: const TextStyle(color: Colors.redAccent))
                  : const CircularProgressIndicator(
                      color: AppColors.primary),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title(ride.status),
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_client != null) _clientCard(_client!),
                _addressRow(Icons.my_location, ride.fromAddress),
                for (final w in ride.waypoints)
                  _addressRow(Icons.add_location_alt, w.address),
                _addressRow(Icons.location_on, ride.toAddress),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(formatPrice(ride.price),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    Text(
                        '${formatDistance(ride.distanceM.toDouble())} · '
                        '${formatDuration(ride.durationS.toDouble())}',
                        style: const TextStyle(color: Colors.grey)),
                    const Spacer(),
                    Chip(
                      avatar: Icon(
                          ride.isCard ? Icons.credit_card : Icons.payments,
                          size: 16,
                          color: AppColors.primaryDark),
                      label: Text(ride.paymentLabel),
                      backgroundColor: AppColors.background,
                      side: BorderSide(color: Colors.pink.shade100),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._actions(ride),
              ],
            ),
    );
  }

  String _title(RideStatus s) {
    switch (s) {
      case RideStatus.accepted:
        return 'Поезжайте к клиенту';
      case RideStatus.arrived:
        return 'Ожидайте клиента';
      case RideStatus.inProgress:
        return 'Поездка идёт';
      case RideStatus.completed:
        return 'Поездка завершена';
      case RideStatus.cancelledByClient:
        return 'Клиент отменил заказ';
      case RideStatus.cancelledByDriver:
        return 'Заказ отменён';
      case RideStatus.searching:
        return 'Заказ возвращён в поиск';
    }
  }

  Widget _clientCard(Profile c) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.pink.shade100),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.primary,
            child: Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.fullName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                if (c.phone.isNotEmpty)
                  SelectableText(c.phone,
                      style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _addressRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14)),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label),
      ),
    );
  }

  List<Widget> _actions(Ride ride) {
    switch (ride.status) {
      case RideStatus.accepted:
        return [
          _primaryButton('Я на месте', _busy ? null : _advance),
          TextButton(
            onPressed: _busy ? null : _release,
            child: const Text('Отказаться от заказа',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ];
      case RideStatus.arrived:
        return [
          _primaryButton('Начать поездку', _busy ? null : _advance),
          TextButton(
            onPressed: _busy ? null : _release,
            child: const Text('Отказаться от заказа',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ];
      case RideStatus.inProgress:
        return [_primaryButton('Завершить поездку', _busy ? null : _advance)];
      case RideStatus.completed:
        return [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              ride.isCard
                  ? 'Оплата картой: ${ride.isPaid ? "получена" : "ожидает клиента"}'
                  : 'Получите с клиента ${formatPrice(ride.price)} наличными',
              style: const TextStyle(color: Colors.black54),
            ),
          ),
          _primaryButton('К заказам', () => context.go('/')),
        ];
      case RideStatus.cancelledByClient:
      case RideStatus.cancelledByDriver:
      case RideStatus.searching:
        return [_primaryButton('К заказам', () => context.go('/'))];
    }
  }
}
