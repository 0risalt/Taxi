enum RideStatus {
  searching,
  accepted,
  arrived,
  inProgress,
  completed,
  cancelledByClient,
  cancelledByDriver;

  static RideStatus fromDb(String? v) {
    switch (v) {
      case 'accepted':
        return RideStatus.accepted;
      case 'arrived':
        return RideStatus.arrived;
      case 'in_progress':
        return RideStatus.inProgress;
      case 'completed':
        return RideStatus.completed;
      case 'cancelled_by_client':
        return RideStatus.cancelledByClient;
      case 'cancelled_by_driver':
        return RideStatus.cancelledByDriver;
      default:
        return RideStatus.searching;
    }
  }

  bool get isActive =>
      this == searching ||
      this == accepted ||
      this == arrived ||
      this == inProgress;

  bool get isCancelled =>
      this == cancelledByClient || this == cancelledByDriver;

  String get label {
    switch (this) {
      case RideStatus.searching:
        return 'Ищем водителя';
      case RideStatus.accepted:
        return 'Водитель едет к вам';
      case RideStatus.arrived:
        return 'Водитель на месте';
      case RideStatus.inProgress:
        return 'Вы в пути';
      case RideStatus.completed:
        return 'Поездка завершена';
      case RideStatus.cancelledByClient:
        return 'Заказ отменён клиентом';
      case RideStatus.cancelledByDriver:
        return 'Заказ отменён водителем';
    }
  }
}

double _num(dynamic v) => v is num ? v.toDouble() : double.parse(v.toString());

class RideStop {
  const RideStop({required this.lat, required this.lon, required this.address});

  final double lat;
  final double lon;
  final String address;

  Map<String, dynamic> toJson() =>
      {'lat': lat, 'lon': lon, 'address': address};

  factory RideStop.fromJson(Map<String, dynamic> m) => RideStop(
        lat: _num(m['lat']),
        lon: _num(m['lon']),
        address: (m['address'] as String?) ?? '',
      );
}

class DriverLocation {
  const DriverLocation({
    required this.lat,
    required this.lon,
    required this.isOnline,
  });

  final double lat;
  final double lon;
  final bool isOnline;

  factory DriverLocation.fromMap(Map<String, dynamic> m) => DriverLocation(
        lat: _num(m['lat']),
        lon: _num(m['lon']),
        isOnline: (m['is_online'] as bool?) ?? false,
      );
}

class Ride {
  const Ride({
    required this.id,
    required this.clientId,
    required this.driverId,
    required this.status,
    required this.fromAddress,
    required this.fromLat,
    required this.fromLon,
    required this.toAddress,
    required this.toLat,
    required this.toLon,
    required this.waypoints,
    required this.distanceM,
    required this.durationS,
    required this.price,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.createdAt,
  });

  final String id;
  final String clientId;
  final String? driverId;
  final RideStatus status;
  final String fromAddress;
  final double fromLat;
  final double fromLon;
  final String toAddress;
  final double toLat;
  final double toLon;
  final List<RideStop> waypoints;
  final int distanceM;
  final int durationS;
  final double price;
  final String paymentMethod; // 'cash' | 'card'
  final String paymentStatus; // 'pending' | 'paid'
  final DateTime createdAt;

  bool get isCard => paymentMethod == 'card';
  bool get isPaid => paymentStatus == 'paid';
  String get paymentLabel => isCard ? 'Картой' : 'Наличными';

  factory Ride.fromMap(Map<String, dynamic> m) {
    final wp = (m['waypoints'] as List?) ?? const [];
    return Ride(
      id: m['id'] as String,
      clientId: m['client_id'] as String,
      driverId: m['driver_id'] as String?,
      status: RideStatus.fromDb(m['status'] as String?),
      fromAddress: (m['from_address'] as String?) ?? '',
      fromLat: _num(m['from_lat']),
      fromLon: _num(m['from_lon']),
      toAddress: (m['to_address'] as String?) ?? '',
      toLat: _num(m['to_lat']),
      toLon: _num(m['to_lon']),
      waypoints: wp
          .map((e) => RideStop.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      distanceM: _num(m['distance_m']).round(),
      durationS: _num(m['duration_s']).round(),
      price: _num(m['price']),
      paymentMethod: (m['payment_method'] as String?) ?? 'cash',
      paymentStatus: (m['payment_status'] as String?) ?? 'pending',
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}
