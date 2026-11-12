import 'package:blt/utils/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  final installed = PackageInfo(
    appName: 'blt-ng',
    packageName: 'com.kkkunny.blt.tcl.stability',
    version: '1.0.29',
    buildNumber: '3053',
  );
  final source = Uri.parse('https://dpswxz.com/blt-updates/latest.json');
  final manifest = <String, dynamic>{
    'packageName': installed.packageName,
    'version': '1.0.31',
    'versionCode': 3055,
    'apk': 'blt-ng-1.0.31-armeabi-v7a.apk',
    'size': 31461284,
    'sha256': 'a' * 64,
  };

  ({String version, AppUpdate? update}) parse(Map<String, dynamic> data) =>
      AppUpdate.fromManifest(data, source: source, installed: installed);

  test('only offers a newer Android version code', () {
    final update = parse(manifest).update!;
    expect(update.version, '1.0.31');
    expect(update.versionCode, 3055);
    expect(update.url, source.resolve(manifest['apk'] as String));
    expect(parse({...manifest, 'versionCode': 3053}), (
      version: '1.0.31',
      update: null,
    ));
    expect(parse({...manifest, 'versionCode': 3052}).update, isNull);
  });

  test(
    'rejects a different application, untrusted origin and invalid digest',
    () {
      for (final invalid in [
        {'packageName': 'com.kkkunny.blt'},
        {'apk': 'http://dpswxz.com/blt-updates/update.apk'},
        {'apk': 'https://other.example/update.apk'},
        {'sha256': ''},
        {'size': 0},
      ]) {
        expect(
          () => parse({...manifest, ...invalid}),
          throwsA(isA<AppUpdateException>()),
        );
      }
    },
  );
}
