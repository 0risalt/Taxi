import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_maps_mapkit/mapkit.dart' as ymk;

import '../models/profile.dart';
import '../models/ride.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../services/ride_service.dart';
import '../services/yandex_api.dart';
import '../theme/app_colors.dart';
import '../utils/format.dart';
import '../widgets/taxi_map.dart';

class ClientRideScreen extends StatefulWidget {
  const ClientRideScreen({super.key, required this.rideId});

  final String rideId;

  @override
  State<ClientRideScreen> createState() => _ClientRideScreenState();
}

class _ClientRideScreenState extends State<ClientRideScreen> {
  final _rides = RideService();
  final _auth = AuthService();
  final _api = YandexApi();
  final _map = TaxiMapController();

  StreamSubscription<Ride?>? _rideSub;
  StreamSubscription<DriverLocation?>? _locSub;

  Ride? _ride;
  Profile? _driver;
  String? _watchedDriverId;
  bool _mapReady = false;
  bool _sceneDrawn = false;
  bool _busy = false;
  String? _error;

  ymk.PlacemarkMapObject? _carMarker;
  final List<ymk.PlacemarkMapObject> _pins = [];

  @override
  void initState() {
    super.initState();
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
    _locSub?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------ данные

  void _onRide(Ride? ride) {
    if (ride == null || !mounted) return;
    setState(() {
      _ride = ride;
      _error = null;
    });

    final driverId = ride.driverId;
    if (driverId != null && driverId != _watchedDriverId) {
      _watchDriver(driverId);
    } else if (driverId == null && _watchedDriverId != null) {
      _stopWatchingDriver();
    }

    if (!ride.status.isActive) {
      // Поездка закончилась — машину с карты убираем.
      _stopWatchingDriver(keepProfile: true);
    }
    _syncMap();
  }

  Future<void> _watchDriver(String driverId) async {
    _watchedDriverId = driverId;
    _locSub?.cancel();
    _locSub = _rides.watchDriverLocation(driverId).listen((loc) {
      if (loc == null || !mounted || !_mapReady) return;
      if (_carMarker == null) {
        _carMarker = _map.addCar(loc.lat, loc.lon);
      } else {
        _map.moveMarker(_carMarker, loc.lat, loc.lon);
      }
    });
    try {
      final p = await _auth.getProfile(driverId);
      if (mounted && _watchedDriverId == driverId) setState(() => _driver = p);
    } catch (_) {}
  }

  void _stopWatchingDriver({bool keepProfile = false}) {
    _locSub?.cancel();
    _locSub = null;
    _watchedDriverId = null;
    _map.removeMarker(_carMarker);
    _carMarker = null;
    if (!keepProfile && mounted) setState(() => _driver = null);
  }

  // ------------------------------------------------------------- карта

  void _onMapReady() {
    _mapReady = true;
    _syncMap();
  }

  Future<void> _syncMap() async {
    final ride = _ride;
    if (!_mapReady || ride == null || _sceneDrawn) return;
    _sceneDrawn = true;

    _pins
      ..forEach(_map.removeMarker)
      ..clear();
    final from = _map.addPin(ride.fromLat, ride.fromLon);
    final to = _map.addPin(ride.toLat, ride.toLon);
    for (final m in [from, to]) {
      if (m != null) _pins.add(m);
    }
    _map.moveTo(ride.fromLat, ride.fromLon, zoom: 13);

    final route = await _api.buildRoute([
      LatLon(ride.fromLat, ride.fromLon),
      for (final w in ride.waypoints) LatLon(w.lat, w.lon),
      LatLon(ride.toLat, ride.toLon),
    ]);
    if (route != null && mounted) _map.setRoute(route.points);
  }

  // ----------------------------------------------------------- действия

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить заказ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Нет')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Отменить',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _rides.cancelRide(widget.rideId);
    } catch (e) {
      _snack('Не удалось отменить заказ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payByCard() async {
    final ride = _ride;
    if (ride == null) return;
    setState(() => _busy = true);
    try {
      final ok = await paymentService
          .payForRide(rideId: ride.id, amount: ride.price);
      if (ok) {
        await _rides.markPaid(ride.id);
        _snack('Оплачено (тестовый режим)');
      } else {
        _snack('Оплата не прошла');
      }
    } catch (e) {
      _snack('Не удалось оплатить');
    } finally {
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
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildPanel(),
            ),
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
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.redAccent))
                else
                  const CircularProgressIndicator(color: AppColors.primary),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statusHeader(ride),
                const SizedBox(height: 12),
                if (_driver != null && ride.status.isActive &&
                    ride.status != RideStatus.searching)
                  _driverCard(_driver!),
                _addressRow(Icons.my_location, ride.fromAddress),
                _addressRow(Icons.location_on, ride.toAddress),
                const SizedBox(height: 8),
                _priceRow(ride),
                const SizedBox(height: 12),
                ..._actions(ride),
              ],
            ),
    );
  }

  Widget _statusHeader(Ride ride) {
    final searching = ride.status == RideStatus.searching;
    return Row(
      children: [
        if (searching)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppColors.primary),
            ),
          ),
        Expanded(
          child: Text(
            ride.status.label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _driverCard(Profile d) {
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
            child: Icon(Icons.local_taxi, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.fullName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                if (d.carInfo.isNotEmpty)
                  Text(d.carInfo,
                      style: const TextStyle(color: Colors.black54)),
                if (d.phone.isNotEmpty)
                  SelectableText(d.phone,
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
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _priceRow(Ride ride) {
    return Row(
      children: [
        Text(formatPrice(ride.price),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(width: 10),
        Text('${formatDistance(ride.distanceM.toDouble())} · '
            '${formatDuration(ride.durationS.toDouble())}',
            style: const TextStyle(color: Colors.grey)),
        const Spacer(),
        Chip(
          avatar: Icon(ride.isCard ? Icons.credit_card : Icons.payments,
              size: 16, color: AppColors.primaryDark),
          label: Text(ride.paymentLabel),
          backgroundColor: AppColors.background,
          side: BorderSide(color: Colors.pink.shade100),
        ),
      ],
    );
  }

  List<Widget> _actions(Ride ride) {
    final spinner = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));

    switch (ride.status) {
      case RideStatus.searching:
      case RideStatus.accepted:
      case RideStatus.arrived:
        return [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _busy ? null : _cancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25)),
              ),
              child: const Text('Отменить заказ'),
            ),
          ),
        ];
      case RideStatus.inProgress:
        return const [];
      case RideStatus.completed:
        return [
          if (ride.isCard && !ride.isPaid)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _payByCard,
                icon: _busy ? spinner : const Icon(Icons.credit_card),
                label: Text('Оплатить ${formatPrice(ride.price)} (тест)'),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                ride.isCard
                    ? 'Оплачено картой'
                    : 'Оплатите водителю наличными',
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/'),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Готово'),
            ),
          ),
        ];
      case RideStatus.cancelledByClient:
      case RideStatus.cancelledByDriver:
        return [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/'),
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('На главную'),
            ),
          ),
        ];
    }
  }
}
