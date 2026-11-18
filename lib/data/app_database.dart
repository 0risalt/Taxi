import 'dart:async';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Случайный идентификатор (32 hex-символа).
String newId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Текущее время в UTC в ISO-формате (так хранятся даты в базе).
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// Локальная база данных приложения (SQLite). Все данные живут на устройстве.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Future<Database>? _opening;

  final StreamController<String> _changes =
      StreamController<String>.broadcast();

  /// Имена таблиц, в которых что-то изменилось (для «живых» запросов).
  Stream<String> get changes => _changes.stream;

  void notifyChanged(String table) => _changes.add(table);

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'pickme_taxi.db');
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final sql in _schema) {
          await db.execute(sql);
        }
      },
    );
    _db = db;
    return db;
  }

  static const List<String> _schema = [
    // Аккаунты (пароль хранится только в виде хеша с солью).
    '''
    CREATE TABLE users (
      id            TEXT PRIMARY KEY,
      email         TEXT NOT NULL UNIQUE COLLATE NOCASE,
      password_hash TEXT NOT NULL,
      salt          TEXT NOT NULL,
      role          TEXT NOT NULL CHECK (role IN ('client', 'driver')),
      full_name     TEXT NOT NULL,
      phone         TEXT NOT NULL,
      car_model     TEXT,
      car_plate     TEXT,
      created_at    TEXT NOT NULL
    )
    ''',
    // Заказы такси.
    '''
    CREATE TABLE rides (
      id             TEXT PRIMARY KEY,
      client_id      TEXT NOT NULL REFERENCES users(id),
      driver_id      TEXT REFERENCES users(id),
      status         TEXT NOT NULL DEFAULT 'searching' CHECK (status IN (
                       'searching', 'accepted', 'arrived', 'in_progress',
                       'completed', 'cancelled_by_client', 'cancelled_by_driver')),
      from_address   TEXT NOT NULL,
      from_lat       REAL NOT NULL,
      from_lon       REAL NOT NULL,
      to_address     TEXT NOT NULL,
      to_lat         REAL NOT NULL,
      to_lon         REAL NOT NULL,
      waypoints      TEXT NOT NULL DEFAULT '[]',
      distance_m     INTEGER NOT NULL CHECK (distance_m >= 0),
      duration_s     INTEGER NOT NULL CHECK (duration_s >= 0),
      price          REAL NOT NULL,
      payment_method TEXT NOT NULL DEFAULT 'cash' CHECK (payment_method IN ('cash', 'card')),
      payment_status TEXT NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid')),
      created_at     TEXT NOT NULL,
      accepted_at    TEXT,
      started_at     TEXT,
      completed_at   TEXT
    )
    ''',
    // Не больше одного активного заказа у клиента и у водителя.
    '''
    CREATE UNIQUE INDEX rides_one_active_per_client ON rides (client_id)
      WHERE status IN ('searching', 'accepted', 'arrived', 'in_progress')
    ''',
    '''
    CREATE UNIQUE INDEX rides_one_active_per_driver ON rides (driver_id)
      WHERE status IN ('accepted', 'arrived', 'in_progress')
    ''',
    'CREATE INDEX rides_status_created ON rides (status, created_at)',
    // Последняя известная позиция водителя.
    '''
    CREATE TABLE driver_locations (
      driver_id  TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      lat        REAL NOT NULL,
      lon        REAL NOT NULL,
      is_online  INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    )
    ''',
    // Закладки, история, дом и работа — у каждого аккаунта свои.
    '''
    CREATE TABLE bookmarks (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      address    TEXT NOT NULL,
      latitude   REAL NOT NULL,
      longitude  REAL NOT NULL,
      type       TEXT NOT NULL CHECK (type IN ('bookmark', 'history', 'home', 'work')),
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX bookmarks_user_type ON bookmarks (user_id, type, id)',
    // Настройки (например, кто сейчас вошёл).
    '''
    CREATE TABLE settings (
      key   TEXT PRIMARY KEY,
      value TEXT
    )
    ''',
  ];
}

/// «Живой» запрос: сразу отдаёт результат и повторяет запрос при каждом
/// изменении указанных таблиц (замена Realtime). [refreshEvery] нужен, когда
/// результат зависит от времени (например, срок жизни заказа в поиске).
Stream<T> watchQuery<T>(
  Future<T> Function() query, {
  Set<String>? tables,
  Duration? refreshEvery,
}) {
  late final StreamController<T> controller;
  StreamSubscription<String>? sub;
  Timer? timer;
  var cancelled = false;
  var chain = Future<void>.value();

  // Запросы выполняются строго по очереди, чтобы ответы не перемешались.
  void emit() {
    chain = chain.then((_) async {
      if (cancelled) return;
      try {
        final value = await query();
        if (!cancelled) controller.add(value);
      } catch (e, st) {
        if (!cancelled) controller.addError(e, st);
      }
    });
  }

  controller = StreamController<T>(
    onListen: () {
      sub = AppDatabase.instance.changes
          .where((t) => tables == null || tables.contains(t))
          .listen((_) => emit());
      if (refreshEvery != null) {
        timer = Timer.periodic(refreshEvery, (_) => emit());
      }
      emit();
    },
    onCancel: () async {
      cancelled = true;
      timer?.cancel();
      await sub?.cancel();
    },
  );
  return controller.stream;
}
