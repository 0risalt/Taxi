import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

class AuthService {
  SupabaseClient get _c => Supabase.instance.client;

  User? get user => _c.auth.currentUser;

  /// Роль и данные профиля передаются в metadata, а профиль создаёт
  /// SQL-триггер handle_new_user (работает и при включённом подтверждении email).
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String role,
    required String fullName,
    required String phone,
    String? carModel,
    String? carPlate,
  }) {
    return _c.auth.signUp(
      email: email,
      password: password,
      data: {
        'role': role,
        'full_name': fullName,
        'phone': phone,
        if (carModel != null) 'car_model': carModel,
        if (carPlate != null) 'car_plate': carPlate,
      },
    );
  }

  Future<void> signIn(String email, String password) async {
    await _c.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _c.auth.signOut();

  Future<Profile?> loadMyProfile() async {
    final u = user;
    if (u == null) return null;
    return getProfile(u.id);
  }

  Future<Profile?> getProfile(String id) async {
    final m = await _c.from('profiles').select().eq('id', id).maybeSingle();
    return m == null ? null : Profile.fromMap(m);
  }
}
