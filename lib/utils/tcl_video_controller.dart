import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// A native SurfaceView/Media3 path, with the previous mpv path available for diagnostics.
class TclVideoController {
  final bool isExo;
  late final PlatformPlayer player;
  VideoController? _mpv;
  TclVideoController(String mode) : isExo = mode == 'auto' || mode == 'exo' {
    if (isExo) {
      player = TclExoPlayer();
    } else {
      final owner = Player(
        configuration: const PlayerConfiguration(logLevel: MPVLogLevel.info),
      );
      player = owner.platform!;
      _mpv = VideoController(
        owner,
        configuration: VideoControllerConfiguration(
          vo: mode == 'native' ? 'mediacodec_embed' : 'gpu',
          hwdec: mode == 'software'
              ? 'no'
              : mode == 'copy'
              ? 'mediacodec-copy'
              : 'mediacodec',
          enableHardwareAcceleration: mode != 'software',
        ),
      );
    }
  }
  Future<void> get ready async {
    if (isExo) {
      await (player as TclExoPlayer).ready.future;
    } else {
      await _mpv!.platform.future;
    }
  }

  Future<void> openDash(
    String video,
    String? audio,
    Map<String, String> headers,
    Duration? start,
  ) async {
    if (isExo) {
      await (player as TclExoPlayer).openDash(video, audio, headers, start);
    } else {
      await player.open(Media(video, httpHeaders: headers, start: start));
      if (audio != null && audio.isNotEmpty) {
        await player.setAudioTrack(AudioTrack.uri(audio));
      }
    }
  }

  Widget video(BoxFit fit) {
    if (!isExo) {
      return Video(controller: _mpv!, controls: NoVideoControls, fit: fit);
    }
    final exo = player as TclExoPlayer;
    exo.setAspect(fit).ignore();
    return PlatformViewLink(
      viewType: 'blt/media3',
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      ),
      onCreatePlatformView: (params) =>
          PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: 'blt/media3',
              layoutDirection: TextDirection.ltr,
              creationParams: const {},
              creationParamsCodec: const StandardMessageCodec(),
            )
            ..addOnPlatformViewCreatedListener((id) {
              exo.attach(id);
              params.onPlatformViewCreated(id);
            })
            ..create(),
    );
  }
}

class TclExoPlayer extends PlatformPlayer {
  TclExoPlayer() : super(configuration: const PlayerConfiguration());
  final ready = Completer<void>();
  MethodChannel? _channel;
  StreamSubscription<dynamic>? _events;
  bool _disposed = false;
  String? _video;
  Map<String, String> _headers = {};
  void attach(int id) {
    if (_disposed) return;
    _events?.cancel().ignore();
    _channel = MethodChannel('blt/media3/$id');
    _events = EventChannel('blt/media3/$id/events')
        .receiveBroadcastStream()
        .listen(
          (event) {
            if (_disposed || event is! Map) return;
            if (event['error'] != null) {
              errorController.add(event['error'] as String);
              return;
            }
            if (event['log'] != null) {
              logController.add(
                PlayerLog(
                  prefix: 'media3',
                  level: 'info',
                  text: event['log'] as String,
                ),
              );
            }
            if (!event.containsKey('position')) return;
            final previous = state;
            state = state.copyWith(
              position: Duration(
                milliseconds: (event['position'] as num).toInt(),
              ),
              duration: Duration(
                milliseconds: (event['duration'] as num).toInt(),
              ),
              buffer: Duration(milliseconds: (event['buffer'] as num).toInt()),
              playing: event['playing'] as bool,
              buffering: event['buffering'] as bool,
              completed: event['completed'] as bool,
            );
            if (previous.position != state.position) {
              positionController.add(state.position);
            }
            if (previous.duration != state.duration) {
              durationController.add(state.duration);
            }
            if (previous.buffer != state.buffer) {
              bufferController.add(state.buffer);
            }
            if (previous.playing != state.playing) {
              playingController.add(state.playing);
            }
            if (previous.buffering != state.buffering) {
              bufferingController.add(state.buffering);
            }
            if (previous.completed != state.completed) {
              completedController.add(state.completed);
            }
          },
          onError: (Object error) {
            if (!_disposed) errorController.add('原生播放器连接失败');
          },
        );
    if (!ready.isCompleted) ready.complete();
  }

  Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    await ready.future;
    if (!_disposed) await _channel!.invokeMethod<void>(method, args);
  }

  Future<void> openDash(
    String video,
    String? audio,
    Map<String, String> headers,
    Duration? start,
  ) async {
    _video = video;
    _headers = Map.of(headers);
    await _invoke('open', {
      'video': video,
      'audio': audio,
      'headers': headers,
      'start': start?.inMilliseconds ?? 0,
    });
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    if (_video == null) return;
    final playing = state.playing;
    await openDash(_video!, track.id, _headers, state.position);
    if (!playing) await pause();
  }

  Future<void> metrics() => _invoke('metrics');
  Future<void> setAspect(BoxFit fit) => _invoke('aspect', {
    'value': fit == BoxFit.cover
        ? 'cover'
        : fit == BoxFit.fill
        ? 'fill'
        : 'fit',
  });
  @override
  Future<void> play() => _invoke('playing', {'value': true});
  @override
  Future<void> pause() => _invoke('playing', {'value': false});
  @override
  Future<void> playOrPause() => state.playing ? pause() : play();
  @override
  Future<void> seek(Duration duration) =>
      _invoke('seek', {'position': duration.inMilliseconds});
  @override
  Future<void> setRate(double rate) => _invoke('rate', {'value': rate});
  @override
  Future<void> setPlaylistMode(PlaylistMode playlistMode) =>
      _invoke('loop', {'value': playlistMode == PlaylistMode.single});
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!ready.isCompleted) ready.complete();
    await _events?.cancel();
    try {
      await _channel?.invokeMethod<void>('release');
    } on PlatformException {
      // The platform view may already have released the native player.
    } on MissingPluginException {
      // The platform view may already have released the native player.
    } finally {
      await super.dispose();
    }
  }
}
