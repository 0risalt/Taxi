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
import '../theme/app_colors.dart';
import '../utils/format.dart';
import '../utils/geo.dart';
import '../widgets/taxi_map.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  static const double _sheetHeight = 340;

  final _rides = RideService();
  final _auth = AuthService();
  final _map = TaxiMapController();

  StreamSubscription<List<Ride>>? _ordersSub;
  StreamSubscription<Position>? _posSub;

  bool _online = driverLocationService.isRunning;
  bool _starting = false;
  bool _mapReady = false;
  bool _centered = false;
  String? _busyRideId;
  List<Ride> _orders = [];
  Position? _position;
  ymk.PlacemarkMapObject? _carMarker;

  @override
  void initState() {
    super.initState();
    _position = driverLocationService.last;
    _posSub = driverLocationService.positions.listen(_onPosition);
    if (_online) _listenOrders();
    _restoreActiveRide();
    _centerOnMe();
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------ позиция

  Future<void> _centerOnMe() async {
    if (_position == null) {
      final p = await LocationHelper.currentPosition();
      if (p == null || !mounted) return;
      _position = p;
    }
    _updateCar();
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    setState(() => _position = p); // пересчитать расстояния до заказов
    _updateCar();
  }

  void _updateCar() {
    final p = _position;
    if (p == null || !_mapReady) return;
    if (_carMarker == null) {
      _carMarker = _map.addCar(p.latitude, p.longitude);
    } else {
      _map.moveMarker(_carMarker, p.latitude, p.longitude);
    }
    if (!_centered) {
      _centered = true;
      _map.moveTo(p.latitude, p.longitude, zoom: 15);
    }
  }

  // ------------------------------------------------------------- заказы

  Future<void> _restoreActiveRide() async {
    try {
      final r = await _rides.getActiveRide(asDriver: true);
      if (r != null && mounted) context.go('/driver/ride/${r.id}');
    } catch (e) {
      debugPrint('restore driver ride error: $e');
    }
  }

  void _listenOrders() {
    _ordersSub?.cancel();
    _ordersSub = _rides.watchOpenRides().listen(
      (list) {
        if (mounted) setState(() => _orders = list);
      },
      onError: (Object e) => debugPrint('orders stream error: $e'),
    );
  }

  Future<void> _toggleOnline(bool value) async {
    if (value) {
      setState(() => _starting = true);
      bool ok = false;
      try {
        ok = await driverLocationService.start();
      } catch (e) {
        debugPrint('start location error: $e');
      }
      if (!mounted) return;
      setState(() => _starting = false);
      if (!ok) {
        _snack('Нет доступа к геопозиции. Включите её и разрешите доступ.');
        return;
      }
      setState(() => _online = true);
      _listenOrders();
    } else {
      await driverLocationService.stop();
      _ordersSub?.cancel();
      if (!mounted) return;
      setState(() {
        _online = false;
        _orders = [];
      });
    }
  }

  Future<void> _accept(Ride ride) async {
    setState(() => _busyRideId = ride.id);
    try {
      final ok = await _rides.acceptRide(ride.id);
      if (!mounted) return;
      if (ok) {
        context.go('/driver/ride/${ride.id}');
      } else {
        _snack('Заказ уже занят другим водителем');
      }
    } on ActiveRideExistsException {
      _snack('У вас уже есть активный заказ');
    } on RideException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Не удалось принять заказ');
    } finally {
      if (mounted) setState(() => _busyRideId = null);
    }
  }

  Future<void> _logout() async {
    await driverLocationService.stop();
    await _auth.signOut();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  double? _distanceToPickup(Ride r) {
    final p = _position;
    if (p == null) return null;
    return haversineMeters(p.latitude, p.longitude, r.fromLat, r.fromLon);
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sheetHeight = _sheetHeight + media.padding.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          TaxiMap(
            controller: _map,
            onReady: () {
              _mapReady = true;
              _updateCar();
            },
          ),
          Positioned(
            top: media.padding.top + 10,
            left: 16,
            right: 16,
            child: _buildTopCard(),
          ),
          Positioned(
            right: 16,
            bottom: sheetHeight,
            child: FloatingActionButton(
              heroTag: 'driverMyLocation',
              mini: true,
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
              onPressed: () {
                final p = _position;
                if (p != null) _map.moveTo(p.latitude, p.longitude);
                else _centerOnMe();
              },
              child: const Icon(Icons.my_location),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildSheet(sheetHeight, media.padding.bottom),
          ),
        ],
      ),
    );
  }

  Widget _buildTopCard() {
    final p = widget.profile;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
              color: Colors.pink.withValues(alpha: 0.2), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle,
                color: AppColors.primary, size: 32),
            onSelected: (v) {
              if (v == 'logout') _logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Выйти')),
            ],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.fullName.isEmpty ? 'Водитель' : p.fullName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text(
                  _online ? 'На линии' : 'Не на линии',
                  style: TextStyle(
                      color: _online ? Colors.green : Colors.grey,
                      fontSize: 13),
                ),
              ],
            ),
          ),
          if (_starting)
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            Switch(
              value: _online,
              activeColor: AppColors.primary,
              onChanged: _toggleOnline,
            ),
        ],
      ),
    );
  }

  Widget _buildSheet(double height, double bottomInset) {
    final sorted = [..._orders]..sort((a, b) =>
        (_distanceToPickup(a) ?? 0).compareTo(_distanceToPickup(b) ?? 0));

    Widget body;
    if (!_online) {
      body = _hint(Icons.power_settings_new,
          'Вы не на линии', 'Включите переключатель, чтобы получать заказы');
    } else if (sorted.isEmpty) {
      body = _hint(Icons.hourglass_empty, 'Ждём заказы…',
          'Новые заказы появятся здесь автоматически');
    } else {
      body = ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: sorted.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _orderCard(sorted[i]),
      );
    }

    return Container(
      height: height,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _online && sorted.isNotEmpty
                ? 'Доступные заказы (${sorted.length})'
                : 'Заказы',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _hint(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _orderCard(Ride r) {
    final toPickup = _distanceToPickup(r);
    final busy = _busyRideId == r.id;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.pink.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(formatPrice(r.price),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Icon(r.isCard ? Icons.credit_card : Icons.payments,
                  size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 4),
              Text(r.paymentLabel,
                  style: const TextStyle(color: Colors.black54)),
              const Spacer(),
              Text(formatDistance(r.distanceM.toDouble()),
                  style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          if (toPickup != null)
            Text('До клиента ~${formatDistance(toPickup)} по прямой',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.my_location, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
                child: Text(r.fromAddress,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.location_on, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
                child: Text(r.toAddress,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: busy ? null : () => _accept(r),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Принять заказ'),
            ),
          ),
        ],
      ),
    );
  }
}
