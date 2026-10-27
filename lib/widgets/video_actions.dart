import 'package:flutter/material.dart';
import 'package:blt/models/video.dart';
import 'package:blt/apis/bilibili/media.dart' show ArchiveRelation, likeMedia;
import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/apis/bilibili/toview.dart';
import 'package:blt/utils/request_scope.dart';
import 'package:blt/icons/iconfont.dart';
import 'package:blt/storages/auth.dart' show loginInfoNotifier;
import 'package:blt/utils/format.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/detail_parts.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:blt/widgets/tooltip.dart';

class VideoActions extends StatefulWidget {
  final Video video;
  final ArchiveRelation relation;
  const VideoActions({super.key, required this.video, required this.relation});
  @override
  State<VideoActions> createState() => _VideoActionsState();
}

class _VideoActionsState extends State<VideoActions> {
  final _requests = RequestScope();
  bool? _inToView;
  bool _actionBusy = false;
  late final ValueNotifier<bool> _like;
  @override
  void initState() {
    super.initState();
    _like = ValueNotifier(widget.relation.like);
    _requests.run(_loadToViewStatus).ignore();
  }

  @override
  void dispose() {
    _requests.dispose();
    _like.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildRelations(context.ui);
  Widget _buildRelations(double ui) {
    // 等宽胶囊按钮：横向 5 格，遥控器左右移动即可，宽度稳定不随数字长度跳动
    Widget stretch(DetailAction action) => Expanded(child: action);

    return ValueListenableBuilder(
      valueListenable: _like,
      builder: (context, like, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stretch(
            DetailAction(
              ui: ui,
              icon: Icons.thumb_up_rounded,
              label: amountString(widget.video.stat.likeCount),
              active: like,
              onPressed: _onLikeTapped,
            ),
          ),
          SizedBox(width: 12 * ui),
          stretch(
            DetailAction(
              ui: ui,
              iconFont: IconFont.coin,
              iconScale: 1.1,
              label: amountString(widget.video.stat.coinCount),
              active: widget.relation.coin > 0,
              onPressed: _onCoinTapped,
            ),
          ),
          SizedBox(width: 12 * ui),
          stretch(
            DetailAction(
              ui: ui,
              icon: Icons.star_rounded,
              iconScale: 1.2,
              label: amountString(widget.video.stat.favoriteCount),
              active: widget.relation.favorite,
              onPressed: _onFavoriteTapped,
            ),
          ),
          SizedBox(width: 12 * ui),
          stretch(
            DetailAction(
              ui: ui,
              iconFont: IconFont.share,
              iconScale: 1.1,
              label: amountString(widget.video.stat.shareCount),
              onPressed: () => pushTooltipInfo(context, '暂不支持该功能！'),
            ),
          ),
          SizedBox(width: 12 * ui),
          stretch(
            DetailAction(
              ui: ui,
              iconFont: IconFont.playlist,
              iconScale: 1.1,
              active: _inToView == true,
              onPressed: _onAddToViewTapped,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onLikeTapped() async {
    try {
      await likeMedia(widget.video.avid, like: !widget.relation.like);
      if (!mounted) return;
      pushTooltipInfo(context, '${widget.relation.like ? '取消' : ''}点赞成功！');
      widget.relation.like = !widget.relation.like;
      _like.value = widget.relation.like;
    } catch (e) {
      if (!mounted) return;
      showAppError(context, e);
    }
  }

  Future<void> _loadToViewStatus() async {
    if (!loginInfoNotifier.value.isLogin) return;
    try {
      final selected = await isInToView(widget.video.avid);
      if (mounted) setState(() => _inToView = selected);
    } catch (_) {
      /* A failed lookup must not be mistaken for an empty list. */
    }
  }

  bool _requireLogin() {
    if (loginInfoNotifier.value.isLogin) return true;
    pushTooltipInfo(context, '请先登录！');
    return false;
  }

  Future<void> _onAddToViewTapped() async {
    if (_actionBusy || !_requireLogin()) return;
    _actionBusy = true;
    try {
      final wasAdded = _inToView ?? await isInToView(widget.video.avid);
      if (wasAdded) {
        await deleteToView(widget.video.avid);
      } else {
        await addToView(avid: widget.video.avid);
      }
      if (!mounted) return;
      setState(() => _inToView = !wasAdded);
      pushTooltipInfo(context, wasAdded ? '已移出稍后再看' : '已加入稍后再看');
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      _actionBusy = false;
    }
  }

  Future<int?> _chooseAction(String title, List<String> labels) {
    final ui = context.ui;
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 760 * ui,
          padding: EdgeInsets.all(28 * ui),
          constraints: BoxConstraints(maxHeight: 800 * ui),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24 * ui),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 30 * ui,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 22 * ui),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 8 * ui),
                        child: PinkButton(
                          ui: ui,
                          label: labels[i],
                          onPressed: () => Navigator.of(dialogContext).pop(i),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 18 * ui),
              PinkButton(
                ui: ui,
                label: '取消',
                autofocus: true,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onCoinTapped() {
    pushTooltipInfo(context, '功能暂未开放');
  }

  Future<void> _onFavoriteTapped() async {
    if (_actionBusy || !_requireLogin()) return;
    _actionBusy = true;
    try {
      final folders = await videoFavoriteFolders(
        loginInfoNotifier.value.mid!,
        widget.video.avid,
      );
      if (!mounted) return;
      if (folders.isEmpty) {
        pushTooltipInfo(context, '请先在 B 站创建收藏夹');
        return;
      }
      final selected = await _chooseAction('选择收藏夹 · 已收藏可取消', [
        for (final f in folders) '${f.selected ? '取消收藏' : '添加收藏'} · ${f.title}',
      ]);
      if (selected == null || !mounted) return;
      final folder = folders[selected];
      await changeVideoFavorite(
        widget.video.avid,
        folder.id,
        add: !folder.selected,
      );
      if (!mounted) return;
      setState(
        () => widget.relation.favorite =
            !folder.selected ||
            folders.any((f) => f.id != folder.id && f.selected),
      );
      pushTooltipInfo(context, folder.selected ? '已从该收藏夹移除' : '收藏成功');
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      _actionBusy = false;
    }
  }
}
