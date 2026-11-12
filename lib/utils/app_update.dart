import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const _manifestUrl = String.fromEnvironment(
  'BLT_UPDATE_MANIFEST',
  defaultValue: 'https://dpswxz.com/blt-updates/latest.json',
);
const _channel = MethodChannel('blt/update');
const _timeout = Duration(seconds: 20);
const _maxApkSize = 300 * 1024 * 1024;

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;
}

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.versionCode,
    required this.url,
    required this.size,
    required this.sha256,
  });

  final String version;
  final int versionCode;
  final Uri url;
  final int size;
  final String sha256;

  static ({String version, AppUpdate? update}) fromManifest(
    Object? data, {
    required Uri source,
    required PackageInfo installed,
  }) {
    if (data is! Map<String, dynamic>) {
      throw const AppUpdateException('更新服务器返回的版本信息无效');
    }
    if (data['packageName'] != installed.packageName) {
      throw const AppUpdateException('更新服务器没有适用于此应用的安装包');
    }
    final version = data['version'];
    final code = data['versionCode'];
    final installedCode = int.tryParse(installed.buildNumber);
    if (version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        code is! int ||
        code <= 0 ||
        installedCode == null) {
      throw const AppUpdateException('更新版本号无效');
    }
    if (code <= installedCode) return (version: version, update: null);

    final path = data['apk'];
    final digest = data['sha256'];
    final size = data['size'];
    final url = path is String ? source.resolve(path) : null;
    if (url == null ||
        !_sameHttpsOrigin(source, url) ||
        !url.path.endsWith('.apk') ||
        digest is! String ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(digest) ||
        size is! int ||
        size <= 0 ||
        size > _maxApkSize) {
      throw const AppUpdateException('安装包地址或校验信息无效');
    }
    return (
      version: version,
      update: AppUpdate(
        version: version,
        versionCode: code,
        url: url,
        size: size,
        sha256: digest.toLowerCase(),
      ),
    );
  }
}

bool _sameHttpsOrigin(Uri source, Uri url) =>
    source.scheme == 'https' &&
    url.scheme == 'https' &&
    url.host.isNotEmpty &&
    url.userInfo.isEmpty &&
    source.origin == url.origin;

class AppUpdater {
  final _http = HttpClient()..connectionTimeout = _timeout;

  void close() => _http.close(force: true);

  Future<({String version, AppUpdate? update})> check(
    PackageInfo installed,
  ) async {
    final url = Uri.parse(_manifestUrl);
    final response = await _get(url);
    final bytes = <int>[];
    await for (final chunk in response.timeout(_timeout)) {
      if (bytes.length + chunk.length > 64 * 1024) {
        throw const AppUpdateException('更新版本信息过大');
      }
      bytes.addAll(chunk);
    }
    return AppUpdate.fromManifest(
      jsonDecode(utf8.decode(bytes)),
      source: url,
      installed: installed,
    );
  }

  Future<HttpClientResponse> _get(Uri url) async {
    if (!_sameHttpsOrigin(url, url)) {
      throw const AppUpdateException('更新服务器必须使用 HTTPS');
    }
    final request = await _http.getUrl(url).timeout(_timeout);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw AppUpdateException('更新服务器请求失败（HTTP ${response.statusCode}）');
    }
    return response;
  }

  Future<File> download(AppUpdate update, void Function(int) onProgress) async {
    final cache = await getTemporaryDirectory();
    final directory = Directory('${cache.path}/updates');
    await directory.create(recursive: true);
    // Keep a recently handed-off file available to the system installer.
    await for (final entry in directory.list()) {
      if (entry is File &&
          DateTime.now().difference(await entry.lastModified()).inDays >= 1) {
        await entry.delete();
      }
    }
    final file = File(
      '${directory.path}/update-${DateTime.now().microsecondsSinceEpoch}.apk',
    );
    var received = 0;
    try {
      final response = await _get(update.url);
      final output = await file.open(mode: FileMode.write);
      try {
        await for (final chunk in response.timeout(_timeout)) {
          received += chunk.length;
          if (received > update.size) {
            throw const AppUpdateException('安装包大小与发布信息不一致');
          }
          await output.writeFrom(chunk);
          onProgress(received * 100 ~/ update.size);
        }
      } finally {
        await output.close();
      }
      if (received != update.size ||
          (await sha256.bind(file.openRead()).first).toString() !=
              update.sha256) {
        throw const AppUpdateException('安装包校验失败，请重新下载');
      }
      return file;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  /// Returns false after opening Android's install-permission settings.
  Future<bool> install(File apk, AppUpdate update) async =>
      await _channel.invokeMethod<bool>('install', {
        'path': apk.path,
        'version': update.version,
        'versionCode': update.versionCode,
      }) ??
      false;
}
