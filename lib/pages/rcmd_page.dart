import 'package:bilitv/apis/bilibili/media.dart' show getVideoInfo;
import 'package:bilitv/apis/bilibili/rcmd.dart';
import 'package:bilitv/models/video.dart' show MediaCardInfo;
import 'package:bilitv/pages/video_detail.dart';
import 'package:bilitv/widgets/loading.dart';
import 'package:bilitv/widgets/video_card.dart';
import 'package:bilitv/apis/bilibili/client.dart' show bilibiliHttpClient;
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';

class RecommendPage extends StatefulWidget {
  const RecommendPage({super.key});

  @override
  State<RecommendPage> createState() => _RecommendPageState();
}

class _RecommendPageState extends State<RecommendPage> {
  final ScrollController _videoScrollController = ScrollController();

  int page = 0;
  final pageVideoCount = 30;
  List<MediaCardInfo> _videos = [];
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _onRefresh();
    _videoScrollController.addListener(_onListenScroll);
  }

  @override
  void dispose() {
    _videoScrollController.dispose();
    super.dispose();
  }

  // Simple debounce to avoid multiple rapid loads when user hits the edge
  DateTime? _lastLoad;
  void _onListenScroll() {
    if (!_videoScrollController.position.atEdge ||
        _videoScrollController.position.pixels == 0) {
      return;
    }

    final now = DateTime.now();
    if (_lastLoad != null && now.difference(_lastLoad!).inMilliseconds < 500) {
      return;
    }
    _lastLoad = now;

    // Prevent concurrent load-more requests
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    _onRefresh();
    // reset flag when done (in _onRefresh completion handlers)
  }

  void _onRefresh() {
    page++;

    if (_videos.isEmpty) {
      _isLoading.value = true;

      // The following block captures BuildContext and uses it with precacheImage after awaits.
      // We ensure mounted checks and accept the small risk; suppress the lint for this block.
      // ignore: use_build_context_synchronously
      fetchRecommendVideos(page: page, count: pageVideoCount).then((videos) async {
          // Preload images without using BuildContext to avoid async-context lint
        Future<void> preloadImage(ImageProvider provider) {
          final completer = Completer<void>();
          final stream = provider.resolve(const ImageConfiguration());
          late ImageStreamListener listener;
          listener = ImageStreamListener((_, __) {
            completer.complete();
            stream.removeListener(listener);
          }, onError: (_, __) {
            completer.complete();
            stream.removeListener(listener);
          });
          stream.addListener(listener);
          return completer.future;
        }

        final first = videos.take(6).toList();
        try {
          await Future.wait(first.map((v) => preloadImage(CachedNetworkImageProvider(
                v.cover,
                headers: bilibiliHttpClient.options.headers.cast<String, String>(),
              ))));
        } catch (_) {}

        // background preload remaining images (fire-and-forget)
        for (var v in videos.skip(6)) {
          preloadImage(CachedNetworkImageProvider(
            v.cover,
            headers: bilibiliHttpClient.options.headers.cast<String, String>(),
          ));
        }

        if (!mounted) return;
        _videos = videos;
        _isLoading.value = false;
      });
      return;
    }

    fetchRecommendVideos(
      page: page,
      count: pageVideoCount,
      removeAvids: _videos.map((e) => e.avid).toList(),
    ).then((videos) {
      setState(() {
        _videos.addAll(videos);
        _isLoadingMore = false;
      });
    });
  }

  void _onVideoTapped(MediaCardInfo video) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => LoadingWidget(
          loader: () async {
            final v = await getVideoInfo(avid: video.avid);
            final relatedVs = await fetchRelatedVideos(avid: video.avid);
            return VideoDetailPageInput(v, relatedVs);
          },
          builder: (context, input) {
            return VideoDetailPage(
              video: input.video,
              relatedVideos: input.relatedVideos,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isLoading,
      builder: (context, isLoading, _) {
        if (isLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.pink[500]!),
                ),
                const SizedBox(height: 16),
                const Text(
                  '加载中...',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(16),
          child: GridView.builder(
            controller: _videoScrollController,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: videoCardWidth,
              mainAxisExtent: videoCardHigh + 8,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
            ),
            itemCount: _videos.length,
            itemBuilder: (context, index) {
              return Material(
                child: InkWell(
                  onTap: () => _onVideoTapped(_videos[index]),
                  focusColor: Colors.blue.shade100,
                  hoverColor: Colors.blue.shade100,
                  child: VideoCard(video: _videos[index]),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
