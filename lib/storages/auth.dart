import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

const _cookieKey = 'bilibili_cookie',
    _refreshTokenKey = 'bilibili_refresh_token';
const _accountsKey = 'bilibili_accounts_v1';

class LoginInfo {
  final bool isLogin;
  final int? mid, level, vipType, vipStatus, vipDueDate;
  final String? nickname, avatar, vipLabel;
  const LoginInfo({
    required this.isLogin,
    this.mid,
    this.nickname,
    this.avatar,
    this.level,
    this.vipType,
    this.vipStatus,
    this.vipDueDate,
    this.vipLabel,
  });
  static const notLogin = LoginInfo(isLogin: false);
  static LoginInfo login({
    required int mid,
    required String nickname,
    required String avatar,
    int? level,
    int? vipType,
    int? vipStatus,
    int? vipDueDate,
    String? vipLabel,
  }) => LoginInfo(
    isLogin: true,
    mid: mid,
    nickname: nickname,
    avatar: avatar,
    level: level,
    vipType: vipType,
    vipStatus: vipStatus,
    vipDueDate: vipDueDate,
    vipLabel: vipLabel,
  );
  String get membershipLabel {
    if (vipStatus == null) return '会员信息待更新';
    if (vipStatus != 1) return '普通用户';
    if (vipLabel?.isNotEmpty == true) return vipLabel!;
    return vipType == 2 ? '年度大会员' : '大会员';
  }

  Map<String, dynamic> toJson() => {
    'mid': mid,
    'nickname': nickname,
    'avatar': avatar,
    'level': level,
    'vipType': vipType,
    'vipStatus': vipStatus,
    'vipDueDate': vipDueDate,
    'vipLabel': vipLabel,
  };
  factory LoginInfo.fromJson(Map<String, dynamic> d) => LoginInfo.login(
    mid: (d['mid'] as num).toInt(),
    nickname: d['nickname'] as String? ?? '',
    avatar: d['avatar'] as String? ?? '',
    level: (d['level'] as num?)?.toInt(),
    vipType: (d['vipType'] as num?)?.toInt(),
    vipStatus: (d['vipStatus'] as num?)?.toInt(),
    vipDueDate: (d['vipDueDate'] as num?)?.toInt(),
    vipLabel: d['vipLabel'] as String?,
  );
}

class SavedAccount {
  final LoginInfo profile;
  final String _cookie, _refresh;
  bool get needsLogin => _cookie.isEmpty;
  int get mid => profile.mid!;
  SavedAccount(this.profile, this._cookie, this._refresh);
  Map<String, dynamic> _json() => {
    'profile': profile.toJson(),
    'cookie': _cookie,
    'refresh': _refresh,
  };
}

class _Accounts {
  int? active;
  final List<SavedAccount> entries;
  _Accounts(this.entries, this.active);
}

final loginInfoNotifier = ValueNotifier(LoginInfo.notLogin);
final accountsRevision = ValueNotifier(0);
int authSessionVersion = 0;
Future<void>? _writeTail;
Future<T> _serial<T>(Future<T> Function() action) async {
  final previous = _writeTail;
  final release = Completer<void>();
  final gate = release.future;
  _writeTail = gate;
  try {
    if (previous != null) await previous;
    return await action();
  } finally {
    release.complete();
    if (identical(_writeTail, gate)) _writeTail = null;
  }
}

List<Cookie> _parseCookies(String text) {
  final list = <Cookie>[];
  for (final part in text.split(';')) {
    if (part.trim().isEmpty) continue;
    try {
      list.add(Cookie.fromSetCookieValue(part.trim()));
    } catch (_) {}
  }
  return list;
}

_Accounts? _read(SharedPreferences prefs) {
  final raw = prefs.getString(_accountsKey);
  if (raw == null) return null;
  // Never use another account's legacy credentials if a saved document is damaged.
  final d = jsonDecode(raw) as Map<String, dynamic>;
  final entries = <SavedAccount>[];
  for (final value in d['accounts'] as List? ?? const []) {
    try {
      final a = value as Map<String, dynamic>;
      final profile = LoginInfo.fromJson(a['profile'] as Map<String, dynamic>);
      if (profile.mid! > 0) {
        entries.add(
          SavedAccount(
            profile,
            a['cookie'] as String? ?? '',
            a['refresh'] as String? ?? '',
          ),
        );
      }
    } catch (_) {}
  }
  return _Accounts(entries, (d['active'] as num?)?.toInt());
}

Future<void> _save(SharedPreferences prefs, _Accounts state) async {
  final ok = await prefs.setString(
    _accountsKey,
    jsonEncode({
      'active': state.active,
      'accounts': state.entries.map((a) => a._json()).toList(),
    }),
  );
  if (!ok) throw StateError('账号保存失败');
  await prefs.remove(_cookieKey);
  await prefs.remove(_refreshTokenKey);
  accountsRevision.value++;
}

Future<_Accounts> _migrate(SharedPreferences prefs) async {
  final existing = _read(prefs);
  if (existing != null) return existing;
  final cookie = prefs.getString(_cookieKey) ?? '';
  final id = _parseCookies(
    cookie,
  ).where((c) => c.name == 'DedeUserID').firstOrNull?.value;
  final mid = int.tryParse(id ?? '') ?? loginInfoNotifier.value.mid;
  final state = _Accounts([], null);
  if (cookie.isNotEmpty && mid != null && mid > 0) {
    final info = loginInfoNotifier.value.mid == mid
        ? loginInfoNotifier.value
        : LoginInfo.login(mid: mid, nickname: '账号 $mid', avatar: '');
    state.entries.add(
      SavedAccount(info, cookie, prefs.getString(_refreshTokenKey) ?? ''),
    );
    state.active = mid;
    await _save(prefs, state);
  }
  return state;
}

Future<List<SavedAccount>> loadSavedAccounts() => _serial(() async {
  final prefs = await SharedPreferences.getInstance();
  return List.unmodifiable((await _migrate(prefs)).entries);
});
Future<void> restoreSavedLogin() async {
  final entries = await loadSavedAccounts();
  final state = _read(await SharedPreferences.getInstance());
  final active = entries
      .where((a) => a.mid == state?.active && !a.needsLogin)
      .firstOrNull;
  if (active != null) loginInfoNotifier.value = active.profile;
}

Future<List<Cookie>> loadCookie() async {
  final prefs = await SharedPreferences.getInstance();
  final state = _read(prefs);
  if (state == null) return _parseCookies(prefs.getString(_cookieKey) ?? '');
  return _parseCookies(
    state.entries.where((a) => a.mid == state.active).firstOrNull?._cookie ??
        '',
  );
}

Future<String?> loadRefreshToken() async {
  final prefs = await SharedPreferences.getInstance();
  final state = _read(prefs);
  if (state == null) return prefs.getString(_refreshTokenKey);
  final token = state.entries
      .where((a) => a.mid == state.active)
      .firstOrNull
      ?._refresh;
  return token == null || token.isEmpty ? null : token;
}

Future<void> saveCookie(List<Cookie> cookies, {String refreshToken = ''}) =>
    _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      final state = _read(prefs);
      final text = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      if (state == null) {
        await prefs.setString(_cookieKey, text);
        if (refreshToken.isNotEmpty) {
          await prefs.setString(_refreshTokenKey, refreshToken);
        }
      } else {
        final index = state.entries.indexWhere((a) => a.mid == state.active);
        if (index < 0) throw StateError('请先选择账号');
        final old = state.entries[index];
        state.entries[index] = SavedAccount(
          old.profile,
          text,
          refreshToken.isEmpty ? old._refresh : refreshToken,
        );
        await _save(prefs, state);
      }
    });
Future<void> saveSignedInAccount(
  LoginInfo profile,
  List<Cookie> cookies, {
  String refreshToken = '',
  bool activate = true,
}) => _serial(() async {
  final prefs = await SharedPreferences.getInstance();
  final state = await _migrate(prefs);
  state.entries.removeWhere((a) => a.mid == profile.mid);
  state.entries.add(
    SavedAccount(
      profile,
      cookies.map((c) => '${c.name}=${c.value}').join('; '),
      refreshToken,
    ),
  );
  if (activate) state.active = profile.mid;
  await _save(prefs, state);
  if (activate || state.active == profile.mid) {
    authSessionVersion++;
    loginInfoNotifier.value = profile;
  }
});
Future<void> rememberCurrentAccount(LoginInfo profile, {int? expectedMid}) =>
    _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      var state = _read(prefs);
      if (state == null) {
        final cookie = prefs.getString(_cookieKey) ?? '';
        if (cookie.isEmpty) return;
        state = _Accounts([
          SavedAccount(
            profile,
            cookie,
            prefs.getString(_refreshTokenKey) ?? '',
          ),
        ], profile.mid);
      } else {
        if (expectedMid != null && state.active != expectedMid) return;
        if (state.active != profile.mid) return;
        final i = state.entries.indexWhere((a) => a.mid == profile.mid);
        if (i < 0) return;
        final old = state.entries[i];
        state.entries[i] = SavedAccount(profile, old._cookie, old._refresh);
      }
      await _save(prefs, state);
      loginInfoNotifier.value = profile;
    });
Future<List<Cookie>> loadAccountCookies(int mid) async {
  final accounts = await loadSavedAccounts();
  return _parseCookies(
    accounts.where((a) => a.mid == mid).firstOrNull?._cookie ?? '',
  );
}

Future<void> switchSavedAccount(int mid, {LoginInfo? refreshedProfile}) =>
    _serial(() async {
      final prefs = await SharedPreferences.getInstance();
      final state = await _migrate(prefs);
      final i = state.entries.indexWhere((a) => a.mid == mid && !a.needsLogin);
      if (i < 0) throw StateError('该账号需要重新扫码登录');
      final old = state.entries[i];
      final profile = refreshedProfile ?? old.profile;
      if (profile.mid != mid) throw StateError('账号信息不匹配');
      state.entries[i] = SavedAccount(profile, old._cookie, old._refresh);
      state.active = mid;
      await _save(prefs, state);
      authSessionVersion++;
      loginInfoNotifier.value = profile;
    });
Future<void> removeSavedAccount(int mid) => _serial(() async {
  final prefs = await SharedPreferences.getInstance();
  final state = await _migrate(prefs);
  state.entries.removeWhere((a) => a.mid == mid);
  final active = state.active == mid;
  if (active) state.active = null;
  await _save(prefs, state);
  if (active) {
    authSessionVersion++;
    loginInfoNotifier.value = LoginInfo.notLogin;
  }
});
Future<void> clearCookie({bool withRefreshToken = true}) => _serial(() async {
  final prefs = await SharedPreferences.getInstance();
  final state = _read(prefs);
  if (state != null) {
    final i = state.entries.indexWhere((a) => a.mid == state.active);
    if (i >= 0) {
      final old = state.entries[i];
      state.entries[i] = SavedAccount(
        old.profile,
        '',
        withRefreshToken ? '' : old._refresh,
      );
    }
    state.active = null;
    await _save(prefs, state);
    authSessionVersion++;
  }
  loginInfoNotifier.value = LoginInfo.notLogin;
  await prefs.remove(_cookieKey);
  if (withRefreshToken) await prefs.remove(_refreshTokenKey);
});
