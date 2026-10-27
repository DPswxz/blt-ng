import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blt/storages/auth.dart';

/// A bounded, account-scoped index. Playback time continues to use cloud history.
class SeasonHistory {
  static Future<void> _pending = Future.value();
  static String _key(int mid) => 'season_episode_history_v1.$mid';

  static Future<int?> episode(int season) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _decode(
      prefs.getString(_key(loginInfoNotifier.value.mid ?? 0)),
    );
    return (entries['$season'] as num?)?.toInt();
  }

  static Map<String, dynamic> _decode(String? raw) {
    try {
      return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(int season, int episode, int mid) {
    final task = _pending.catchError((_) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final entries = _decode(prefs.getString(_key(mid)));
      entries.remove('$season');
      entries['$season'] = episode;
      while (entries.length > 100) {
        entries.remove(entries.keys.first);
      }
      await prefs.setString(_key(mid), jsonEncode(entries));
    });
    _pending = task;
    return task;
  }
}
