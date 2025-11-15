import 'dart:async';

import 'package:bilitv/apis/bilibili/history.dart';
import 'package:bilitv/apis/bilibili/toview.dart';
import 'package:bilitv/models/video.dart' show MediaCardInfo;
import 'package:bilitv/pages/video_detail.dart';
import 'package:bilitv/storages/cookie.dart';
import 'package:bilitv/widgets/loading.dart';
import 'package:bilitv/widgets/tooltip.dart';
import 'package:bilitv/widgets/video_grid_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../consts/assets.dart';

class HistoryPage extends StatefulWidget {
  final ValueNotifier<int> _tappedListener;

  const HistoryPage(this._tappedListener, {super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  HistoryCursor? cursor;
  final pageVideoCount = 20;
  final _videos = VideoGridViewProvider();
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);

  @override
  void initState() {
    widget._tappedListener.addListener(_onRefresh);
    _videos.onLoad = _pullMoreVideos;
    super.initState();
  }

  @override
  void dispose() {
    widget._tappedListener.removeListener(_onRefresh);
    super.dispose();
  }

  DateTime? _lastRefresh;

  void _onRefresh() {
    if (_isLoading.value) return;

    final now = DateTime.now();
    if (_lastRefresh != null &&
        now.difference(_lastRefresh!).inMilliseconds < 500) {
      return;
    }
    _lastRefresh = now;

    _isLoading.value = true;
    cursor = null;
    _videos.clear();
    _pullMoreVideos().then((res) {
      _videos.addAll(res.$1);
      _isLoading.value = false;
    });
  }

  void _onVideoTapped(_, MediaCardInfo video) {
    Get.to(VideoDetailPageWrap(avid: video.avid));
  }

  bool _isFetchingMore = false;
  DateTime? _lastFetchMore;

  Future<void> _onVideoFocused(int index, MediaCardInfo _) async {
    final lastLine = (index / 5).floor() == ((_videos.length - 1) / 5).floor();
    if (!lastLine || _isFetchingMore) return;

    final now = DateTime.now();
    if (_lastFetchMore != null &&
        now.difference(_lastFetchMore!).inMilliseconds < 500) {
      return;
    }
    _lastFetchMore = now;

    _isFetchingMore = true;
    await _videos.fetchData(isFetchMore: true);
    _isFetchingMore = false;
  }

  Future<(List<MediaCardInfo>, bool)> _pullMoreVideos({
    bool isFetchMore = false,
  }) async {
    if (!loginInfoNotifier.value.isLogin) {
      return ([] as List<MediaCardInfo>, false);
    }

    final (nextCursor, videos) = await listHistory(
      cursor: cursor,
      count: pageVideoCount,
    );
    if (nextCursor.max != 0) {
      cursor = nextCursor;
    }
    return (videos, videos.length == pageVideoCount);
  }

  @override
  Widget build(BuildContext context) {
    return LoadingWidget(
      isLoading: _isLoading,
      loader: () async => await _pullMoreVideos().then((res) {
        _videos.addAll(res.$1);
      }),
      builder: (context, _) {
        if (_videos.isEmpty) {
          return FractionallySizedBox(
            widthFactor: 0.2,
            child: Image.asset(Images.empty, fit: BoxFit.contain),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: VideoGridView(
            provider: _videos,
            onItemTap: _onVideoTapped,
            onItemFocus: _onVideoFocused,
            itemMenuActions: [
              ItemMenuAction(
                title: '稍后再看',
                icon: Icons.playlist_add_rounded,
                action: (media) {
                  if (!loginInfoNotifier.value.isLogin) return;

                  addToView(avid: media.avid);
                  pushTooltipInfo(context, '已加入稍后再看：${media.title}');
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
