import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/auth_service.dart';
import '../services/driver_location_service.dart';
import '../theme/app_colors.dart';
import 'driver_home_screen.dart';
import 'home_screen.dart';

/// Загружает профиль и открывает клиентский или водительский интерфейс.
class RoleGate extends StatefulWidget {
  const RoleGate({super.key});

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  final _auth = AuthService();
  late Future<Profile?> _future = _auth.loadMyProfile();

  void _retry() => setState(() => _future = _auth.loadMyProfile());

  Future<void> _logout() async {
    await driverLocationService.stop();
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        final profile = snap.data;
        if (snap.hasError || profile == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.primary),
                    const SizedBox(height: 12),
                    const Text('Не удалось загрузить профиль',
                        style: TextStyle(fontSize: 18)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                        onPressed: _retry, child: const Text('Повторить')),
                    TextButton(
                        onPressed: _logout, child: const Text('Выйти')),
                  ],
                ),
              ),
            ),
          );
        }
        return profile.isDriver
            ? DriverHomeScreen(profile: profile)
            : const HomeScreen();
      },
    );
  }
}
