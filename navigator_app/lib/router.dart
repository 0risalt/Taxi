import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/client_ride_screen.dart';
import 'screens/driver_ride_screen.dart';
import 'screens/role_gate.dart';

/// Обновляет роутер при входе/выходе пользователя.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: _AuthNotifier(),
  redirect: (context, state) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final loc = state.matchedLocation;
    final onAuthPage = loc == '/login' || loc == '/register';
    if (!loggedIn && !onAuthPage) return '/login';
    if (loggedIn && onAuthPage) return '/';
    return null;
  },
  routes: [
    // Клиентский или водительский главный экран — по роли в профиле.
    GoRoute(path: '/', builder: (context, state) => const RoleGate()),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
        path: '/register', builder: (context, state) => const RegisterScreen()),
    GoRoute(
      path: '/ride/:id',
      builder: (context, state) =>
          ClientRideScreen(rideId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/driver/ride/:id',
      builder: (context, state) =>
          DriverRideScreen(rideId: state.pathParameters['id']!),
    ),
  ],
);
