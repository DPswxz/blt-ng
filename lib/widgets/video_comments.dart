import 'package:blt/apis/bilibili/comments.dart';
import 'package:blt/consts/color.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:blt/widgets/tooltip.dart';
import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

typedef CommentLoader =
    Future<CommentPage> Function(int page, int sort, int? root);

class VideoCommentsPanel extends StatefulWidget {
  final int avid;
  final bool compact;
  final VideoComment? root;
  final CommentLoader? loader;
  const VideoCommentsPanel({
    super.key,
    required this.avid,
    this.compact = true,
    this.root,
    this.loader,
  });
  @override
  State<VideoCommentsPanel> createState() => _VideoCommentsPanelState();
}

class _VideoCommentsPanelState extends State<VideoCommentsPanel> {
  final _items = <VideoComment>[];
  int _page = 0, _total = 0, _sort = 1, _seq = 0;
  bool _loading = false, _more = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final seq = ++_seq;
    final next = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await (widget.loader?.call(next, _sort, widget.root?.id) ??
              getComments(
                widget.avid,
                page: next,
                sort: _sort,
                root: widget.root?.id,
              ));
      if (!mounted || seq != _seq) return;
      setState(() {
        if (reset) _items.clear();
        final seen = _items.map((c) => c.id).toSet();
        final additions = result.comments.where((c) => seen.add(c.id)).toList();
        _items.addAll(additions);
        _total = result.total;
        _page = next;
        _more =
            result.comments.isNotEmpty &&
            additions.isNotEmpty &&
            _items.length < _total;
      });
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = '评论加载失败，请重试');
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  Future<void> _open({VideoComment? root}) async {
    final ui = context.ui;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: 90 * ui,
          vertical: 50 * ui,
        ),
        child: SizedBox(
          width: 1400 * ui,
          height: 860 * ui,
          child: VideoCommentsPanel(
            avid: widget.avid,
            compact: false,
            root: root,
            loader: widget.loader,
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    final data = [if (widget.root != null) widget.root!, ..._items];
    return PinkPanel(
      ui: ui,
      child: Flex(
        direction: widget.compact ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.compact)
            SizedBox(
              width: 140 * ui,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '评论 · $_total',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19 * ui,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 6 * ui),
                  PinkButton(
                    ui: ui,
                    height: 38,
                    fontSize: 18,
                    horizontalPadding: 16,
                    label: _sort == 1 ? '热门' : '最新',
                    onPressed: () {
                      _sort = _sort == 1 ? 0 : 1;
                      _load(reset: true);
                    },
                  ),
                  SizedBox(height: 6 * ui),
                  PinkButton(
                    ui: ui,
                    height: 38,
                    fontSize: 18,
                    horizontalPadding: 16,
                    label: '全部',
                    onPressed: () => _open(),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 40 * ui,
              child: Row(
                children: [
                  Icon(Icons.forum_rounded, color: biliPink, size: 26 * ui),
                  SizedBox(width: 8 * ui),
                  Expanded(
                    child: Text(
                      widget.root == null
                          ? '评论 · $_total'
                          : '评论详情 · $_total 条回复',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 24 * ui,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (widget.root == null) ...[
                    PinkButton(
                      ui: ui,
                      height: 36,
                      label: _sort == 1 ? '热门' : '最新',
                      onPressed: () {
                        _sort = _sort == 1 ? 0 : 1;
                        _load(reset: true);
                      },
                    ),
                    SizedBox(width: 12 * ui),
                  ],
                  PinkButton(
                    ui: ui,
                    height: 36,
                    label: widget.compact ? '查看全部' : '关闭',
                    autofocus: !widget.compact,
                    onPressed: () =>
                        widget.compact ? _open() : Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: data.isEmpty
                ? Center(
                    child: _loading
                        ? const CircularProgressIndicator()
                        : _error != null
                        ? PinkButton(
                            ui: ui,
                            label: '评论加载失败 · 重试',
                            height: 40,
                            onPressed: () => _load(reset: true),
                          )
                        : Text(
                            '暂无评论',
                            style: TextStyle(
                              fontSize: 22 * ui,
                              color: Colors.grey,
                            ),
                          ),
                  )
                : ListView.separated(
                    scrollDirection: widget.compact
                        ? Axis.horizontal
                        : Axis.vertical,
                    padding: EdgeInsets.all(14 * ui),
                    itemCount: data.length + 1,
                    separatorBuilder: (_, _) =>
                        SizedBox(width: 16 * ui, height: 14 * ui),
                    itemBuilder: (context, index) {
                      if (index == data.length) {
                        return Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : _more || _error != null
                              ? PinkButton(
                                  ui: ui,
                                  height: 40,
                                  label: _error != null ? '重试' : '加载更多',
                                  onPressed: () => _load(),
                                )
                              : Text(
                                  _items.length >= _total
                                      ? '已显示全部'
                                      : '已显示当前可见评论',
                                  style: TextStyle(
                                    fontSize: 18 * ui,
                                    color: Colors.grey,
                                  ),
                                ),
                        );
                      }
                      final comment = data[index];
                      final card = _CommentCard(
                        avid: widget.avid,
                        comment: comment,
                        compact: widget.compact,
                        reply: widget.root != null && index > 0,
                        onOpen: widget.compact || widget.root == null
                            ? () => _open(root: comment)
                            : null,
                      );
                      return widget.compact
                          ? SizedBox(width: 540 * ui, child: card)
                          : Padding(
                              padding: EdgeInsets.only(
                                left: widget.root != null && index > 0
                                    ? 64 * ui
                                    : 0,
                                right: widget.root != null && index > 0
                                    ? 24 * ui
                                    : 0,
                              ),
                              child: card,
                            );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CommentCard extends StatefulWidget {
  final int avid;
  final VideoComment comment;
  final bool compact;
  final bool reply;
  final VoidCallback? onOpen;
  const _CommentCard({
    required this.avid,
    required this.comment,
    required this.compact,
    this.reply = false,
    this.onOpen,
  });
  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  bool _busy = false;
  Future<void> _vote(bool dislike) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await voteComment(widget.avid, widget.comment, dislike: dislike);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui, c = widget.comment;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          c.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: (widget.reply || widget.compact ? 18 : 20) * ui,
            height: 1.2,
            color: biliPink,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 4 * ui),
        if (widget.compact)
          Expanded(
            child: GestureDetector(
              onTap: widget.onOpen,
              child: DpadFocusable(
                onSelect: widget.onOpen,
                builder: pinkFocusEffect(ui: ui, radius: 8 * ui),
                child: Text(
                  c.message,
                  maxLines: 2,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 20 * ui, height: 1.25),
                ),
              ),
            ),
          )
        else
          Text(
            c.message,
            style: TextStyle(
              fontSize: (widget.reply ? 21 : 24) * ui,
              height: 1.5,
            ),
          ),
        SizedBox(height: 6 * ui),
        Row(
          children: [
            _action(
              ui,
              Icons.thumb_up_alt_outlined,
              '${c.likes}',
              c.action == 1,
              () => _vote(false),
            ),
            SizedBox(width: 14 * ui),
            _action(
              ui,
              Icons.thumb_down_alt_outlined,
              '踩',
              c.action == 2,
              () => _vote(true),
            ),
            const Spacer(),
            if (widget.onOpen != null)
              _action(
                ui,
                Icons.chat_bubble_outline,
                widget.compact
                    ? '全文 · ${c.replyCount} 回复'
                    : '${c.replyCount} 回复',
                false,
                widget.onOpen!,
              ),
          ],
        ),
      ],
    );
    final content = Container(
      padding: EdgeInsets.all((widget.reply || widget.compact ? 10 : 16) * ui),
      decoration: BoxDecoration(
        color: widget.reply ? const Color(0xFFF7F7F9) : focusableSurfaceColor,
        borderRadius: BorderRadius.circular(16 * ui),
      ),
      child: body,
    );
    return content;
  }

  Widget _action(
    double ui,
    IconData icon,
    String label,
    bool active,
    VoidCallback action,
  ) => GestureDetector(
    onTap: _busy ? null : action,
    child: DpadFocusable(
      onSelect: () {
        if (!_busy) action();
      },
      builder: pinkFocusEffect(ui: ui, radius: 10 * ui),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8 * ui,
          vertical: (widget.compact ? 4 : 5) * ui,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: (widget.compact ? 18 : 20) * ui,
              color: active ? biliPink : Colors.black54,
            ),
            SizedBox(width: 5 * ui),
            Text(
              label,
              style: TextStyle(
                fontSize: (widget.compact ? 16 : 18) * ui,
                height: 1.2,
                color: active ? biliPink : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
