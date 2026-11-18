import 'package:flutter/material.dart';
import 'package:yandex_maps_mapkit/init.dart' as init;
import 'package:yandex_maps_mapkit/mapkit_factory.dart';

import 'config.dart';
import 'router.dart';
import 'services/auth_service.dart';
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // MapKit нужно инициализировать до создания виджета карты.
  await init.initMapkit(apiKey: AppConfig.mapkitApiKey);

  // Локальная база (SQLite) открывается при первом обращении;
  // здесь восстанавливаем вход предыдущего сеанса.
  await AuthService().init();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Жизненным циклом MapKit управляем один раз на всё приложение,
    // а не на каждом экране (иначе при смене экранов карта "засыпает").
    mapkit.onStart();
    _lifecycle = AppLifecycleListener(
      onResume: () => mapkit.onStart(),
      onPause: () => mapkit.onStop(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    mapkit.onStop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PickMe Taxi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
          ),
        ),
      ),
      routerConfig: appRouter,
    );
  }
}
