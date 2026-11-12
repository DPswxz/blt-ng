import 'dart:async';
import 'dart:io';

import 'package:blt/utils/app_update.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> showAppUpdateDialog(
  BuildContext context, {
  required ValueChanged<String> onVersionChecked,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _AppUpdateDialog(onVersionChecked: onVersionChecked),
);

class _AppUpdateDialog extends StatefulWidget {
  const _AppUpdateDialog({required this.onVersionChecked});

  final ValueChanged<String> onVersionChecked;

  @override
  State<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<_AppUpdateDialog> {
  final _updater = AppUpdater();
  AppUpdate? _update;
  File? _apk;
  bool _handedOff = false;
  bool _busy = true;
  bool _installing = false;
  int? _percent;
  String _status = '正在检查更新…';
  String? _installedVersion;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _updater.close();
    final apk = _apk;
    if (!_handedOff && apk != null) unawaited(_delete(apk));
    super.dispose();
  }

  Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // The cache may already have been cleared.
    }
  }

  Future<void> _check() async {
    try {
      final installed = await PackageInfo.fromPlatform();
      if (!mounted) return;
      _installedVersion = installed.version;
      final result = await _updater.check(installed);
      if (!mounted) return;
      setState(() {
        _update = result.update;
        _busy = false;
        _status = result.update == null
            ? '当前已是最新版本'
            : '发现新版本 ${result.version}';
      });
      widget.onVersionChecked(result.version);
    } catch (error) {
      _showError(error, '检查更新失败，请检查网络后重试');
    }
  }

  Future<void> _downloadAndInstall() async {
    final update = _update;
    if (update == null || _busy) return;
    setState(() {
      _busy = true;
      _percent = _apk == null ? 0 : null;
      _status = _apk == null ? '正在下载安装包…' : '正在校验安装包…';
    });
    try {
      if (_apk == null) {
        final apk = await _updater.download(update, (percent) {
          if (mounted && _percent != percent) {
            setState(() => _percent = percent);
          }
        });
        if (!mounted) {
          await _delete(apk);
          return;
        }
        _apk = apk;
      }
      setState(() {
        _installing = true;
        _percent = null;
        _status = '正在打开系统安装器…';
      });
      final started = await _updater.install(_apk!, update);
      if (!mounted) return;
      if (started) {
        _handedOff = true;
        Navigator.of(context).pop();
      } else {
        setState(() {
          _busy = false;
          _installing = false;
          _status = '请在系统设置中允许安装应用，返回后选择“安装”';
        });
      }
    } catch (error) {
      _showError(error, '下载失败，请检查网络后重试');
    }
  }

  void _showError(Object error, String fallback) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _installing = false;
      _percent = null;
      _status = switch (error) {
        AppUpdateException(:final message) => message,
        PlatformException(:final message) => message ?? '无法打开系统安装器',
        FileSystemException() => '无法保存安装包，请检查电视存储空间',
        _ => fallback,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return PopScope(
      canPop: !_installing,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 640 * ui,
          padding: EdgeInsets.all(32 * ui),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24 * ui),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '检查更新',
                style: TextStyle(
                  fontSize: 30 * ui,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 16 * ui),
              if (_installedVersion != null)
                Text(
                  '当前版本 $_installedVersion',
                  style: TextStyle(fontSize: 20 * ui),
                ),
              Text(_status, style: TextStyle(fontSize: 24 * ui)),
              if (_busy) ...[
                SizedBox(height: 16 * ui),
                LinearProgressIndicator(
                  value: _percent == null ? null : _percent! / 100,
                  minHeight: 6 * ui,
                  semanticsLabel: '更新进度',
                ),
                if (_percent != null)
                  Text('$_percent%', style: TextStyle(fontSize: 20 * ui)),
              ],
              SizedBox(height: 24 * ui),
              Row(
                children: [
                  if (!_installing)
                    Expanded(
                      child: PinkButton(
                        ui: ui,
                        label: _busy ? '取消' : '关闭',
                        autofocus: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  if (!_busy && _update != null) ...[
                    SizedBox(width: 16 * ui),
                    Expanded(
                      child: PinkButton(
                        ui: ui,
                        label: _apk == null ? '下载安装' : '安装',
                        onPressed: _downloadAndInstall,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
