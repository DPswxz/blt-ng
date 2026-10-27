import 'package:blt/utils/playback_completion.dart';
import 'package:blt/widgets/playback_completed.dart';
import 'package:blt/utils/request_scope.dart';
import 'package:blt/widgets/danmaku_settings.dart';
import 'dart:async';
import 'package:blt/utils/playback_policy.dart';
import 'package:blt/utils/log.dart';

import 'package:blt/apis/bilibili/client.dart' show bilibiliHttpClient;
import 'package:blt/apis/bilibili/history.dart';
import 'package:blt/apis/bilibili/media.dart'
    show
        getVideoPlayURL,
        GetVideoPlayURLResponse,
        Quality,
        DashData,
        DashMediaData;
import 'package:blt/consts/settings.dart';
import 'package:blt/icons/iconfont.dart';
import 'package:blt/models/video.dart' as model;
import 'package:blt/storages/auth.dart';
import 'package:blt/storages/settings.dart';
import 'package:blt/utils/stream.dart';
import 'package:blt/widgets/bilibili_danmaku_wall.dart';
import 'package:blt/widgets/focus_progress_bar.dart';
import 'package:blt/widgets/loading.dart';
import 'package:blt/widgets/player_controls.dart';
import 'package:blt/widgets/tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:blt/utils/tcl_video_controller.dart';

const _step = Duration(seconds: 5);
const _danmakuWaitDuration = Duration(seconds: 5);

// 视频播放页
class VideoPlayerPage extends StatefulWidget {
  final model.Video video;
  final int cid;

  final String decoderMode;
  final Duration? initialPosition;
  final bool recoveredNative;
  final bool danmu;
  final bool ha;
  final VideoOutputDrivers vo;
  final HardwareVideoDecoder hwdec;

  const VideoPlayerPage({
    super.key,
    required this.video,
    required this.cid,
    this.decoderMode = 'auto',
    this.initialPosition,
    this.recoveredNative = false,
    required this.danmu,
    required this.ha,
    required this.vo,
    required this.hwdec,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final _videoRequests = RequestScope();
  late final ValueNotifier<int> _currentCid;
  late GetVideoPlayURLResponse _videoPlayURLInfo;
  late final ValueNotifier<Quality?> _currentQuality;
  late int _playingCid; // 当前实际播放的分P，用于进度上报，避免与_currentCid错配

  int _avidForCid(int cid) =>
      widget.video.episodes.where((e) => e.cid == cid).firstOrNull?.aid ??
      widget.video.avid;
  int get _playingAvid => _avidForCid(_playingCid);

  late final TclVideoController _controller;
  late final BilibiliDanmakuWallController _danmakuCtl;

  late final FocusNode _screenFocusNode;
  late final ValueNotifier<bool> _displayControl;
  late final ValueNotifier<bool> _panelVisible; // 右侧设置面板是否展开
  late final ValueNotifier<double> _playbackRate;
  late final ValueNotifier<PlayerAspectMode> _aspectMode;
  late final ValueNotifier<PlayerLoopMode> _loopMode;

  bool get _directOutput =>
      widget.decoderMode == 'auto' || widget.decoderMode == 'native';
  String get _hwdec => widget.decoderMode == 'software'
      ? 'no'
      : widget.decoderMode == 'copy'
      ? 'mediacodec-copy'
      : 'mediacodec';
  int _defaultQuality = 80;
  int _preferredCodec = 0;
  StreamSubscription<PlayerLog>? _metricsSub;
  Timer? _codecRecoveryTimer;
  Timer? _telemetryTimer;
  Timer? _heartbeatTimer; // 播放心跳timer
  late final StreamController<bool> loading;

  // memoize合并流，避免rebuild时StreamBuilder对单订阅loading流重新订阅
  late final Stream<bool> _bufferingOrLoading = combineBoolStream(
    _controller.player.stream.buffering,
    loading.stream,
  );
  late final PlaybackCompletionController _completion;
  bool _suppressCompletionKeyUp = false;
  bool _initialPositionConsumed = false;
  StreamSubscription<String>? _errorSub;
  final _videoReady = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _currentCid = ValueNotifier(widget.cid);
    _currentCid.addListener(_onEpisodeChanged);
    _playingCid = widget.cid;
    _controller = TclVideoController(widget.decoderMode);
    _metricsSub = _controller.player.stream.log.listen((event) {
      if (event.prefix == 'media3' || event.text.startsWith('BLT_METRICS ')) {
        log('playback').i(event.text.trim());
        _acceptMetrics(event.text);
      }
    });
    _errorSub = _controller.player.stream.error.listen(_onPlayError);
    _danmakuCtl = BilibiliDanmakuWallController(widget.danmu);
    _screenFocusNode = FocusNode();
    _displayControl = ValueNotifier(false);
    _displayControl.addListener(_onDisplayControlChanged);
    _panelVisible = ValueNotifier(false);
    _currentQuality = ValueNotifier(null);
    _playbackRate = ValueNotifier(1);
    _aspectMode = ValueNotifier(PlayerAspectMode.fit);
    _loopMode = ValueNotifier(PlayerLoopMode.none);
    _completion = PlaybackCompletionController(
      completed: _controller.player.stream.completed,
      shouldShow: () =>
          mounted &&
          _videoReady.value &&
          _loopMode.value == PlayerLoopMode.none,
      onCompleted: _onPlayCompleted,
      seek: (position) async {
        _danmakuCtl.wait(_danmakuWaitDuration);
        _danmakuCtl.clear();
        await _controller.player.seek(position);
      },
      play: () => _controller.player.play(),
    );
    loading = StreamController<bool>();
    _loadPlayerSettings().ignore();
    _onEpisodeChanged();
    _telemetryTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _logDecoderState().ignore(),
    );
  }

  @override
  void dispose() {
    _videoRequests.dispose();
    _codecRecoveryTimer?.cancel();
    _metricsSub?.cancel();
    _telemetryTimer?.cancel();
    if (_heartbeatTimer != null) _heartbeatTimer!.cancel();
    _completion.dispose();
    _errorSub?.cancel();
    if (!loading.isClosed) loading.close();
    _displayControl.removeListener(_onDisplayControlChanged);
    _displayControl.dispose();
    _panelVisible.dispose();
    _currentQuality.dispose();
    _playbackRate.dispose();
    _aspectMode.dispose();
    _loopMode.dispose();
    _videoReady.dispose();
    _screenFocusNode.dispose();
    _danmakuCtl.dispose();
    _controller.player.dispose();
    _currentCid.dispose();
    super.dispose();
  }

  // 读取播放参数（倍速/画面比例/循环播放）并应用到播放器
  Future<void> _loadPlayerSettings() async {
    try {
      final rate = double.tryParse(
        await Settings.getString(Settings.pathPlaybackRateSwitch) ?? '',
      );
      if (!mounted) return;
      if (rate != null && playerPlaybackRates.contains(rate)) {
        _playbackRate.value = rate;
      }
      final aspect = PlayerAspectMode.parse(
        await Settings.getString(Settings.pathAspectModeSwitch),
      );
      if (!mounted) return;
      if (aspect != null) _aspectMode.value = aspect;
      final loop = PlayerLoopMode.parse(
        await Settings.getString(Settings.pathLoopModeSwitch),
      );
      if (!mounted) return;
      if (loop != null) _loopMode.value = loop;
    } catch (_) {
      // 读取失败时使用默认值
    }
    if (!mounted) return;
    await _controller.player.setRate(_playbackRate.value);
    if (!mounted) return;
    await _controller.player.setPlaylistMode(_toPlaylistMode(_loopMode.value));
  }

  PlaylistMode _toPlaylistMode(PlayerLoopMode mode) {
    return mode == PlayerLoopMode.single
        ? PlaylistMode.single
        : PlaylistMode.none;
  }

  void _onDisplayControlChanged() {
    if (_displayControl.value) {
      return;
    }
    // 控制层隐藏时设置面板一并收起
    _panelVisible.value = false;
    _screenFocusNode.requestFocus();
  }

  void _onPlayError(String err) {
    if (!mounted) return;
    if (_controller.isExo) {
      log('playback').w(err);
      _recoverExo().ignore();
      return;
    }
    if (isCodecError(err)) {
      log(
        'playback',
      ).w('codec initialization error; mode=${widget.decoderMode}');
      if (_directOutput && !_recovering) {
        // MediaCodec may report a transient initialization failure while the
        // texture surface is being attached. Allow the plugin to reinitialize vid.
        _codecRecoveryTimer?.cancel();
        final position = _controller.player.state.position;
        _codecRecoveryTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          if (_controller.player.state.position >
              position + const Duration(milliseconds: 500)) {
            log(
              'playback',
            ).i('Native playback progressed after surface initialization');
            return;
          }
          if (_recoveryBudget > 0) _recoverCodec().ignore();
        });
        return;
      }
      if (_recovering) {
        _pendingCodecError = true;
      } else if (_recoveryBudget > 0) {
        _recoverCodec().ignore();
      }
      return;
    }
    // 视频源失败：仅在"无法打开"类错误时轮换到下一个备份地址，其他错误直接提示
    if (_videoUrls.isNotEmpty && err.contains(_videoUrls.first)) {
      if (!err.contains('Can not open external file')) {
        pushTooltipError(context, '视频加载失败');
        return;
      }
      _videoUrls.removeAt(0);
      if (_videoUrls.isEmpty) {
        pushTooltipError(context, '视频加载失败');
        return;
      }
      _restartPlayback().ignore();
      return;
    }
    // 音频源失败：轮换到下一个备份地址
    if (_audioUrls.isNotEmpty && err.contains(_audioUrls.first)) {
      if (!err.contains('Can not open external file')) {
        pushTooltipError(context, "音频加载失败");
        return;
      }
      _audioUrls.removeAt(0);
      if (_audioUrls.isEmpty) {
        pushTooltipError(context, "音频加载失败");
        return;
      }
      _controller.player
          .setAudioTrack(AudioTrack.uri(_audioUrls.first))
          .ignore();
      return;
    }
    pushTooltipError(context, err);
  }

  Future<void> _recoverExo() async {
    if (!mounted || _recoveryBudget <= 0) return;
    if (_recovering) {
      _pendingCodecError = true;
      return;
    }
    _recovering = true;
    _pendingCodecError = false;
    _recoveryBudget--;
    try {
      if (_streamIndex + 1 < _streamCandidates.length) {
        final next = _streamCandidates[++_streamIndex];
        _videoUrls = [next.baseUrl, ...next.backupUrls];
        log('playback').i('ExoPlayer retry same quality codec=${next.codecId}');
        await _restartPlayback();
      } else if (_videoUrls.length > 1) {
        _videoUrls.removeAt(0);
        await _restartPlayback();
      } else if (!await _lowerAutomaticQuality()) {
        _recoveryBudget = 0;
        if (mounted) pushTooltipError(context, '播放失败，请切换较低画质或其他解码方式');
      }
    } finally {
      _recovering = false;
      if (_pendingCodecError && mounted && _recoveryBudget > 0) {
        scheduleMicrotask(() => _recoverExo().ignore());
      }
    }
  }

  Future<void> _recoverCodec() async {
    if (_recoveryBudget-- <= 0) return;
    _recovering = true;
    _pendingCodecError = false;
    try {
      if (_directOutput) {
        if (!widget.recoveredNative) _replaceDecoder('gpu', recovered: true);
        return;
      }
      if (!_copyFallback) {
        _copyFallback = true;
        await (_controller.player as NativePlayer).setProperty(
          'hwdec',
          'mediacodec-copy',
        );
      } else if (_streamIndex + 1 < _streamCandidates.length) {
        final next = _streamCandidates[++_streamIndex];
        _videoUrls = [next.baseUrl, ...next.backupUrls];
        _copyFallback = false;
        await (_controller.player as NativePlayer).setProperty(
          'hwdec',
          'mediacodec',
        );
      } else {
        if (await _lowerAutomaticQuality()) return;
        _recoveryBudget = 0;
        if (mounted) pushTooltipError(context, '当前画质解码失败，请切换较低画质');
        return;
      }
      await _restartPlayback();
    } finally {
      _recovering = false;
      if (_pendingCodecError && _recoveryBudget > 0 && mounted) {
        scheduleMicrotask(() {
          if (mounted) _recoverCodec().ignore();
        });
      }
    }
  }

  // 切换视频备份地址后重新打开媒体，保留播放进度、弹幕时间轴与音轨
  Future<void> _restartPlayback() async {
    if (_videoUrls.isEmpty) return;
    final start = _controller.player.state.position;
    // 重置弹幕时间轴，避免重开后按旧时间轴推送导致长时间无弹幕
    _danmakuCtl.clear();
    try {
      await _controller.openDash(
        _videoUrls.first,
        _audioUrls.isEmpty ? null : _audioUrls.first,
        bilibiliHttpClient.options.headers.cast<String, String>(),
        start,
      );
      await _controller.player.setRate(_playbackRate.value);
      await _controller.player.setPlaylistMode(
        _toPlaylistMode(_loopMode.value),
      );
    } catch (_) {
      // 打开失败会通过错误流再次触发轮换
    }
  }

  DateTime? _lastBackTime;

  void _onBack(didPop) {
    if (didPop || !mounted) return;

    // 返回键优先收起设置面板
    if (_panelVisible.value) {
      _panelVisible.value = false;
      return;
    }
    if (_displayControl.value) return;

    final now = DateTime.now();
    if (_lastBackTime != null && now.difference(_lastBackTime!).inSeconds < 4) {
      // 上报播放进度
      if (loginInfoNotifier.value.isLogin) {
        reportPlayProgress(
          _playingAvid,
          _playingCid,
          _controller.player.state.position,
        ).ignore();
      }
      return Get.back();
    }
    _lastBackTime = now;

    pushTooltipInfo(
      context,
      '再按一次返回退出播放',
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _onEpisodeChanged() =>
      _videoRequests.run(_loadEpisode, replace: true);

  Future<void> _loadEpisode() async {
    // 快照本次请求的分P，若处理过程中用户又切了分P则丢弃本次结果
    final cid = _currentCid.value;
    final currentAvid = _avidForCid(cid);
    _recoveryBudget = 8;
    // 新分P就绪前禁止画质等操作，避免用到旧分P的播放信息
    _videoReady.value = false;
    // 结束心跳
    _heartbeatTimer?.cancel();
    // 取消待执行的自动下一分P
    _completion.reset();
    // 上报上一分P的播放进度（使用实际播放中的cid，避免切P后cid与位置错配）
    if (loginInfoNotifier.value.isLogin &&
        _controller.player.state.position.inSeconds > 0) {
      reportPlayProgress(
        _playingAvid,
        _playingCid,
        _controller.player.state.position,
      ).ignore();
    }
    reportPlayStart(currentAvid, cid).ignore();
    // 暂停弹幕
    final danmakuEnabled = _danmakuCtl.enabled;
    _danmakuCtl.enabled = false;

    var success = false;
    if (!loading.isClosed) loading.sink.add(true);
    try {
      MediaPlayInfo? playInfo;
      // 若已登陆，获取播放进度
      if (loginInfoNotifier.value.isLogin) {
        try {
          final lastPlayInfo = await getMediaPlayInfo(
            avid: currentAvid,
            cid: cid,
          );
          if (cid == lastPlayInfo.lastPlayCid) {
            playInfo = lastPlayInfo;
          }
        } catch (_) {}
        if (!mounted || cid != _currentCid.value) return;
      }

      final info = await getVideoPlayURL(
        avid: currentAvid,
        cid: cid,
        episodeId: widget.video.episodes
            .where((e) => e.cid == cid)
            .firstOrNull
            ?.episodeId,
      );
      if (!mounted || cid != _currentCid.value) return;
      if (info.supportFormats.isEmpty) {
        throw Exception('该视频暂无可播放清晰度');
      }

      final available = info.supportFormats
          .where((q) => info.dashData.video.any((v) => v.quality == q.id))
          .toList();
      if (available.isEmpty) throw Exception('当前账号没有可播放的视频流，请登录后重试');
      // Each new video starts with the TV's smooth default. Manual 4K affects this video only.
      _defaultQuality =
          await Settings.getInt(Settings.pathDefaultQuality) ?? 80;
      _preferredCodec = await Settings.getInt(Settings.pathPreferredCodec) ?? 0;
      const qualityID = 0;
      _autoQuality = qualityID == 0;
      var quality = available.firstWhere(
        (q) => q.id == qualityID,
        orElse: () => defaultQualityOrder(available, _defaultQuality).isNotEmpty
            ? defaultQualityOrder(available, _defaultQuality).first
            : available.last,
      );
      if (qualityID == 0) {
        final ranked = defaultQualityOrder(available, _defaultQuality);
        if (ranked.isEmpty) throw Exception('该视频没有可用的 1080P 或更低画质，请手动选择');
        for (final candidate in ranked) {
          if ((await compatibleStreams(
            info.dashData.video
                .where((v) => v.quality == candidate.id)
                .toList(),
          )).isNotEmpty) {
            quality = candidate;
            break;
          }
        }
      }
      _videoPlayURLInfo = info;
      // 打开媒体前再校验一次分P未变，避免并发切P时旧请求最后执行覆盖新请求
      if (!mounted || cid != _currentCid.value) return;

      await _playDashMedia(
        info.dashData,
        quality,
        start: !_initialPositionConsumed
            ? widget.initialPosition ?? playInfo?.lastPlayTime
            : playInfo?.lastPlayTime,
      );
      if (!mounted || cid != _currentCid.value) return;

      // 应用用户设置的倍速与循环模式
      await _controller.player.setRate(_playbackRate.value);
      await _controller.player.setPlaylistMode(
        _toPlaylistMode(_loopMode.value),
      );
      if (!mounted || cid != _currentCid.value) return;

      // 播放成功后才提交状态，失败时保持旧画质/旧播放信息不变
      _videoPlayURLInfo = info;
      _currentQuality.value = quality;
      _videoReady.value = true;
      success = true;
      _initialPositionConsumed = true;
      // 开始周期心跳（每15秒上报一次，切P/退出时取消）
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _onHeartbeat(),
      );
    } catch (e) {
      if (mounted) {
        if (isCodecError(e.toString())) {
          _onPlayError(e.toString());
        } else {
          showAppError(context, e);
        }
      }
    } finally {
      if (!loading.isClosed) loading.sink.add(false);
      // 仅当前分P的请求仍有效时恢复弹幕，避免旧请求覆盖新请求的状态
      if (mounted && cid == _currentCid.value) {
        _danmakuCtl.enabled = danmakuEnabled;
        if (success) _playingCid = cid;
      }
    }
  }

  void _onHeartbeat() {
    if (!loginInfoNotifier.value.isLogin) return;
    reportPlayHeartbeat(
      avid: _playingAvid,
      cid: _playingCid,
      progress: _controller.player.state.position,
    ).ignore();
  }

  Future<void> _logDecoderState() async {
    if (!mounted) return;
    final state = _controller.player.state;
    log('playback').i(
      'sample mode=${widget.decoderMode} ready=${_videoReady.value} position=${state.position.inMilliseconds} playing=${state.playing} buffering=${state.buffering} buffered=${state.buffer.inMilliseconds}',
    );
    if (!_videoReady.value) return;
    if (_controller.isExo) {
      await (_controller.player as TclExoPlayer).metrics();
      return;
    }
    // command() uses mpv_command_async. Never synchronously query mpv from
    // Flutter's UI isolate: a native rendering lock can freeze its event loop.
    await (_controller.player as NativePlayer).command([
      'expand-properties',
      'print-text',
      r'BLT_METRICS hw=${hwdec-current} codec=${video-codec} decoderDrops=${decoder-frame-drop-count} renderDrops=${frame-drop-count} buffering=${paused-for-cache} cache=${demuxer-cache-duration}',
    ], waitForInitialization: false);
  }

  void _acceptMetrics(String value) {
    final match = RegExp(
      r'decoderDrops=(\d+) renderDrops=(\d+)',
    ).firstMatch(value);
    if (match == null) return;
    final dropped = int.parse(match[1]!) + int.parse(match[2]!);
    final position = _controller.player.state.position;
    final elapsed = _lastSamplePosition == null
        ? 0
        : (position - _lastSamplePosition!).inSeconds;
    final delta = dropped - _lastDropped;
    _lastSamplePosition = position;
    _lastDropped = dropped;
    if (_autoQuality &&
        elapsed >= 8 &&
        elapsed <= 22 &&
        delta >= 45 &&
        _controller.player.state.playing &&
        !_recovering &&
        !_optimizing) {
      _lowerAutomaticQuality().ignore();
    }
  }

  Future<void> _onQualityChange(Quality sf) async {
    if (!mounted || _currentQuality.value?.id == sf.id) return;
    if (!_videoPlayURLInfo.dashData.video.any((v) => v.quality == sf.id)) {
      pushTooltipInfo(context, '该画质当前无播放权限或视频流，请检查登录与大会员状态');
      return;
    }
    _recoveryBudget = 8;
    // 快照当前分P，切画质期间若用户切换了分P则不恢复弹幕，避免覆盖新分P的状态
    final cid = _currentCid.value;

    // 暂停弹幕
    final danmakuEnabled = _danmakuCtl.enabled;
    _danmakuCtl.enabled = false;

    if (!loading.isClosed) loading.sink.add(true);
    try {
      await _playDashMedia(
        _videoPlayURLInfo.dashData,
        sf,
        start: _controller.player.state.position,
      );
      // 切画质期间用户切换了分P时丢弃结果，避免画质与分P错配
      if (!mounted || cid != _currentCid.value) return;
      // 播放成功后才提交画质
      _currentQuality.value = sf;
    } catch (e) {
      if (mounted) {
        if (isCodecError(e.toString())) {
          _onPlayError(e.toString());
        } else {
          showAppError(context, e);
        }
      }
    } finally {
      if (!loading.isClosed) loading.sink.add(false);
      if (mounted && cid == _currentCid.value) {
        // 恢复弹幕
        _danmakuCtl.enabled = danmakuEnabled;
      }
    }
  }

  List<DashMediaData> _streamCandidates = [];
  int _streamIndex = 0;
  bool _copyFallback = false;
  bool _recovering = false;
  bool _pendingCodecError = false;
  int _recoveryBudget = 8;
  bool _autoQuality = true;
  Quality? _attemptQuality;
  int _lastDropped = 0;
  Duration? _lastSamplePosition;
  bool _optimizing = false;

  Future<bool> _lowerAutomaticQuality() async {
    if (!_autoQuality || _attemptQuality == null || _optimizing || !mounted) {
      return false;
    }
    _optimizing = true;
    try {
      final lower = smoothQualityOrder(
        _videoPlayURLInfo.supportFormats,
      ).where((q) => q.id < _attemptQuality!.id).toList();
      for (final quality in lower) {
        if ((await compatibleStreams(
          _videoPlayURLInfo.dashData.video
              .where((v) => v.quality == quality.id)
              .toList(),
        )).isEmpty) {
          continue;
        }
        final position = _controller.player.state.position;
        await _playDashMedia(
          _videoPlayURLInfo.dashData,
          quality,
          start: position,
        );
        if (!mounted) return false;
        _currentQuality.value = quality;
        _lastSamplePosition = null;
        _lastDropped = 0;
        pushTooltipInfo(context, '已自动调整为 ${_qualityLabel(quality)}，优先流畅播放');
        return true;
      }
      return false;
    } finally {
      _optimizing = false;
    }
  }

  List<String> _videoUrls = [];
  List<String> _audioUrls = [];
  DashMediaData? _currentAudio;

  Future<void> _playDashMedia(
    DashData media,
    Quality quality, {
    Duration? start,
  }) async {
    await _controller.ready.timeout(const Duration(seconds: 15));
    if (!mounted) return;
    _attemptQuality = quality;
    final candidates = await compatibleStreams(
      media.video.where((v) => v.quality == quality.id).toList(),
    );
    if (candidates.isEmpty) throw Exception('电视不支持该画质的编码，请选择较低画质');
    _streamCandidates = candidates;
    _streamIndex = 0;
    _copyFallback = false;
    if (_preferredCodec != 0) {
      candidates.sort(
        (a, b) => (a.codecId == _preferredCodec ? 0 : 1).compareTo(
          b.codecId == _preferredCodec ? 0 : 1,
        ),
      );
    }
    final video = candidates.first;
    log('playback').i(
      'TCL stream q=${quality.id} codec=${video.codecId} ${video.width}x${video.height} fps=${video.fps}; mode=${widget.decoderMode} hwdec=$_hwdec',
    );
    var videoUrls = [
      video.baseUrl,
      ...video.backupUrls,
    ].where((u) => u.isNotEmpty).toList();
    if (videoUrls.isEmpty) {
      throw Exception('该画质无可用视频流');
    }
    final audioTracks = [...media.audio]
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    _currentAudio = audioTracks.isEmpty ? null : audioTracks.first;
    var audioUrls =
        (_currentAudio == null ? <DashMediaData>[] : [_currentAudio!])
            .expand((e) => [e.baseUrl, ...e.backupUrls])
            .where((u) => u.isNotEmpty)
            .toList();

    // 先记录全部候选地址，供_onPlayError在首个地址失败时轮换备份地址
    _videoUrls = videoUrls;
    _audioUrls = audioUrls;

    if (!_controller.isExo) {
      await (_controller.player as NativePlayer).setProperty('hwdec', _hwdec);
    }
    await _controller.openDash(
      videoUrls.first,
      audioUrls.isEmpty ? null : audioUrls.first,
      bilibiliHttpClient.options.headers.cast<String, String>(),
      start,
    );
  }

  void _onPlayCompleted() {
    // 上报播放进度
    if (loginInfoNotifier.value.isLogin) {
      reportPlayProgress(
        _playingAvid,
        _playingCid,
        _controller.player.state.position,
      ).ignore();
    }

    if (!mounted ||
        !_videoReady.value ||
        _loopMode.value == PlayerLoopMode.single) {
      return;
    }
    _displayControl.value = false;
    _panelVisible.value = false;
    _danmakuCtl.clear();
  }

  Future<void> _restartCompletedVideo() async {
    _suppressCompletionKeyUp = HardwareKeyboard.instance.logicalKeysPressed.any(
      (key) =>
          key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select,
    );
    try {
      await _completion.restart();
      if (mounted) _screenFocusNode.requestFocus();
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  // 当前分P下标，-1 表示不在列表中
  int get _currentEpisodeIndex {
    return widget.video.episodes.indexWhere((e) => e.cid == _currentCid.value);
  }

  void _onPrevEpisode() {
    final index = _currentEpisodeIndex;
    if (index <= 0) return;
    _currentCid.value = widget.video.episodes[index - 1].cid;
  }

  void _onNextEpisode() {
    final index = _currentEpisodeIndex;
    final episodes = widget.video.episodes;
    if (index < 0 || index >= episodes.length - 1) return;
    _currentCid.value = episodes[index + 1].cid;
  }

  void _onPlayOrPause() {
    _controller.player.playOrPause();
  }

  void _onSeekPosition(Duration position) {
    _controller.player.seek(position);
    _completion.reset();
    _danmakuCtl.wait(_danmakuWaitDuration);
    _danmakuCtl.clear();
  }

  void _onDanmakuSwitchTapped() {
    _danmakuCtl.enabled = !_danmakuCtl.enabled;
    Settings.setBool(Settings.pathDanmuSwitch, _danmakuCtl.enabled).ignore();
  }

  String _audioLabel(DashMediaData? audio) {
    if (audio == null) return '默认音轨';
    return switch (audio.quality) {
      30216 => 'AAC · 64K',
      30232 => 'AAC · 132K',
      30280 => 'AAC · 192K',
      _ =>
        audio.bandwidth > 0
            ? '${(audio.bandwidth / 1000).round()} kbps'
            : '默认音轨',
    };
  }

  Future<void> _onAudioTapped() async {
    if (!_videoReady.value) return;
    final tracks = _videoPlayURLInfo.dashData.audio;
    if (tracks.length <= 1) {
      pushTooltipInfo(context, '该视频只有一条默认音轨');
      return;
    }
    final selected = await showPlayerPicker<DashMediaData>(
      context: context,
      title: '音轨',
      options: tracks,
      current: _currentAudio ?? tracks.first,
      labelOf: _audioLabel,
    );
    if (!mounted || selected == null || selected == _currentAudio) return;
    try {
      await _controller.player.setAudioTrack(AudioTrack.uri(selected.baseUrl));
      _audioUrls = [selected.baseUrl, ...selected.backupUrls];
      setState(() => _currentAudio = selected);
    } catch (_) {
      if (mounted) pushTooltipError(context, '音轨切换失败，保留原音轨');
    }
  }

  void _replaceDecoder(String mode, {bool recovered = false}) {
    Get.off(
      () => VideoPlayerPage(
        video: widget.video,
        cid: _currentCid.value,
        danmu: _danmakuCtl.enabled,
        ha: widget.ha,
        vo: widget.vo,
        hwdec: widget.hwdec,
        decoderMode: mode,
        initialPosition: _controller.player.state.position,
        recoveredNative: recovered,
      ),
      preventDuplicates: false,
    );
  }

  Future<void> _onDecoderTapped() async {
    final selected = await showPlayerPicker<String>(
      context: context,
      title: '解码方式',
      options: decoderLabels.keys.toList(),
      current: widget.decoderMode,
      labelOf: (v) => decoderLabels[v]!,
    );
    if (!mounted || selected == null || selected == widget.decoderMode) return;
    await Settings.setString(Settings.pathDecoderMode, selected);
    if (mounted) _replaceDecoder(selected);
  }

  Future<void> _onDefaultQualityTapped() async {
    final selected = await showPlayerPicker<int>(
      context: context,
      title: '进入视频默认画质 · 无对应画质时选较低',
      options: defaultQualityLabels.keys.toList(),
      current: _defaultQuality,
      labelOf: (v) => defaultQualityLabels[v]!,
    );
    if (!mounted || selected == null) return;
    await Settings.setInt(Settings.pathDefaultQuality, selected);
    setState(() => _defaultQuality = selected);
  }

  Future<void> _onCodecTapped() async {
    final selected = await showPlayerPicker<int>(
      context: context,
      title: '视频编码偏好 · 不支持时自动回退',
      options: preferredCodecLabels.keys.toList(),
      current: _preferredCodec,
      labelOf: (v) => preferredCodecLabels[v]!,
    );
    if (!mounted || selected == null) return;
    await Settings.setInt(Settings.pathPreferredCodec, selected);
    setState(() => _preferredCodec = selected);
    if (_videoReady.value) {
      await _playDashMedia(
        _videoPlayURLInfo.dashData,
        _currentQuality.value!,
        start: _controller.player.state.position,
      );
    }
  }

  Future<void> _onDanmakuSettingsTapped() => showDanmakuSettings(
    context,
    _danmakuCtl,
    onToggle: _onDanmakuSwitchTapped,
  );

  String _qualityLabel(Quality? quality) {
    if (quality == null) return '--';
    if (quality.description.isEmpty) {
      return {
            120: '4K 超高清',
            116: '1080P 60帧',
            112: '1080P 高码率',
            80: '1080P 高清',
            74: '720P 60帧',
            64: '720P 准高清',
            32: '480P 标清',
            16: '360P 流畅',
          }[quality.id] ??
          '其他画质';
    }
    return quality.description;
  }

  Future<void> _onQualityTapped() async {
    if (!_videoReady.value) return;
    final formats = _videoPlayURLInfo.supportFormats;
    final current = _currentQuality.value;
    if (formats.isEmpty || current == null) return;

    final selected = await showPlayerPicker<Quality>(
      context: context,
      title: '画质·清晰度',
      options: formats,
      current: current,
      labelOf: (q) =>
          _videoPlayURLInfo.dashData.video.any((v) => v.quality == q.id)
          ? '${_qualityLabel(q)}${q.needsVip ? ' · 大会员' : ''}'
          : '${_qualityLabel(q)} · 需登录/会员或暂无流',
    );
    if (!mounted || selected == null) return;
    await Settings.setInt(Settings.pathQualitySwitch, selected.id);
    _autoQuality = false;
    await _onQualityChange(selected);
  }

  Future<void> _onRateTapped() async {
    final selected = await showPlayerPicker<double>(
      context: context,
      title: '播放倍速',
      options: playerPlaybackRates,
      current: _playbackRate.value,
      labelOf: playbackRateString,
    );
    if (!mounted || selected == null) return;
    _playbackRate.value = selected;
    await Settings.setString(Settings.pathPlaybackRateSwitch, '$selected');
    await _controller.player.setRate(selected);
  }

  Future<void> _onAspectTapped() async {
    final selected = await showPlayerPicker<PlayerAspectMode>(
      context: context,
      title: '画面比例',
      options: PlayerAspectMode.values,
      current: _aspectMode.value,
      labelOf: (mode) => mode.description,
    );
    if (!mounted || selected == null) return;
    _aspectMode.value = selected;
    await Settings.setString(Settings.pathAspectModeSwitch, selected.value);
  }

  Future<void> _onLoopTapped() async {
    final selected = await showPlayerPicker<PlayerLoopMode>(
      context: context,
      title: '循环播放',
      options: PlayerLoopMode.values,
      current: _loopMode.value,
      labelOf: (mode) => mode.description,
    );
    if (!mounted || selected == null) return;
    _loopMode.value = selected;
    await Settings.setString(Settings.pathLoopModeSwitch, selected.value);
    if (selected == PlayerLoopMode.single) _completion.reset();
    await _controller.player.setPlaylistMode(_toPlaylistMode(selected));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _onBack(didPop),
      child: Scaffold(
        body: KeyboardListener(
          autofocus: true,
          focusNode: _screenFocusNode,
          onKeyEvent: _onKeyEvent,
          child: Stack(
            children: [
              _buildVideo(),
              StreamBuilder<bool>(
                stream: _bufferingOrLoading,
                builder: (context, buffering) => (buffering.data ?? false)
                    ? buildLoadingStyle3()
                    : const SizedBox(),
              ),
              ValueListenableBuilder(
                valueListenable: _currentCid,
                builder: (context, cid, child) => BilibiliDanmakuWall(
                  controller: _danmakuCtl,
                  cid: cid,
                  timeline: _controller.player.stream.position,
                  playing: _controller.player.stream.playing,
                ),
              ),
              ValueListenableBuilder(
                valueListenable: _displayControl,
                builder: (context, display, _) => ExcludeFocus(
                  excluding: !display,
                  child: Offstage(
                    offstage: !display,
                    child: _buildControlLayer(display),
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: _completion,
                builder: (_, finished, _) => finished
                    ? PlaybackCompletedOverlay(
                        title:
                            widget.video.episodes
                                .where((e) => e.cid == _playingCid)
                                .firstOrNull
                                ?.title ??
                            widget.video.title,
                        onRestart: _restartCompletedVideo,
                        onBack: () => Get.back(),
                        onNext:
                            _currentEpisodeIndex >= 0 &&
                                _currentEpisodeIndex <
                                    widget.video.episodes.length - 1
                            ? _onNextEpisode
                            : null,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 视频画面：按画面比例设置切换填充方式
  Widget _buildVideo() {
    return ValueListenableBuilder<PlayerAspectMode>(
      valueListenable: _aspectMode,
      builder: (context, mode, _) => _controller.video(switch (mode) {
        PlayerAspectMode.fit => BoxFit.contain,
        PlayerAspectMode.fill => BoxFit.fill,
        PlayerAspectMode.cover => BoxFit.cover,
      }),
    );
  }

  Widget _buildControlLayer(bool display) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _currentCid,
        _currentQuality,
        _playbackRate,
        _aspectMode,
        _loopMode,
        _videoReady,
        _danmakuCtl.enableNotifier,
      ]),
      builder: (context, _) => StreamBuilder<bool>(
        stream: _controller.player.stream.playing,
        builder: (context, playing) {
          final playingNow = playing.data ?? _controller.player.state.playing;
          return PlayerControlLayer(
            title: widget.video.title,
            uploader: widget.video.userName,
            avatar: widget.video.userAvatar,
            visible: display,
            panelVisible: _panelVisible,
            progressBar: _buildProgressBar(),
            playing: playingNow,
            actions: _buildBarActions(playingNow),
            panelRows: _buildPanelRows(),
          );
        },
      ),
    );
  }

  Widget _buildProgressBar() {
    return StreamBuilder<Duration>(
      stream: _controller.player.stream.position,
      builder: (context, position) => FocusProgressBar(
        position: position.data ?? _controller.player.state.position,
        duration: _controller.player.state.duration,
        buffered: _controller.player.state.buffer,
        onPositionChanged: _onSeekPosition,
      ),
    );
  }

  List<PlayerBarAction> _buildBarActions(bool playing) {
    final index = _currentEpisodeIndex;
    final episodes = widget.video.episodes;
    final ready = _videoReady.value;
    final danmakuOn = _danmakuCtl.enabled;
    return [
      PlayerBarAction(
        kind: PlayerControlKind.prevEpisode,
        icon: Icons.skip_previous_rounded,
        label: '上一集',
        iconSize: 58,
        enabled: index > 0,
        onSelect: _onPrevEpisode,
      ),
      PlayerBarAction(
        kind: PlayerControlKind.playPause,
        icon: Icons.play_arrow_rounded,
        label: playing ? '暂停' : '播放',
        primary: true,
        onSelect: _onPlayOrPause,
      ),
      PlayerBarAction(
        kind: PlayerControlKind.nextEpisode,
        icon: Icons.skip_next_rounded,
        label: '下一集',
        iconSize: 58,
        enabled: index >= 0 && index < episodes.length - 1,
        onSelect: _onNextEpisode,
      ),
      PlayerBarAction(
        kind: PlayerControlKind.quality,
        icon: Icons.high_quality_outlined,
        label: '清晰度',
        value: ready ? _qualityLabel(_currentQuality.value) : '--',
        enabled: ready,
        dividerBefore: true,
        onSelect: _onQualityTapped,
      ),
      PlayerBarAction(
        kind: PlayerControlKind.rate,
        icon: Icons.speed_rounded,
        label: '倍速',
        value: playbackRateString(_playbackRate.value),
        onSelect: _onRateTapped,
      ),
      PlayerBarAction(
        kind: PlayerControlKind.audio,
        icon: Icons.music_note_rounded,
        label: '音轨',
        value: _audioLabel(_currentAudio),
        onSelect: _onAudioTapped,
      ),
      PlayerBarAction(
        kind: PlayerControlKind.danmaku,
        icon: danmakuOn ? IconFont.danmukai : IconFont.danmuguanbi,
        label: '弹幕设置',
        value: danmakuOn ? '开' : '关',
        onSelect: _onDanmakuSettingsTapped,
      ),
      PlayerBarAction(
        kind: PlayerControlKind.aspect,
        icon: Icons.aspect_ratio_rounded,
        label: '画面比例',
        value: _aspectMode.value.description,
        dividerBefore: true,
        onSelect: _onAspectTapped,
      ),
      PlayerBarAction(
        kind: PlayerControlKind.loop,
        icon: Icons.loop_rounded,
        label: '循环播放',
        value: _loopMode.value.description,
        onSelect: _onLoopTapped,
      ),
      PlayerBarAction(
        kind: PlayerControlKind.moreSettings,
        icon: Icons.more_horiz_rounded,
        label: '更多设置',
        onSelect: () => _panelVisible.value = true,
      ),
    ];
  }

  List<PlayerPanelRow> _buildPanelRows() {
    final ready = _videoReady.value;
    return [
      PlayerPanelRow.item(
        kind: PlayerControlKind.quality,
        icon: Icons.high_quality_outlined,
        label: '画质·清晰度',
        value: ready ? _qualityLabel(_currentQuality.value) : '--',
        enabled: ready,
        onSelect: _onQualityTapped,
      ),
      PlayerPanelRow.item(
        kind: PlayerControlKind.aspect,
        icon: Icons.aspect_ratio_rounded,
        label: '画面比例',
        value: _aspectMode.value.description,
        onSelect: _onAspectTapped,
      ),
      PlayerPanelRow.item(
        kind: PlayerControlKind.loop,
        icon: Icons.loop_rounded,
        label: '循环播放',
        value: _loopMode.value.description,
        onSelect: _onLoopTapped,
      ),
      const PlayerPanelRow.divider(),
      PlayerPanelRow.item(
        kind: PlayerControlKind.defaultQuality,
        icon: Icons.high_quality,
        label: '进入视频默认画质',
        value: defaultQualityLabels[_defaultQuality],
        onSelect: _onDefaultQualityTapped,
      ),
      PlayerPanelRow.item(
        kind: PlayerControlKind.decoder,
        icon: Icons.memory,
        label: '解码方式',
        value: decoderLabels[widget.decoderMode],
        onSelect: _onDecoderTapped,
      ),
      PlayerPanelRow.item(
        kind: PlayerControlKind.codec,
        icon: Icons.tune,
        label: '视频编码偏好',
        value: preferredCodecLabels[_preferredCodec],
        onSelect: _onCodecTapped,
      ),
    ];
  }

  void _onKeyEvent(KeyEvent value) {
    if (_suppressCompletionKeyUp &&
        value is KeyUpEvent &&
        (value.logicalKey == LogicalKeyboardKey.enter ||
            value.logicalKey == LogicalKeyboardKey.select)) {
      _suppressCompletionKeyUp = false;
      return;
    }
    if (_completion.value) return;
    if (!_displayControl.value) {
      if (value is KeyDownEvent || value is KeyRepeatEvent) {
        switch (value.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            _onStepForward(false);
            break;
          case LogicalKeyboardKey.arrowRight:
            _onStepForward(true);
            break;
        }
      }
    }

    if (value is! KeyUpEvent) {
      return;
    }

    if (_displayControl.value) {
      switch (value.logicalKey) {
        case LogicalKeyboardKey.goBack:
          // 面板展开时返回键只收面板，控制层保持显示
          final panelWasOpen = _panelVisible.value;
          // 延迟一帧后再隐藏控制层：确保PopScope的_onBack先被调用，
          // 这样_onBack里才能拿到此时的displayControl.value（true），
          // 从而仅关闭控制层而不是退出播放页
          Future.delayed(const Duration(milliseconds: 10)).then((_) {
            if (!mounted || panelWasOpen) return;
            _displayControl.value = false;
          });
          break;
        case LogicalKeyboardKey.contextMenu:
          _displayControl.value = false;
          break;
      }
      return;
    }

    switch (value.logicalKey) {
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
        // 仅当没有控件持有焦点时才由页面接管播放/暂停，
        // 避免与控件自身的激活（ActivateIntent）重复触发
        if (FocusManager.instance.primaryFocus != _screenFocusNode) {
          break;
        }
        _controller.player.playOrPause();
        break;
      case LogicalKeyboardKey.contextMenu:
        _displayControl.value = true;
        break;
    }
  }

  void _onStepForward(bool forward) {
    _completion.reset();
    if (forward) {
      if (_controller.player.state.duration -
              _controller.player.state.position <
          _step) {
        _controller.player.seek(_controller.player.state.duration);
      } else {
        _controller.player.seek(_controller.player.state.position + _step);
      }
    } else {
      if (_controller.player.state.position < _step) {
        _controller.player.seek(Duration(seconds: 0));
      } else {
        _controller.player.seek(_controller.player.state.position - _step);
      }
    }
    _danmakuCtl.wait(_danmakuWaitDuration);
    _danmakuCtl.clear();
  }
}
