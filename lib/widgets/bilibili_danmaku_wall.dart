import 'package:blt/utils/request_scope.dart';
import 'dart:async';

import 'package:blt/apis/bilibili/media.dart';
import 'package:blt/consts/bilibili.dart';
import 'package:blt/models/pbs/dm.pb.dart';
import 'package:blt/storages/settings.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';

const danmakuAreaLabels = {
  5: '顶部 5%',
  10: '顶部 10%',
  25: '顶部 25%',
  50: '顶部 50%',
};
String danmakuTransparencyLabel(int value) =>
    value == 0 ? '0%（不透明）' : '$value%';

class BilibiliDanmakuWallController {
  // 弹幕墙就绪前为空，此时所有操作均为空操作
  DanmakuController? _controller;
  Future<void> Function()? _reloadFunc;
  Future<void> reloadSettings() async {
    await _reloadFunc?.call();
  }

  final ValueNotifier<bool> enableNotifier;

  BilibiliDanmakuWallController(bool enable)
    : enableNotifier = ValueNotifier(enable);

  void dispose() => enableNotifier.dispose();

  set enabled(bool enable) => enableNotifier.value = enable;

  bool get enabled => enableNotifier.value;

  // 清空，并重新开始推送弹幕（弹幕墙未挂载时为空操作）
  Function() _clearFunc = () {};

  void clear() {
    _clearFunc();
  }

  // 等待一会儿再开始载入弹幕，用于步进等场景，避免频繁拉取（弹幕墙未挂载时为空操作）
  Function(Duration duration) _waitFunc = (_) {};

  void wait(Duration duration) {
    _waitFunc(duration);
  }

  void clearDanmaku() => _controller?.clear();

  void pause() => _controller?.pause();

  void resume() => _controller?.resume();

  void addDanmaku(DanmakuContentItem item) => _controller?.addDanmaku(item);
}

// bilibili弹幕墙
class BilibiliDanmakuWall extends StatefulWidget {
  final BilibiliDanmakuWallController controller;
  final int cid;
  final Stream<Duration> timeline;
  final Stream<bool> playing;

  const BilibiliDanmakuWall({
    super.key,
    required this.controller,
    required this.cid,
    required this.timeline,
    required this.playing,
  });

  @override
  State<BilibiliDanmakuWall> createState() => _BilibiliDanmakuWallState();
}

class _BilibiliDanmakuWallState extends State<BilibiliDanmakuWall> {
  final _requests = RequestScope();
  int _danmuBlockWeight = 6;
  double _danmuFontSize = 20;
  int _danmuArea = 10;
  int _transparency = 0;
  bool _initDone = false;
  bool _pullDanmaku = false;
  DateTime? _lastPullFailTime;
  (int, int, DmSegMobileReply)? _danmakuCache; // (cid, 分块index, 弹幕数据)

  StreamSubscription<Duration>? _timelineSubscription;
  StreamSubscription<bool>? _playingSubscription;

  @override
  void initState() {
    super.initState();
    _timelineSubscription = widget.timeline.listen(_onPosition);
    _playingSubscription = widget.playing.listen(_onPlayingChanged);
    widget.controller.enableNotifier.addListener(_onEnableChanged);
    widget.controller._reloadFunc = _init;
    widget.controller._clearFunc = _onClear;
    widget.controller._waitFunc = _onWait;
    _init();
  }

  @override
  void didUpdateWidget(covariant BilibiliDanmakuWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cid != widget.cid) {
      // 切分P：丢弃旧分P缓存与时间轴进度，避免旧弹幕串台
      _danmakuCache = null;
      _lastPushDanmakuTime = null;
      _pullDanmaku = false;
      _onClear();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.enableNotifier.removeListener(_onEnableChanged);
      oldWidget.controller._clearFunc = () {};
      oldWidget.controller._waitFunc = (_) {};
      widget.controller.enableNotifier.addListener(_onEnableChanged);
      widget.controller._reloadFunc = _init;
      widget.controller._clearFunc = _onClear;
      widget.controller._waitFunc = _onWait;
    }
    if (oldWidget.timeline != widget.timeline) {
      _timelineSubscription?.cancel();
      _timelineSubscription = widget.timeline.listen(_onPosition);
    }
    if (oldWidget.playing != widget.playing) {
      _playingSubscription?.cancel();
      _playingSubscription = widget.playing.listen(_onPlayingChanged);
    }
  }

  @override
  void dispose() {
    _requests.dispose();
    widget.controller._reloadFunc = null;
    _timelineSubscription?.cancel();
    _playingSubscription?.cancel();
    widget.controller.enableNotifier.removeListener(_onEnableChanged);
    widget.controller._clearFunc = () {};
    widget.controller._waitFunc = (_) {};
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final weight = await Settings.getInt(Settings.pathDanmuBlockWeightSwitch);
      final fontSize = await Settings.getInt(Settings.pathDanmuFontSize);
      final area = await Settings.getInt(Settings.pathDanmuArea) ?? 10;
      final transparency =
          await Settings.getInt(Settings.pathDanmuTransparency) ?? 0;
      if (!mounted) return;
      final newArea = danmakuAreaLabels.containsKey(area) ? area : 10;
      if (_danmuArea != newArea) widget.controller.clearDanmaku();
      setState(() {
        _danmuArea = newArea;
        _transparency = transparency.clamp(0, 90);
        _danmuBlockWeight = weight ?? 6;
        _danmuFontSize = (fontSize ?? 20).toDouble();
        _initDone = true;
      });
      widget.controller._controller?.updateOption(_option(context.ui));
    } catch (_) {
      // 读取设置失败时使用默认值，保证弹幕仍可展示
      if (!mounted) return;
      setState(() => _initDone = true);
    }
  }

  // 时间变化
  Duration? _lastPushDanmakuTime;

  void _onPosition(Duration pos) {
    // 禁用时不处理
    if (!widget.controller.enabled) return;
    // 没到开始拉取时间时不处理
    if (DateTime.now().isBefore(_beginTime)) return;

    // 拉取弹幕
    // 已有缓存不属于当前分P或当前时间分块时重新拉取
    final index =
        (pos.inSeconds / danmakuChunkIntervalDuration.inSeconds).toInt() + 1;
    final failCooldown =
        _lastPullFailTime != null &&
        DateTime.now().difference(_lastPullFailTime!).inSeconds < 5;
    final needPull =
        !_pullDanmaku &&
        !failCooldown &&
        (_danmakuCache == null ||
            widget.cid != _danmakuCache!.$1 ||
            index != _danmakuCache!.$2);
    if (needPull) _onPullDanmaku(index);

    if (_danmakuCache == null) return;

    // 筛选出这个时间段没有推送的弹幕进行推送
    final lastPushMS = _lastPushDanmakuTime == null
        ? pos.inMilliseconds
        : _lastPushDanmakuTime!.inMilliseconds;
    _lastPushDanmakuTime = pos;
    final needPushDanmakuList = _danmakuCache!.$3.elems.where((e) {
      // 屏蔽权重
      if (e.weight <= _danmuBlockWeight) return false;
      return lastPushMS <= e.progress && e.progress < pos.inMilliseconds;
    }).toList();
    if (needPushDanmakuList.isEmpty) return;
    _onPushDanmaku(needPushDanmakuList);
  }

  // 拉取弹幕
  Future<void> _onPullDanmaku(int index) async {
    if (_pullDanmaku) return;
    _pullDanmaku = true;

    // 请求前捕获cid，分P切换后旧分P的在途请求返回的数据不会被新分P使用
    final cid = widget.cid;
    try {
      final danmakuResp = await _requests.run(
        () => getDanmaku(cid, index),
        replace: true,
      );
      if (!mounted || widget.cid != cid) return;
      _danmakuCache = (cid, index, danmakuResp);
    } catch (_) {
      // 拉取失败时保留旧缓存并进入冷却，等待后续重试
      _lastPullFailTime = DateTime.now();
    } finally {
      _pullDanmaku = false;
    }
  }

  // 推送弹幕

  void _onPushDanmaku(List<DanmakuElem> danmakuList) {
    for (var e in danmakuList) {
      final color = Color(0xFF000000 | e.color);

      switch (e.mode) {
        case 4: // 底部弹幕
          widget.controller.addDanmaku(
            DanmakuContentItem(
              e.content,
              color: color,
              type: DanmakuItemType.bottom,
            ),
          );
          break;
        case 5: // 顶部弹幕
          widget.controller.addDanmaku(
            DanmakuContentItem(
              e.content,
              color: color,
              type: DanmakuItemType.top,
            ),
          );
          break;
        // case 6: // 逆向弹幕
        //   final y = _random.nextDouble() / 2;
        //   widget.controller.addDanmaku(
        //     SpecialDanmakuContentItem(
        //       e.content,
        //       color: color,
        //       fontSize: 20,
        //       translateXTween: Tween<double>(begin: -0.5, end: 1),
        //       translateYTween: Tween<double>(begin: y, end: y),
        //       duration: Duration(seconds: 15).inMilliseconds,
        //     ),
        //   );
        //   break;
        default: // 1,2,3 普通弹幕 + 6 逆向弹幕 + 其他
          widget.controller.addDanmaku(
            DanmakuContentItem(e.content, color: color),
          );
      }
    }
  }

  // 播放状态变化
  void _onPlayingChanged(bool playing) {
    if (playing) {
      widget.controller.resume();
    } else {
      widget.controller.pause();
    }
  }

  // 禁用状态变化
  void _onEnableChanged() {
    final enable = widget.controller.enableNotifier.value;
    if (!enable) {
      _onClear();
      _danmakuCache = null;
      widget.controller._controller = null;
    }
    // Clearing content alone leaves the package's periodic repaint timer alive.
    // Unmount the canvas completely while disabled, so native video can play
    // without continual Flutter/platform-view composition work.
    if (mounted) setState(() {});
  }

  void _onClear() {
    widget.controller.clearDanmaku();
    _lastPushDanmakuTime = null;
  }

  DateTime _beginTime = DateTime.now();

  void _onWait(Duration duration) {
    _beginTime = DateTime.now().add(duration);
  }

  DanmakuOption _option(double ui) => DanmakuOption(
    fontSize: _danmuFontSize * ui,
    opacity: 1 - _transparency / 100,
  );

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    if (!_initDone || !widget.controller.enabled) {
      return const SizedBox();
    }
    // Size the entire canvas so fixed bottom comments also stay in the chosen region.
    return RepaintBoundary(
      child: Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          widthFactor: 1,
          heightFactor: _danmuArea / 100,
          child: ClipRect(
            child: DanmakuScreen(
              createdController: (c) => widget.controller._controller = c,
              option: _option(ui),
            ),
          ),
        ),
      ),
    );
  }
}
