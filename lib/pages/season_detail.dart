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
  final Future<SeasonDetail> Function(int)? loader;
  final bool? knownFollowed;
  final CommentLoader? commentsLoader;
  const SeasonDetailPage({
    super.key,
    required this.seasonId,
    this.loader,
    this.knownFollowed,
    this.commentsLoader,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: pageBackgroundGradient),
      child: LoadingWidget<SeasonDetail>(
        loader: () async {
          final detail = await (loader ?? getSeasonDetail)(seasonId);
          if (knownFollowed != null) detail.followed = knownFollowed!;
          return detail;
        },
        loadingWidget: buildLoadingStyle1(),
        builder: (_, detail) =>
            SeasonDetailView(detail: detail, commentsLoader: commentsLoader),
      ),
    ),
  );
}

class SeasonDetailView extends StatefulWidget {
  final SeasonDetail detail;
  final CommentLoader? commentsLoader;
  const SeasonDetailView({
    super.key,
    required this.detail,
    this.commentsLoader,
  });
  @override
  State<SeasonDetailView> createState() => _SeasonDetailViewState();
}

class _SeasonDetailViewState extends State<SeasonDetailView> {
  final _backAnchor = FocusNode(canRequestFocus: false);
  int _selected = 0;
  bool _busy = false;
  SeasonDetail get detail => widget.detail;
  LibraryEntry? get episode => detail.episodes.elementAtOrNull(_selected);
  @override
  void dispose() {
    _backAnchor.dispose();
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
                '简介与资料',
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

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    final ep = episode;
    final cover = ep?.cover.isNotEmpty == true ? ep!.cover : detail.cover;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _backAnchor.descendants
              .where((n) => n.canRequestFocus && !n.skipTraversal)
              .firstOrNull
              ?.requestFocus();
        }
      },
      child: Padding(
        padding: EdgeInsets.all(24 * ui),
        child: Column(
          children: [
            Row(
              children: [
                Focus(
                  focusNode: _backAnchor,
                  canRequestFocus: false,
                  child: PinkButton(
                    ui: ui,
                    label: '返回',
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).pop(detail.followed),
                  ),
                ),
                SizedBox(width: 24 * ui),
                Expanded(
                  child: Text(
                    detail.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 30 * ui,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14 * ui),
            Expanded(
              flex: 5,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 9,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: GestureDetector(
                          onTap: ep == null
                              ? null
                              : () => playLibraryEpisode(
                                  context,
                                  LibraryEntry(
                                    id: detail.id,
                                    title: detail.title,
                                  ),
                                  ep,
                                ),
                          child: DpadFocusable(
                            autofocus: true,
                            onSelect: () {
                              if (ep != null) {
                                playLibraryEpisode(
                                  context,
                                  LibraryEntry(
                                    id: detail.id,
                                    title: detail.title,
                                  ),
                                  ep,
                                );
                              }
                            },
                            builder: pinkFocusEffect(ui: ui, radius: 20 * ui),
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
                  ),
                  SizedBox(width: 20 * ui),
                  Expanded(
                    flex: 10,
                    child: PinkPanel(
                      ui: ui,
                      padding: EdgeInsets.all(24 * ui),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            detail.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 34 * ui,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 10 * ui),
                          Text(
                            detail.metadata,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20 * ui,
                              color: Colors.black54,
                            ),
                          ),
                          SizedBox(height: 10 * ui),
                          Text(
                            '${amountString(detail.views)} 播放 · ${amountString(detail.danmaku)} 弹幕 · ${amountString(detail.follows)} ${detail.isDrama ? '追剧' : '追番'}',
                            style: TextStyle(
                              fontSize: 20 * ui,
                              color: Colors.black54,
                            ),
                          ),
                          SizedBox(height: 10 * ui),
                          Text(
                            detail.rating.isEmpty
                                ? '暂无评分'
                                : '${detail.rating} 分 · ${amountString(detail.ratingCount)} 人评分',
                            style: TextStyle(
                              fontSize: 26 * ui,
                              color: navigationAccentColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 14 * ui),
                          Row(
                            children: [
                              Expanded(
                                child: PinkButton(
                                  ui: ui,
                                  label: _busy
                                      ? '处理中'
                                      : '${detail.followed ? '取消' : ''}${detail.isDrama ? '追剧' : '追番'}',
                                  icon: detail.followed
                                      ? Icons.check_circle_rounded
                                      : Icons.add_circle_rounded,
                                  onPressed: _follow,
                                ),
                              ),
                              SizedBox(width: 14 * ui),
                              Expanded(
                                child: PinkButton(
                                  ui: ui,
                                  label: '简介与资料',
                                  onPressed: _info,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12 * ui),
                          Expanded(
                            child: ScrollText(
                              detail.description.isEmpty
                                  ? '暂无简介'
                                  : detail.description,
                              style: TextStyle(fontSize: 22 * ui, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12 * ui),
            Expanded(
              flex: 2,
              child: PinkPanel(
                ui: ui,
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
            ),
            SizedBox(height: 12 * ui),
            Expanded(
              flex: 3,
              child: PinkPanel(
                ui: ui,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '选集 · 确认选择分集，封面与评论同步切换',
                      style: TextStyle(
                        fontSize: 22 * ui,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: EdgeInsets.all(14 * ui),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 440 * ui,
                          childAspectRatio: 4,
                          mainAxisSpacing: 18 * ui,
                          crossAxisSpacing: 18 * ui,
                        ),
                        itemCount: detail.episodes.length,
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => setState(() => _selected = i),
                          child: DpadFocusable(
                            onSelect: () => setState(() => _selected = i),
                            builder: pinkFocusEffect(
                              ui: ui,
                              radius: 16 * ui,
                              backgroundColor: i == _selected
                                  ? Colors.pink.shade100
                                  : focusableSurfaceColor,
                              focusedBackgroundColor: Colors.white,
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(12 * ui),
                              child: Center(
                                child: Text(
                                  detail.episodes[i].title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 21 * ui,
                                    color: i == _selected
                                        ? navigationAccentColor
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
