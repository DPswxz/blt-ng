// 本地日志：统一格式（时间/级别/tag/消息），debug 全量、release 仅 warning+。
//
// 日志只保存在本地（应用文档目录，滚动保留），不上传任何数据。
// 使用方式：在模块内缓存实例，例如 `final _log = log('bilibili');`

import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

const _logFileName = 'blt.log';
const _maxLogFileBytes = 2 * 1024 * 1024; // 单文件 2MB
const _maxLogBackups = 3; // 保留 3 个历史文件

final List<LogOutput> _outputs = [ConsoleOutput()];

// 初始化文件日志（应用启动时调用一次），失败时仅保留控制台输出
Future<void> initFileLogging({Directory? directory}) async {
  try {
    final dir = directory ?? await getApplicationDocumentsDirectory();
    for (final output in _outputs.whereType<RollingFileOutput>()) {
      await output.flush();
    }
    _outputs.removeWhere((output) => output is RollingFileOutput);
    _outputs.add(RollingFileOutput(File('${dir.path}/$_logFileName')));
  } catch (_) {
    // 文件日志不可用时不影响控制台日志
  }
}

// 带 tag 的日志工厂
Logger log(String tag) => Logger(
  filter: kReleaseMode ? ProductionFilter() : DevelopmentFilter(),
  level: kReleaseMode
      ? (tag == 'playback' ? Level.info : Level.warning)
      : Level.trace,
  printer: TagPrinter(tag),
  output: MultiOutput(List.of(_outputs)),
);

// 格式：[时间] [级别] [tag] 消息，错误与堆栈跟随
class TagPrinter extends LogPrinter {
  static const _levelNames = {
    Level.trace: 'TRACE',
    Level.debug: 'DEBUG',
    Level.info: 'INFO',
    Level.warning: 'WARN',
    Level.error: 'ERROR',
    Level.fatal: 'FATAL',
  };

  final String tag;

  TagPrinter(this.tag);

  @override
  List<String> log(LogEvent event) {
    final time = event.time;
    String two(int value) => value.toString().padLeft(2, '0');
    final timestamp =
        '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    final level = _levelNames[event.level] ?? event.level.name.toUpperCase();

    final lines = <String>['[$timestamp] [$level] [$tag] ${event.message}'];
    if (event.error != null) {
      lines.add('    error: ${event.error}');
    }
    if (event.stackTrace != null) {
      lines.add('    stack: ${event.stackTrace}');
    }
    return lines;
  }
}

// 写入文件并在超过上限时滚动（file.log.1 ~ file.log.N）
class RollingFileOutput extends LogOutput {
  final File file;
  final int maxBytes;
  final int backups;
  Future<void> _pending = Future<void>.value();
  int _pendingBytes = 0;
  static const _maxPendingBytes = 256 * 1024;

  Future<void> flush() => _pending;

  RollingFileOutput(
    this.file, {
    this.maxBytes = _maxLogFileBytes,
    this.backups = _maxLogBackups,
  });

  @override
  void output(OutputEvent event) {
    final bytes = utf8.encode('${event.lines.join('\n')}\n');
    // Slow TV storage must not block rendering or build an unbounded queue.
    if (_pendingBytes + bytes.length > _maxPendingBytes) return;
    _pendingBytes += bytes.length;
    _pending = _pending.then((_) async {
      try {
        if (await file.exists() &&
            await file.length() + bytes.length > maxBytes) {
          await _rotate();
        }
        await file.writeAsBytes(bytes, mode: FileMode.append);
      } catch (_) {
        // A failed write must not poison later writes or affect playback.
      } finally {
        _pendingBytes -= bytes.length;
      }
    });
  }

  Future<void> _rotate() async {
    final oldest = File('${file.path}.$backups');
    if (await oldest.exists()) await oldest.delete();
    for (var i = backups - 1; i >= 1; i--) {
      final source = File('${file.path}.$i');
      if (await source.exists()) {
        await source.rename('${file.path}.${i + 1}');
      }
    }
    if (await file.exists()) {
      await file.rename('${file.path}.1');
    }
  }
}
