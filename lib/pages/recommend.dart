import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/pages/my_library.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:dpad/dpad.dart';
import 'package:flutter_lazy_indexed_stack/flutter_lazy_indexed_stack.dart';
import 'dart:async';

import 'package:blt/apis/bilibili/recommend.dart';
import 'package:blt/apis/bilibili/toview.dart';
import 'package:blt/consts/assets.dart';
import 'package:blt/models/video.dart' show MediaCardInfo;
import 'package:blt/pages/video_detail.dart';
import 'package:blt/storages/auth.dart';
import 'package:blt/widgets/loading.dart';
import 'package:blt/widgets/tooltip.dart';
import 'package:blt/widgets/video_grid_view.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class _HomeVideoFeed extends StatefulWidget {
  final ValueNotifier<int> _tappedListener;

  final bool popular;
  const _HomeVideoFeed(this._tappedListener, {this.popular = false});

  @override
  State<_HomeVideoFeed> createState() => _HomeVideoFeedState();
}

class _HomeVideoFeedState extends State<_HomeVideoFeed> {
  int _page = 0;
  final _pageVideoCount = 20;
  late final VideoGridViewProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = VideoGridViewProvider(onLoad: _onLoad);
    widget._tappedListener.addListener(_onRefresh);
  }

  @override
  void dispose() {
    widget._tappedListener.removeListener(_onRefresh);
    _provider.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    _page = 0;
    await _provider.refresh();
  }

  Future<(List<MediaCardInfo>, bool)> _onLoad({
    bool isFetchMore = false,
  }) async {
    // 请求成功后提交页码，失败时下次重试同一页
    final nextPage = _page + 1;
    if (widget.popular) {
      final result = await listPopularVideos(
        page: nextPage,
        count: _pageVideoCount,
      );
      _page = nextPage;
      return result;
    }
    final videos = await listRecommendVideos(
      page: nextPage,
      count: _pageVideoCount,
      removeAvids: _provider.toList().map((e) => e.avid).toList(),
    );
    _page = nextPage;
    return (videos, true);
  }

  void _onVideoTapped(_, MediaCardInfo video) {
    Get.to(() => VideoDetailPageWrap(avid: video.avid, cid: video.cid));
  }

  @override
  Widget build(BuildContext context) {
    return VideoGridView(
      provider: _provider,
      onItemTap: _onVideoTapped,
      itemMenuActions: [
        ItemMenuAction(
          title: '稍后再看',
          icon: Icons.playlist_add_rounded,
          action: (media) {
            if (!loginInfoNotifier.value.isLogin) return;

            requestWithTooltip(
              context,
              request: () => addToView(avid: media.avid),
              successText: '已加入稍后再看：${media.title}',
            );
          },
        ),
      ],
      refreshWidget: buildLoadingStyle1(),
      noItemsWidget: FractionallySizedBox(
        widthFactor: 0.2,
        child: Image.asset(Images.empty, fit: BoxFit.contain),
      ),
    );
  }
}

class RecommendPage extends StatefulWidget {
  final ValueNotifier<int> tappedListener;
  const RecommendPage(this.tappedListener, {super.key});
  @override
  State<RecommendPage> createState() => _RecommendPageState();
}

class _RecommendPageState extends State<RecommendPage> {
  int _section = 0;
  final _refresh = List.generate(3, (_) => ValueNotifier(0));
  @override
  void initState() {
    super.initState();
    widget.tappedListener.addListener(_reload);
  }

  void _reload() => _refresh[_section].value++;
  @override
  void dispose() {
    widget.tappedListener.removeListener(_reload);
    for (final value in _refresh) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(24 * ui, 14 * ui, 24 * ui, 4 * ui),
          child: Row(
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.only(right: 16 * ui),
                  child: GestureDetector(
                    onTap: () => setState(() => _section = i),
                    child: DpadFocusable(
                      onSelect: () => setState(() => _section = i),
                      builder: pinkFocusEffect(
                        ui: ui,
                        radius: 14 * ui,
                        focusedBackgroundColor: Colors.white,
                      ),
                      child: SizedBox(
                        width: 132 * ui,
                        height: 78 * ui,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              ['推荐', '热门', '番剧'][i],
                              style: TextStyle(
                                fontSize: 30 * ui,
                                fontWeight: _section == i
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: _section == i
                                    ? navigationAccentColor
                                    : Colors.black54,
                              ),
                            ),
                            SizedBox(height: 8 * ui),
                            Container(
                              width: 42 * ui,
                              height: 4 * ui,
                              decoration: BoxDecoration(
                                color: _section == i
                                    ? navigationAccentColor
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(2 * ui),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LazyIndexedStack(
            index: _section,
            children: [
              _HomeVideoFeed(_refresh[0]),
              _HomeVideoFeed(_refresh[1], popular: true),
              _BangumiHome(refresh: _refresh[2]),
            ],
          ),
        ),
      ],
    );
  }
}

class _BangumiHome extends StatefulWidget {
  final ValueNotifier<int> refresh;
  const _BangumiHome({required this.refresh});
  @override
  State<_BangumiHome> createState() => _BangumiHomeState();
}

class _BangumiHomeState extends State<_BangumiHome> {
  int _revision = 0;
  LibraryEntry? _season;
  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_reload);
  }

  void _reload() => setState(() => _revision++);
  @override
  void dispose() {
    widget.refresh.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _season == null
      ? LibraryCollectionPane(
          key: ValueKey('catalog-$_revision'),
          title: '番剧',
          loader: (page) => listBangumiCatalog(page: page),
          onOpen: (season) => setState(() => _season = season),
        )
      : LibraryCollectionPane(
          key: ValueKey('episodes-${_season!.id}-$_revision'),
          title: _season!.title,
          onBack: () => setState(() => _season = null),
          loader: (_) => listSeasonEpisodes(_season!.id),
          onOpen: (episode) => playLibraryEpisode(context, _season!, episode),
        );
}
