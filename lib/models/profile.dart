class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.fullName,
    required this.phone,
    this.carModel,
    this.carPlate,
  });

  final String id;
  final String role; // 'client' | 'driver'
  final String fullName;
  final String phone;
  final String? carModel;
  final String? carPlate;

  bool get isDriver => role == 'driver';

  String get carInfo => [carModel, carPlate]
      .where((e) => e != null && e.isNotEmpty)
      .join(' · ');

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        role: (m['role'] as String?) ?? 'client',
        fullName: (m['full_name'] as String?) ?? '',
        phone: (m['phone'] as String?) ?? '',
        carModel: m['car_model'] as String?,
        carPlate: m['car_plate'] as String?,
      );
}
