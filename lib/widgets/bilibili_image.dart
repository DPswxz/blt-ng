import 'dart:async';
import 'package:blt/apis/bilibili/client.dart' show bilibiliHttpClient;
import 'package:blt/utils/image_transport.dart';
import 'package:blt/consts/assets.dart';
import 'package:blt/consts/bilibili.dart' show coverSizeRatio;
import 'package:blt/utils/log.dart';
import 'package:cached_network_image/cached_network_image.dart'
    show
        CachedNetworkImage,
        CachedNetworkImageProvider,
        LoadingErrorWidgetBuilder,
        PlaceholderWidgetBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

final _log = log('image');

// A single bounded disk cache and a small download pool prevent page-switch bursts.
class _BilibiliCacheManager extends CacheManager with ImageCacheManager {
  _BilibiliCacheManager()
    : super(
        Config(
          'libCachedImageData',
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 160,
          fileService: BilibiliImageFileService(),
        ),
      );
}

final bilibiliImageCache = _BilibiliCacheManager();

int imageDecodeWidth(double logicalWidth, double devicePixelRatio) {
  final width = (logicalWidth * devicePixelRatio).ceil();
  return ((width.clamp(128, 960) + 63) ~/ 64) * 64;
}

String thumbnailUrl(String url, int width) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !uri.host.endsWith('.hdslb.com') ||
      uri.path.contains('@') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return url;
  }
  return '$url@${width}w.webp';
}

class BilibiliNetworkImageProvider extends CachedNetworkImageProvider {
  BilibiliNetworkImageProvider(String url)
    : super(
        thumbnailUrl(url, 192),
        maxWidth: 192,
        cacheManager: bilibiliImageCache,
        headers: bilibiliHttpClient.options.headers.cast<String, String>(),
      );
}

class BilibiliNetworkImage extends StatefulWidget {
  final String url;
  final PlaceholderWidgetBuilder? placeholder;
  final LoadingErrorWidgetBuilder? errorWidget;
  const BilibiliNetworkImage(
    this.url, {
    super.key,
    this.placeholder,
    this.errorWidget,
  });
  @override
  State<BilibiliNetworkImage> createState() => _BilibiliNetworkImageState();
}

class _BilibiliNetworkImageState extends State<BilibiliNetworkImage>
    with WidgetsBindingObserver {
  Timer? _retryTimer;
  int _attempt = 0;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(BilibiliNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _retryTimer?.cancel();
      _attempt = 0;
      _failed = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _failed && mounted) {
      _retryTimer?.cancel();
      setState(() {
        _attempt++;
        _failed = false;
      });
    }
  }

  Widget _error(BuildContext context, String url, Object error) {
    _failed = true;
    if (_attempt < 2 && !(_retryTimer?.isActive ?? false)) {
      _retryTimer = Timer(Duration(seconds: _attempt == 0 ? 3 : 12), () {
        if (mounted) {
          setState(() {
            _attempt++;
            _failed = false;
          });
        }
      });
    }
    return (widget.errorWidget ?? _defaultErrorWidget)(context, url, error);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = imageDecodeWidth(
        constraints.hasBoundedWidth ? constraints.maxWidth : 640,
        MediaQuery.devicePixelRatioOf(context),
      );
      return CachedNetworkImage(
        key: ValueKey('${widget.url}:$_attempt'),
        imageUrl: thumbnailUrl(widget.url, width),
        cacheManager: bilibiliImageCache,
        memCacheWidth: width,
        maxWidthDiskCache: width,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        httpHeaders: bilibiliHttpClient.options.headers.cast<String, String>(),
        placeholder: widget.placeholder ?? _defaultPlaceholder,
        errorWidget: _error,
      );
    },
  );
  static Widget _defaultPlaceholder(BuildContext context, String url) =>
      ColoredBox(color: Colors.black.withValues(alpha: 0.04));
  static Widget _defaultErrorWidget(
    BuildContext context,
    String url,
    Object error,
  ) {
    _log.w('图片加载失败 (${error.runtimeType})');
    return ColoredBox(color: Colors.black.withValues(alpha: 0.04));
  }
}

// bilibili媒体缩略图，固定了纵横比
class BilibiliMediaThumbnail extends StatelessWidget {
  final String url;

  const BilibiliMediaThumbnail(this.url, {super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: coverSizeRatio,
      child: BilibiliNetworkImage(url),
    );
  }
}

// bilibili头像，带上了header和默认头像
class BilibiliAvatar extends CircleAvatar {
  BilibiliAvatar(
    String? url, {
    super.key,
    super.radius,
    void Function(Object, StackTrace?)? onError,
  }) : super(
         backgroundImage: AssetImage(Images.noface),
         foregroundImage: url == null
             ? null
             : ResizeImage(BilibiliNetworkImageProvider(url), width: 192),
         onForegroundImageError: url == null
             ? null
             : (onError ?? _defaultAvatarError),
       );

  static void _defaultAvatarError(Object error, StackTrace? stackTrace) {
    _log.w('头像加载失败 (${error.runtimeType})');
  }
}
