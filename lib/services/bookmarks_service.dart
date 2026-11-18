import '../data/app_database.dart';
import 'auth_service.dart';

/// Закладки, история, «Дом» и «Работа» текущего аккаунта (локальная база).
class BookmarksService {
  final AppDatabase _db = AppDatabase.instance;

  String _uid() {
    final id = AuthService().currentUserId;
    if (id == null) throw StateError('Пользователь не вошёл в аккаунт');
    return id;
  }

  List<Map<String, dynamic>> _toMaps(List<Map<String, Object?>> rows) =>
      rows.map((r) => Map<String, dynamic>.from(r)).toList();

  // Сохранить точку (закладка, дом, работа, история)
  Future<void> savePlace({
    required String address,
    required double lat,
    required double lon,
    required String type,
  }) async {
    final db = await _db.database;
    final uid = _uid();
    await db.insert('bookmarks', {
      'user_id': uid,
      'address': address,
      'latitude': lat,
      'longitude': lon,
      'type': type,
      'created_at': nowIso(),
    });
    if (type == 'history') {
      // Храним только 50 последних записей истории.
      await db.rawDelete(
        '''
        DELETE FROM bookmarks
        WHERE user_id = ? AND type = 'history' AND id NOT IN (
          SELECT id FROM bookmarks
          WHERE user_id = ? AND type = 'history'
          ORDER BY id DESC LIMIT 50
        )
        ''',
        [uid, uid],
      );
    }
  }

  // Получить закладки
  Future<List<Map<String, dynamic>>> getBookmarks() async {
    final db = await _db.database;
    final rows = await db.query('bookmarks',
        where: 'user_id = ? AND type = ?',
        whereArgs: [_uid(), 'bookmark'],
        orderBy: 'id DESC');
    return _toMaps(rows);
  }

  // Получить историю (20 последних маршрутов)
  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await _db.database;
    final rows = await db.query('bookmarks',
        where: 'user_id = ? AND type = ?',
        whereArgs: [_uid(), 'history'],
        orderBy: 'id DESC',
        limit: 20);
    return _toMaps(rows);
  }

  // Получить Дом или Работу (самую свежую запись)
  Future<Map<String, dynamic>?> getPlace(String type) async {
    final db = await _db.database;
    final rows = await db.query('bookmarks',
        where: 'user_id = ? AND type = ?',
        whereArgs: [_uid(), type],
        orderBy: 'id DESC',
        limit: 1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  // Удалить любую запись по ID (закладки и история)
  Future<void> deleteItem(int id) async {
    final db = await _db.database;
    await db.delete('bookmarks',
        where: 'id = ? AND user_id = ?', whereArgs: [id, _uid()]);
  }
}
