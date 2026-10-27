import 'package:blt/widgets/horizontal_rail_boundary.dart';
import 'dart:async';
import 'package:blt/models/video.dart';
import 'package:blt/storages/season_history.dart';
import 'package:blt/widgets/detail_parts.dart';
import 'package:blt/widgets/video_actions.dart';
import 'package:blt/apis/bilibili/media.dart'
    show getVideoInfo, getArchiveRelation, ArchiveRelation;
import 'package:blt/utils/request_scope.dart';
import 'package:blt/apis/bilibili/user.dart'
    show
        getUserRelation,
        getUserFollowerCount,
        modifyUserRelation,
        UserRelation;
import 'package:blt/storages/auth.dart' show loginInfoNotifier;
import 'package:blt/widgets/season_follow_icon.dart';
import 'package:blt/widgets/video_card.dart';
import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/consts/color.dart';
import 'package:blt/pages/my_library.dart' show playLibraryEpisode;
import 'package:blt/utils/format.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/account_dialog.dart' show confirmAccountAction;
import 'package:blt/widgets/bilibili_image.dart';
import 'package:blt/widgets/loading.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:blt/widgets/scroll_text.dart';
import 'package:blt/widgets/tooltip.dart';
import 'package:blt/widgets/video_comments.dart';
import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

typedef SeasonEpisodeLoader =
    Future<(Video, ArchiveRelation)> Function(LibraryEntry);

Future<(Video, ArchiveRelation)> loadSeasonEpisode(LibraryEntry ep) async {
  return (
    getVideoInfo(avid: ep.aid),
    getArchiveRelation(avid: ep.aid).onError((_, _) => ArchiveRelation()),
  ).wait;
}

Future<bool?> openSeasonDetail(
  BuildContext context,
  LibraryEntry season, {
  bool? knownFollowed,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(
    builder: (_) =>
        SeasonDetailPage(seasonId: season.id, knownFollowed: knownFollowed),
  ),
);

class SeasonDetailPage extends StatelessWidget {
  final int seasonId;
  final int? episodeId, initialAid, initialCid;
  final Future<SeasonDetail> Function(int)? loader;
  final bool? knownFollowed;
  final CommentLoader? commentsLoader;
  final SeasonEpisodeLoader? episodeLoader;
  const SeasonDetailPage({
    super.key,
    this.seasonId = 0,
    this.episodeId,
    this.initialAid,
    this.initialCid,
    this.loader,
    this.knownFollowed,
    this.commentsLoader,
    this.episodeLoader,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: pageBackgroundGradient),
      child: LoadingWidget<SeasonDetail>(
        loader: () async {
          final detail = await (loader != null
              ? loader!(seasonId)
              : (episodeId ?? 0) > 0
              ? getSeasonDetailByEpisode(episodeId!)
              : getSeasonDetail(seasonId));
          if (knownFollowed != null) detail.followed = knownFollowed!;
          return detail;
        },
        loadingWidget: buildLoadingStyle1(),
        builder: (_, detail) => SeasonDetailView(
          detail: detail,
          commentsLoader: commentsLoader,
          episodeLoader: episodeLoader,
          initialEpisodeId: episodeId,
          initialAid: initialAid,
          initialCid: initialCid,
        ),
      ),
    ),
  );
}

class SeasonDetailView extends StatefulWidget {
  final int? initialEpisodeId, initialAid, initialCid;
  final SeasonDetail detail;
  final CommentLoader? commentsLoader;
  final Future<void> Function(LibraryEntry)? onPlay;
  final SeasonEpisodeLoader? episodeLoader;
  const SeasonDetailView({
    super.key,
    required this.detail,
    this.commentsLoader,
    this.onPlay,
    this.episodeLoader,
    this.initialEpisodeId,
    this.initialAid,
    this.initialCid,
  });
  @override
  State<SeasonDetailView> createState() => _SeasonDetailViewState();
}

class _SeasonDetailViewState extends State<SeasonDetailView> {
  int _selected = 0;
  bool _busy = false;
  bool _playing = false;
  bool _interacted = false;
  final _episodesScroll = ScrollController();
  final _episodeRequests = RequestScope();
  Video? _episodeVideo;
  ArchiveRelation? _episodeRelation;
  bool _episodeLoading = false;
  bool _episodeError = false;
  final _uploaderRequests = RequestScope();
  bool _upFollowing = false, _upBusy = false;
  int _upRelationMid = 0, _upMutation = 0;
  int _upFollowers = 0;
  bool _upFollowersKnown = false;
  bool _explicitEntry = false;
  int _loadGeneration = 0;
  bool _positioned = false;
  @override
  void initState() {
    super.initState();
    var entry = (widget.initialEpisodeId ?? 0) > 0
        ? detail.episodes.indexWhere((ep) => ep.id == widget.initialEpisodeId)
        : -1;
    if (entry < 0 && (widget.initialCid ?? 0) > 0) {
      entry = detail.episodes.indexWhere((ep) => ep.cid == widget.initialCid);
    }
    if (entry < 0 && (widget.initialAid ?? 0) > 0) {
      entry = detail.episodes.indexWhere((ep) => ep.aid == widget.initialAid);
    }
    final server = detail.episodes.indexWhere(
      (e) => e.id == detail.lastEpisodeId,
    );
    if (server >= 0) _selected = server;
    if (entry >= 0) {
      _selected = entry;
      _explicitEntry = true;
    }
    _restoreEpisode(initial: true).then((_) {
      if (mounted) _loadEpisode();
    }).ignore();
  }

  Future<void> _restoreEpisode({bool initial = false}) async {
    if (initial && _explicitEntry) return;
    final id = await SeasonHistory.episode(detail.id);
    if (!mounted || (initial && _interacted)) return;
    final index = detail.episodes.indexWhere((e) => e.id == id);
    if (index >= 0) {
      setState(() {
        _selected = index;
        _positioned = false;
      });
    }
  }

  Future<void> _loadEpisode() async {
    final ep = episode;
    if (ep == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      _episodeLoading = true;
      _episodeError = false;
      _episodeVideo = null;
      _episodeRelation = null;
    });
    try {
      final (video, relation) = await _episodeRequests.run(
        () => (widget.episodeLoader ?? loadSeasonEpisode)(ep),
        replace: true,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _episodeVideo = video;
        _episodeRelation = relation;
      });
      _loadUploaderRelation();
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _episodeError = true);
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _episodeLoading = false);
      }
    }
  }

  void _selectEpisode(int i) {
    if (_playing) return;
    _interacted = true;
    if (i == _selected) {
      _play(i);
      return;
    }
    setState(() => _selected = i);
    _loadEpisode();
  }

  Future<void> _play(int i) async {
    if (_playing || i < 0 || i >= detail.episodes.length) return;
    _interacted = true;
    setState(() {
      _selected = i;
      _playing = true;
    });
    try {
      final ep = detail.episodes[i];
      if (widget.onPlay != null) {
        await widget.onPlay!(ep);
      } else {
        await playLibraryEpisode(
          context,
          LibraryEntry(id: detail.id, title: detail.title),
          ep,
          episodes: detail.episodes,
        );
        await _restoreEpisode();
        if (mounted) {
          _loadEpisode();
        }
      }
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  SeasonDetail get detail => widget.detail;
  int get _uploaderMid => _episodeVideo?.userMid ?? 0;
  Future<void> _loadUploaderRelation() async {
    final mid = _uploaderMid;
    if (mid <= 0 || _upRelationMid == mid) {
      return;
    }
    _upRelationMid = mid;
    setState(() {
      _upFollowing = false;
      _upFollowers = 0;
      _upFollowersKnown = false;
    });
    final mutation = _upMutation;
    try {
      final (followers, relation) = await _uploaderRequests.run(
        () => (
          getUserFollowerCount(
            mid,
          ).then<int?>((v) => v).onError((_, _) => null),
          loginInfoNotifier.value.isLogin
              ? getUserRelation(mid).onError((_, _) => const UserRelation())
              : Future.value(const UserRelation()),
        ).wait,
        replace: true,
      );
      if (mounted && mid == _uploaderMid) {
        setState(() {
          if (mutation == _upMutation) _upFollowing = relation.following;
          _upFollowers = followers ?? 0;
          _upFollowersKnown = followers != null;
        });
      }
    } catch (_) {
      /* Keep the season response's relation on lookup failure. */
    }
  }

  Future<void> _followUploader() async {
    if (_upBusy) return;
    if (!loginInfoNotifier.value.isLogin) {
      pushTooltipInfo(context, '请先登录！');
      return;
    }
    final mid = _uploaderMid;
    if (mid <= 0) {
      pushTooltipInfo(context, 'UP 主信息尚未加载，请稍后重试');
      return;
    }
    _upMutation++;
    setState(() => _upBusy = true);
    try {
      final follow = !_upFollowing;
      await modifyUserRelation(mid, follow: follow);
      if (!mounted) return;
      setState(() {
        _upFollowing = follow;
        _upFollowers = (_upFollowers + (follow ? 1 : -1)).clamp(0, 1 << 62);
      });
      pushTooltipInfo(context, follow ? '关注成功！' : '已取消关注！');
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _upBusy = false);
    }
  }

  LibraryEntry? get episode => detail.episodes.elementAtOrNull(_selected);
  @override
  void dispose() {
    _uploaderRequests.dispose();
    _episodeRequests.dispose();
    _episodesScroll.dispose();
    super.dispose();
  }

  Future<void> _follow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final word = detail.isDrama ? '追剧' : '追番';
      if (detail.followed &&
          !await confirmAccountAction(
            context,
            title: '取消$word？',
            message: '将「${detail.title}」移出我的$word列表。',
            confirm: '取消$word',
          )) {
        return;
      }
      if (!mounted) return;
      await changeSeasonFollow(detail.id, follow: !detail.followed);
      if (!mounted) return;
      setState(() => detail.followed = !detail.followed);
      pushTooltipInfo(context, detail.followed ? '已$word' : '已取消$word');
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _info() async {
    final ui = context.ui;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 1120 * ui,
          height: 750 * ui,
          padding: EdgeInsets.all(32 * ui),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24 * ui),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '番剧简介',
                style: TextStyle(
                  fontSize: 32 * ui,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 20 * ui),
              Expanded(
                child: ScrollText(
                  [
                    detail.title,
                    detail.metadata,
                    detail.description,
                    if (detail.actors.isNotEmpty) '声优 / 演员\n${detail.actors}',
                    if (detail.staff.isNotEmpty) '制作人员\n${detail.staff}',
                  ].where((s) => s.isNotEmpty).join('\n\n'),
                  autofocus: true,
                  style: TextStyle(fontSize: 24 * ui, height: 1.6),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: PinkButton(
                  ui: ui,
                  label: '关闭',
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(double ui) => PinkPanel(
    ui: ui,
    padding: EdgeInsets.all(32 * ui),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          key: const ValueKey('season-title'),
          detail.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 34 * ui,
            height: 1.15,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 12 * ui),
        _summary(ui, detail.categoryLine, 'season-category'),
        SizedBox(height: 2 * ui),
        _summary(
          ui,
          '${amountString(detail.views)}播放 · ${amountString(detail.danmaku)}弹幕 · ${amountString(detail.follows)}${detail.isDrama ? '追剧' : '追番'}${detail.rating.isEmpty ? '' : ' · ${detail.rating}分 · ${amountString(detail.ratingCount)}人评分'}',
          'season-stats',
        ),
        SizedBox(height: 10 * ui),
        SizedBox(
          height: 58 * ui,
          child: _episodeVideo != null && _episodeRelation != null
              ? VideoActions(
                  key: ValueKey('season-actions-${episode?.id}'),
                  video: _episodeVideo!,
                  relation: _episodeRelation!,
                )
              : _episodeError
              ? PinkButton(
                  ui: ui,
                  label: '分集数据加载失败，重试',
                  onPressed: _loadEpisode,
                )
              : Center(
                  child: _episodeLoading
                      ? SizedBox(
                          width: 24 * ui,
                          height: 24 * ui,
                          child: const CircularProgressIndicator(),
                        )
                      : const SizedBox(),
                ),
        ),
        SizedBox(height: 12 * ui),
        Expanded(
          child: DetailDescription(
            ui: ui,
            desc: detail.description.trim(),
            onOpen: _info,
            fillAvailableHeight: true,
          ),
        ),
        SizedBox(height: 12 * ui),
        Divider(height: 2 * ui, color: Colors.black.withValues(alpha: .05)),
        SizedBox(height: 100 * ui, child: _uploaderRow(ui)),
      ],
    ),
  );

  Widget _summary(double ui, String text, String key) => SizedBox(
    key: ValueKey(key),
    height: 25 * ui,
    child: Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontSize: 20 * ui,
            height: 1.15,
            color: Colors.grey.shade600,
          ),
        ),
      ),
    ),
  );

  Widget _uploaderRow(double ui) => LayoutBuilder(
    builder: (context, constraints) {
      final actionWidth = (constraints.maxWidth - 48 * ui) / 5;
      final date = _episodeVideo == null
          ? ''
          : '发布于 ${datetimeString(_episodeVideo!.publishTime)}';
      return Row(
        children: [
          SizedBox(
            key: const ValueKey('season-follow-button'),
            width: actionWidth,
            height: 58 * ui,
            child: DetailAction(
              ui: ui,
              leading: SeasonFollowIcon(followed: detail.followed, ui: ui),
              label: _busy
                  ? '处理中'
                  : '${detail.followed ? '已' : ''}${detail.isDrama ? '追剧' : '追番'}',
              active: detail.followed,
              onPressed: _follow,
            ),
          ),
          SizedBox(width: 32 * ui),
          Expanded(
            child: Row(
              children: [
                BilibiliAvatar(
                  (_episodeVideo?.userAvatar.isNotEmpty == true
                      ? _episodeVideo!.userAvatar
                      : null),
                  radius: 26 * ui,
                ),
                SizedBox(width: 14 * ui),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _episodeVideo?.userName.isNotEmpty == true
                                  ? _episodeVideo!.userName
                                  : 'UP主信息加载中',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 26 * ui,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          SizedBox(width: 8 * ui),
                          DetailUpBadge(ui: ui),
                        ],
                      ),
                      SizedBox(height: 4 * ui),
                      SizedBox(
                        height: 24 * ui,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${_upFollowersKnown && _episodeVideo != null ? '${amountString(_upFollowers)}粉丝' : 'UP 主'}${date.isEmpty ? '' : '  $date'}',
                            key: const ValueKey('season-uploader-details'),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 20 * ui,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16 * ui),
                SizedBox(
                  width: 132 * ui,
                  child: PinkButton(
                    ui: ui,
                    height: 48,
                    fontSize: 22,
                    horizontalPadding: 12,
                    label: _upBusy
                        ? '处理中'
                        : _upFollowing
                        ? '已关注'
                        : '关注',
                    icon: _upFollowing || _upBusy ? null : Icons.add_rounded,
                    onPressed: _followUploader,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _episodes(double ui) => PinkPanel(
    ui: ui,
    child: Row(
      children: [
        SizedBox(
          width: 112 * ui,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.video_library_rounded, color: biliPink, size: 30 * ui),
              SizedBox(height: 6 * ui),
              Text(
                '选集',
                style: TextStyle(
                  fontSize: 22 * ui,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Same 16:9 cover + two-line title geometry as related-video cards.
              final width =
                  (constraints.maxHeight - 28 * ui) * videoCardAspectRatio;
              if (!_positioned) {
                _positioned = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _episodesScroll.hasClients) {
                    _episodesScroll.jumpTo(
                      (_selected * (width + 16 * ui)).clamp(
                        0,
                        _episodesScroll.position.maxScrollExtent,
                      ),
                    );
                  }
                });
              }
              return HorizontalRailBoundary(
                child: ListView.separated(
                  key: const ValueKey('season-episodes'),
                  controller: _episodesScroll,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.all(14 * ui),
                  itemCount: detail.episodes.length,
                  separatorBuilder: (_, _) => SizedBox(width: 16 * ui),
                  itemBuilder: (_, i) {
                    final e = detail.episodes[i];
                    return SizedBox(
                      width: width,
                      child: GestureDetector(
                        onTap: () => _selectEpisode(i),
                        child: VideoCard(
                          key: ValueKey('season-episode-${e.id}'),
                          showUploader: false,
                          selected: i == _selected,
                          video: MediaCardInfo(
                            type: MediaType.ogv,
                            avid: e.aid ?? 0,
                            bvid: '',
                            cid: e.cid,
                            title: e.title,
                            cover: e.cover.isEmpty ? detail.cover : e.cover,
                            duration: e.duration,
                            userMid: 0,
                            userName: '',
                            userAvatar: '',
                            publishTime: DateTime.fromMillisecondsSinceEpoch(0),
                          ),
                          onFocus: () => _interacted = true,
                          onTap: () => _selectEpisode(i),
                          focusEffect: pinkFocusEffect(
                            ui: ui,
                            radius: 18 * ui,
                            backgroundColor: i == _selected
                                ? focusableSurfaceColor
                                : Colors.white,
                            focusedBackgroundColor: Colors.white,
                            scale: 1.03,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    final ep = episode;
    final cover = ep?.cover.isNotEmpty == true ? ep!.cover : detail.cover;
    final size = MediaQuery.sizeOf(context);
    final headerHeight = ((size.width - 48 * ui) * .46 * 9 / 16 - 4 * ui).clamp(
      404 * ui,
      size.height * .48,
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(detail.followed);
        }
      },
      child: Padding(
        padding: EdgeInsets.all(24 * ui),
        child: Column(
          children: [
            SizedBox(
              height: headerHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 46,
                    child: Stack(
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: GestureDetector(
                              onTap: () => _play(_selected),
                              child: DpadFocusable(
                                autofocus: true,
                                onSelect: () => _play(_selected),
                                builder: pinkFocusEffect(
                                  ui: ui,
                                  radius: 20 * ui,
                                  scale: 1.02,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20 * ui),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (cover.isNotEmpty)
                                        BilibiliNetworkImage(cover)
                                      else
                                        const ColoredBox(color: Colors.black12),
                                      Center(
                                        child: Icon(
                                          Icons.play_circle_fill_rounded,
                                          size: 110 * ui,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Positioned(
                                        left: 18 * ui,
                                        right: 18 * ui,
                                        bottom: 16 * ui,
                                        child: Text(
                                          ep?.title ?? '暂无可播放分集',
                                          maxLines: 2,
                                          style: TextStyle(
                                            fontSize: 24 * ui,
                                            color: Colors.white,
                                            backgroundColor: Colors.black54,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 20 * ui),
                  Expanded(flex: 54, child: _infoCard(ui)),
                ],
              ),
            ),
            SizedBox(height: 12 * ui),
            Expanded(child: _episodes(ui)),
            SizedBox(height: 12 * ui),
            SizedBox(
              height: 212 * ui,
              child: ep?.aid != null && ep!.aid! > 0
                  ? VideoCommentsPanel(
                      key: ValueKey('episode-comments-${ep.aid}'),
                      avid: ep.aid!,
                      loader: widget.commentsLoader,
                    )
                  : Center(
                      child: Text(
                        '该分集暂无评论',
                        style: TextStyle(fontSize: 22 * ui),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
