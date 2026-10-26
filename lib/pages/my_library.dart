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

typedef LibraryLoader = Future<LibraryBatch> Function(int page);

class MySubscriptions extends StatefulWidget {
  final int mid;
  const MySubscriptions({super.key, required this.mid});
  @override
  State<MySubscriptions> createState() => _MySubscriptionsState();
}

class _MySubscriptionsState extends State<MySubscriptions> {
  int _type = 1;
  LibraryEntry? _season;
  Future<void> _play(LibraryEntry episode) async {
    try {
      if ((episode.aid ?? 0) <= 0 || (episode.cid ?? 0) <= 0) {
        throw StateError('该分集暂时无法播放');
      }
      final season = _season!;
      final danmu = await Settings.getBool(Settings.pathDanmuSwitch) ?? true;
      final decoder =
          await Settings.getString(Settings.pathDecoderMode) ?? 'auto';
      if (!mounted) return;
      final video = Video(
        avid: episode.aid!,
        bvid: '',
        title: '${season.title} · ${episode.title}',
        cover: episode.cover,
        desc: '',
        duration: Duration.zero,
        stat: Stat.fromJson({}),
        userMid: 0,
        userName: '哔哩哔哩番剧',
        userAvatar: '',
        publishTime: DateTime.fromMillisecondsSinceEpoch(0),
        cid: episode.cid!,
        episodes: [
          Episode(
            index: 1,
            cid: episode.cid!,
            episodeId: episode.id,
            title: episode.title,
            duration: Duration.zero,
          ),
        ],
      );
      Get.to(
        () => VideoPlayerPage(
          video: video,
          cid: episode.cid!,
          danmu: danmu,
          ha: true,
          vo: VideoOutputDrivers.gpu,
          hwdec: HardwareVideoDecoder.autoSafe,
          decoderMode: decoder,
        ),
      );
    } catch (e) {
      if (mounted) showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    if (_season != null) {
      return LibraryCollectionPane(
        key: ValueKey('season-${_season!.id}'),
        title: _season!.title,
        loader: (_) => listSeasonEpisodes(_season!.id),
        onBack: () => setState(() => _season = null),
        onOpen: _play,
      );
    }
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
            loader: (page) =>
                listFollowedSeasons(widget.mid, type: _type, page: page),
            onOpen: (item) => setState(() => _season = item),
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
  LibraryEntry? _folder;
  int _folderRevision = 0;
  @override
  Widget build(BuildContext context) {
    if (_folder != null) {
      return LibraryCollectionPane(
        key: ValueKey('folder-${_folder!.id}-$_folderRevision'),
        title: _folder!.title,
        onBack: () => setState(() => _folder = null),
        loader: (page) => listFavoriteVideos(_folder!.id, page: page),
        onRemove: (item) async {
          await changeVideoFavorite(item.video!.avid, _folder!.id, add: false);
        },
        onOpen: (item) async {
          final video = item.video;
          if (video != null) {
            await Get.to(
              () => VideoDetailPageWrap(
                avid: video.avid,
                bvid: video.bvid.isEmpty ? null : video.bvid,
                cid: video.cid,
              ),
            );
            if (mounted) setState(() => _folderRevision++);
          }
        },
      );
    }
    return LibraryCollectionPane(
      title: '我的收藏夹',
      loader: (_) => listFavoriteFolders(widget.mid),
      onOpen: (item) => setState(() => _folder = item),
    );
  }
}

class LibraryCollectionPane extends StatefulWidget {
  final String title;
  final LibraryLoader loader;
  final ValueChanged<LibraryEntry> onOpen;
  final VoidCallback? onBack;
  final Future<void> Function(LibraryEntry)? onRemove;
  const LibraryCollectionPane({
    super.key,
    required this.title,
    required this.loader,
    required this.onOpen,
    this.onBack,
    this.onRemove,
  });
  @override
  State<LibraryCollectionPane> createState() => _LibraryCollectionPaneState();
}

class _LibraryCollectionPaneState extends State<LibraryCollectionPane> {
  final _items = <LibraryEntry>[];
  int _page = 0, _generation = 0;
  bool _loading = false, _more = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
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
      final result = await widget.loader(next);
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
      if (mounted && version == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14 * ui, vertical: 12 * ui),
          child: Row(
            children: [
              if (widget.onBack != null) ...[
                PinkButton(
                  ui: ui,
                  height: 42,
                  fontSize: 20,
                  horizontalPadding: 18,
                  label: '返回',
                  icon: Icons.arrow_back_rounded,
                  onPressed: widget.onBack!,
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
              if (widget.onRemove != null) ...[
                Text(
                  '菜单键 / 长按移除',
                  style: TextStyle(fontSize: 18 * ui, color: Colors.black54),
                ),
                SizedBox(width: 16 * ui),
              ],
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
                          onTap: () => widget.onOpen(item),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
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
