import 'package:blt/utils/playback_navigation.dart';
import 'dart:async';
import 'package:blt/consts/color.dart';
import 'package:blt/pages/season_detail.dart';
import 'package:blt/utils/request_scope.dart';
import 'package:flutter/services.dart';
import 'package:blt/widgets/account_dialog.dart' show confirmAccountAction;
import 'package:blt/apis/bilibili/library.dart';
import 'package:blt/consts/settings.dart';
import 'package:blt/models/video.dart';
import 'package:blt/pages/video_detail.dart';
import 'package:blt/pages/video_player.dart';
import 'package:blt/storages/settings.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/bilibili_image.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:blt/widgets/tooltip.dart';
import 'package:blt/widgets/text.dart';
import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

Future<void> playLibraryEpisode(
  BuildContext context,
  LibraryEntry season,
  LibraryEntry episode, {
  List<LibraryEntry>? episodes,
}) async {
  try {
    if ((episode.aid ?? 0) <= 0 || (episode.cid ?? 0) <= 0) {
      throw StateError('该分集暂时无法播放');
    }
    final danmu = await Settings.getBool(Settings.pathDanmuSwitch) ?? true;
    final decoder =
        await Settings.getString(Settings.pathDecoderMode) ?? 'auto';
    if (!context.mounted) return;
    final video = Video(
      avid: episode.aid!,
      bvid: '',
      title: season.title,
      cover: episode.cover,
      desc: '',
      duration: episode.duration,
      stat: Stat.fromJson({}),
      userMid: 0,
      userName: '哔哩哔哩番剧',
      userAvatar: '',
      publishTime: DateTime.fromMillisecondsSinceEpoch(0),
      cid: episode.cid!,
      episodes: libraryPlaybackEpisodes(episodes ?? [episode]),
    );
    await openPlaybackPage(
      () => VideoPlayerPage(
        video: video,
        seasonId: season.id,
        cid: episode.cid!,
        danmu: danmu,
        ha: true,
        vo: VideoOutputDrivers.gpu,
        hwdec: HardwareVideoDecoder.autoSafe,
        decoderMode: decoder,
      ),
    );
  } catch (e) {
    if (context.mounted) showAppError(context, e);
  }
}

typedef LibraryLoader = Future<LibraryBatch> Function(int page);

List<Episode> libraryPlaybackEpisodes(List<LibraryEntry> entries) => [
  for (var i = 0; i < entries.length; i++)
    if ((entries[i].aid ?? 0) > 0 && (entries[i].cid ?? 0) > 0)
      Episode(
        index: i + 1,
        aid: entries[i].aid,
        cid: entries[i].cid!,
        episodeId: entries[i].id,
        title: entries[i].title,
        duration: entries[i].duration,
      ),
];

class MySubscriptions extends StatefulWidget {
  final int mid;
  const MySubscriptions({super.key, required this.mid});
  @override
  State<MySubscriptions> createState() => _MySubscriptionsState();
}

class _MySubscriptionsState extends State<MySubscriptions> {
  int _type = 1;
  final _collection = LibraryCollectionController();
  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14 * ui, vertical: 10 * ui),
          child: Row(
            children: [
              LibraryTab(
                label: '追番',
                icon: Icons.auto_awesome_rounded,
                selected: _type == 1,
                onTap: () => setState(() => _type = 1),
              ),
              SizedBox(width: 16 * ui),
              LibraryTab(
                label: '追剧',
                icon: Icons.live_tv_rounded,
                selected: _type == 2,
                onTap: () => setState(() => _type = 2),
              ),
            ],
          ),
        ),
        Expanded(
          child: LibraryCollectionPane(
            key: ValueKey('follow-$_type'),
            title: _type == 1 ? '我的追番' : '我的追剧',
            controller: _collection,
            loader: (page) =>
                listFollowedSeasons(widget.mid, type: _type, page: page),
            onOpen: (item) async {
              final followed = await openSeasonDetail(
                context,
                item,
                knownFollowed: true,
              );
              if (mounted && followed == false) _collection.remove(item.id);
            },
          ),
        ),
      ],
    );
  }
}

class MyFavorites extends StatefulWidget {
  final int mid;
  const MyFavorites({super.key, required this.mid});
  @override
  State<MyFavorites> createState() => _MyFavoritesState();
}

class _MyFavoritesState extends State<MyFavorites> {
  @override
  Widget build(BuildContext context) => LibraryCollectionPane(
    title: '我的收藏夹',
    loader: (_) => listFavoriteFolders(widget.mid),
    onOpen: (folder) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: pageBackgroundGradient),
            padding: EdgeInsets.all(24 * context.ui),
            child: LibraryCollectionPane(
              title: folder.title,
              folderView: true,
              onBack: () => Navigator.of(routeContext).pop(),
              loader: (page) => listFavoriteVideos(folder.id, page: page),
              onRemove: (item) =>
                  changeVideoFavorite(item.video!.avid, folder.id, add: false),
              onOpen: (item) async {
                final video = item.video;
                if (video == null) return;
                await Get.to(
                  () => VideoDetailPageWrap(
                    avid: video.avid,
                    bvid: video.bvid.isEmpty ? null : video.bvid,
                    cid: video.cid,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class LibraryCollectionController {
  void Function(int)? _remove;
  void remove(int id) => _remove?.call(id);
}

class LibraryCollectionPane extends StatefulWidget {
  final String title;
  final LibraryLoader loader;
  final FutureOr<void> Function(LibraryEntry) onOpen;
  final VoidCallback? onBack;
  final bool showHeader;
  final bool folderView;
  final Future<void> Function(LibraryEntry)? onRemove;
  final LibraryCollectionController? controller;
  const LibraryCollectionPane({
    super.key,
    required this.title,
    required this.loader,
    required this.onOpen,
    this.onBack,
    this.showHeader = true,
    this.folderView = false,
    this.onRemove,
    this.controller,
  });
  @override
  State<LibraryCollectionPane> createState() => _LibraryCollectionPaneState();
}

class _LibraryCollectionPaneState extends State<LibraryCollectionPane> {
  final _requests = RequestScope();
  final _items = <LibraryEntry>[];
  final _entryFocus = <int, FocusNode>{};
  final _scroll = ScrollController();
  final _backFocus = FocusNode(canRequestFocus: false);
  bool _initialFocusPending = true;
  bool _opening = false;

  void _focusControl(FocusNode anchor) {
    if (!mounted ||
        !TickerMode.valuesOf(context).enabled ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final target = anchor.descendants
        .where((node) => node.canRequestFocus && !node.skipTraversal)
        .firstOrNull;
    target?.requestFocus();
  }

  void _focusInitialItem() {
    if (!_initialFocusPending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading || !TickerMode.valuesOf(context).enabled) return;
      if (_items.isNotEmpty) {
        _initialFocusPending = false;
        _focusControl(_entryFocus[_items.first.id]!);
      } else if (widget.onBack != null && widget.showHeader) {
        _focusControl(_backFocus);
      }
    });
  }

  @override
  void dispose() {
    if (widget.controller?._remove == _removeEntry) {
      widget.controller?._remove = null;
    }
    _generation++;
    _requests.dispose();
    _scroll.dispose();
    for (final node in _entryFocus.values) {
      node.dispose();
    }
    _backFocus.dispose();
    super.dispose();
  }

  int _page = 0, _generation = 0;
  bool _loading = false, _more = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    widget.controller?._remove = _removeEntry;
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant LibraryCollectionPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._remove == _removeEntry) {
        oldWidget.controller?._remove = null;
      }
      widget.controller?._remove = _removeEntry;
    }
  }

  void _removeEntry(int id) {
    if (mounted) setState(() => _items.removeWhere((entry) => entry.id == id));
  }

  Future<void> _openEntry(LibraryEntry item) async {
    if (_opening) return;
    _opening = true;
    final anchor = _entryFocus[item.id];
    final oldIndex = _items.indexWhere((entry) => entry.id == item.id);
    try {
      await widget.onOpen(item);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      _opening = false;
      if (mounted && anchor != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_items.any((entry) => entry.id == item.id)) {
            _focusControl(anchor);
          } else if (_items.isNotEmpty) {
            final next = _items[oldIndex.clamp(0, _items.length - 1)];
            final target = _entryFocus[next.id];
            if (target != null) _focusControl(target);
          }
        });
        setState(() {});
      }
    }
  }

  bool _removing = false;
  Future<void> _remove(LibraryEntry item) async {
    if (_removing || widget.onRemove == null) return;
    _removing = true;
    try {
      final yes = await confirmAccountAction(
        context,
        title: '移出此收藏夹？',
        message: '将「${item.title}」从当前收藏夹移除，其他收藏夹不受影响。',
        confirm: '确认移除',
      );
      if (!yes || !mounted) return;
      await widget.onRemove!(item);
      if (mounted) await _load(reset: true);
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      _removing = false;
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading && !reset) return;
    final version = ++_generation, next = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _requests.run(
        () => widget.loader(next),
        replace: reset,
      );
      if (!mounted || version != _generation) return;
      setState(() {
        if (reset) _items.clear();
        final ids = _items.map((e) => e.id).toSet();
        _items.addAll(result.items.where((e) => ids.add(e.id)));
        _page = next;
        _more = result.hasMore;
      });
    } catch (_) {
      if (mounted && version == _generation) {
        setState(() => _error = '加载失败，请检查登录状态或网络后重试');
      }
    } finally {
      if (mounted && version == _generation) {
        setState(() => _loading = false);
        if (reset) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final ids = _items.map((e) => e.id).toSet();
            for (final id in _entryFocus.keys.toList()) {
              if (!ids.contains(id)) _entryFocus.remove(id)?.dispose();
            }
          });
        }
        _focusInitialItem();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return PopScope(
      canPop: widget.onBack == null || !widget.showHeader,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.onBack != null && widget.showHeader) {
          if (widget.folderView) {
            widget.onBack!();
          } else {
            _focusControl(_backFocus);
          }
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 14 * ui,
                vertical: 12 * ui,
              ),
              child: Row(
                children: [
                  if (widget.onBack != null && !widget.folderView) ...[
                    Focus(
                      focusNode: _backFocus,
                      canRequestFocus: false,
                      child: PinkButton(
                        ui: ui,
                        height: 42,
                        fontSize: 20,
                        horizontalPadding: 18,
                        label: '返回',
                        icon: Icons.arrow_back_rounded,
                        onPressed: widget.onBack!,
                      ),
                    ),
                    SizedBox(width: 18 * ui),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 26 * ui,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (widget.onRemove != null && !widget.folderView) ...[
                    Text(
                      '菜单键 / 长按移除',
                      style: TextStyle(
                        fontSize: 18 * ui,
                        color: Colors.black54,
                      ),
                    ),
                    SizedBox(width: 16 * ui),
                  ],
                  if (!widget.folderView)
                    PinkButton(
                      ui: ui,
                      height: 42,
                      fontSize: 20,
                      horizontalPadding: 18,
                      label: '刷新',
                      icon: Icons.refresh_rounded,
                      onPressed: () => _load(reset: true),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: _loading
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error ?? '暂无内容',
                                style: TextStyle(
                                  fontSize: 23 * ui,
                                  color: Colors.black54,
                                ),
                              ),
                              if (_error != null || _more) ...[
                                SizedBox(height: 18 * ui),
                                PinkButton(
                                  ui: ui,
                                  label: _error != null ? '重试' : '加载下一页',
                                  onPressed: () => _load(reset: _error != null),
                                ),
                              ],
                            ],
                          ),
                  )
                : GridView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.all(14 * ui),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 480 * ui,
                      childAspectRatio: 1.3,
                      mainAxisSpacing: 24 * ui,
                      crossAxisSpacing: 24 * ui,
                    ),
                    itemCount:
                        _items.length +
                        (_more || _loading || _error != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        return Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : PinkButton(
                                  ui: ui,
                                  label: _error != null ? '重试' : '加载更多',
                                  onPressed: () => _load(),
                                ),
                        );
                      }
                      final item = _items[index];
                      return Focus(
                        key: ValueKey(item.id),
                        focusNode: _entryFocus.putIfAbsent(
                          item.id,
                          () => FocusNode(canRequestFocus: false),
                        ),
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey ==
                                  LogicalKeyboardKey.contextMenu &&
                              widget.onRemove != null) {
                            _remove(item);
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        canRequestFocus: false,
                        child: GestureDetector(
                          onLongPress: widget.onRemove == null
                              ? null
                              : () => _remove(item),
                          child: _LibraryCard(
                            item: item,
                            onTap: () => _openEntry(item),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class LibraryTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const LibraryTab({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return GestureDetector(
      onTap: onTap,
      child: DpadFocusable(
        onSelect: onTap,
        builder: pinkFocusEffect(
          ui: ui,
          radius: 18 * ui,
          backgroundColor: selected ? focusableSurfaceColor : Colors.white,
          focusedBackgroundColor: Colors.white,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 22 * ui, vertical: 14 * ui),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? navigationAccentColor : Colors.black54,
                size: 28 * ui,
              ),
              SizedBox(width: 12 * ui),
              Text(
                label,
                style: TextStyle(
                  fontSize: 24 * ui,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? navigationAccentColor : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  final LibraryEntry item;
  final VoidCallback onTap;
  const _LibraryCard({required this.item, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return GestureDetector(
      onTap: onTap,
      child: DpadFocusable(
        onSelect: onTap,
        builder: pinkFocusEffect(
          ui: ui,
          radius: 20 * ui,
          backgroundColor: Colors.white,
          scale: 1.02,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16 * ui),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.cover.isEmpty
                        ? ColoredBox(
                            color: focusableSurfaceColor,
                            child: Icon(
                              Icons.video_library_rounded,
                              color: navigationAccentColor,
                              size: 56 * ui,
                            ),
                          )
                        : BilibiliNetworkImage(item.cover),
                    if (item.subtitle.isNotEmpty)
                      Positioned(
                        left: 10 * ui,
                        right: 10 * ui,
                        bottom: 10 * ui,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8 * ui,
                              vertical: 4 * ui,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8 * ui),
                            ),
                            child: Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17 * ui,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 12 * ui,
                  vertical: 8 * ui,
                ),
                child: FixedLineAdaptiveText(
                  item.title,
                  line: 2,
                  maxFontSize: 22 * ui,
                  lineHeight: 1.2,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
