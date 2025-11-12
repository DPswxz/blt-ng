import 'package:animated_infinite_scroll_pagination/animated_infinite_scroll_pagination.dart';
import 'package:bilitv/models/video.dart';
import 'package:bilitv/widgets/video_card.dart';
import 'package:flutter/material.dart';

class _VideoGridViewController
    with AnimatedInfinitePaginationController<MediaCardInfo> {
  final bool Function() onHasMore;
  final Future<void> Function({bool isFetchMore}) onLoad;

  _VideoGridViewController({required this.onHasMore, required this.onLoad});

  @override
  get lastPage => onHasMore();

  @override
  bool areItemsTheSame(MediaCardInfo a, MediaCardInfo b) {
    return a.avid == b.avid;
  }

  @override
  Future<void> fetchData(int page) async => onLoad(isFetchMore: page == 1);
}

class VideoGridViewProvider {
  late final _ctl = _VideoGridViewController(
    onHasMore: _onHasMore,
    onLoad: fetchData,
  );
  final List<MediaCardInfo> _videos = [];
  Future<(List<MediaCardInfo>, bool)> Function({bool isFetchMore})? onLoad;
  late bool _hasMore = onLoad == null;

  VideoGridViewProvider({this.onLoad});

  List<MediaCardInfo> toList() => _videos;

  operator [](int index) => _videos[index];

  int get length => _videos.length;
  bool get isEmpty => _videos.isEmpty;
  bool get isNotEmpty => _videos.isNotEmpty;

  void addAll(Iterable<MediaCardInfo> iterable) {
    _videos.addAll(iterable);
    _ctl.emitState(PaginationSuccessState(iterable.toList(), cached: false));
    _ctl.setTotal(_videos.length);
  }

  void clear() {
    _videos.clear();
    _ctl.refresh();
  }

  bool _onHasMore() => _hasMore;

  Future<void> fetchData({bool isFetchMore = false}) async {
    if (onLoad == null) return;

    _ctl.emitState(const PaginationLoadingState());

    final (newVideos, hasMore) = await onLoad!(isFetchMore: isFetchMore);
    _hasMore = !hasMore;
    addAll(newVideos);
  }
}

class VideoGridView extends StatelessWidget {
  final VideoGridViewProvider provider;
  final Axis scrollDirection;
  final bool shrinkWrap;
  final void Function(int index, MediaCardInfo item)? onItemTap;
  final void Function(int index, MediaCardInfo item)? onItemFocus;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final int? crossAxisCount; // 与maxCrossAxisExtent互斥
  final double? maxCrossAxisExtent; // 与crossAxisCount互斥

  const VideoGridView({
    super.key,
    required this.provider,
    this.scrollDirection = Axis.vertical,
    this.shrinkWrap = false,
    this.onItemTap,
    this.onItemFocus,
    this.mainAxisSpacing = 20.0,
    this.crossAxisSpacing = 20.0,
    this.crossAxisCount,
    this.maxCrossAxisExtent,
  });

  Widget itemBuilder(BuildContext context, int index, MediaCardInfo item) {
    return VideoCard(
      video: item,
      onTap: onItemTap == null ? null : () => onItemTap!(index, item),
      onFocus: onItemFocus == null ? null : () => onItemFocus!(index, item),
    );
  }

  @override
  Widget build(BuildContext context) {
    late SliverGridDelegate gridDelegate;
    if (crossAxisCount != null) {
      gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount!,
        childAspectRatio: 1 / videoCardAspectRatio,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      );
    } else {
      gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCrossAxisExtent ?? 400,
        childAspectRatio: videoCardAspectRatio,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
      );
    }

    if (shrinkWrap) {
      return GridView.builder(
        scrollDirection: scrollDirection,
        shrinkWrap: shrinkWrap,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: gridDelegate,
        itemCount: provider.length,
        itemBuilder: (context, index) =>
            itemBuilder(context, index, provider[index]),
      );
    }

    return AnimatedInfiniteScrollView<MediaCardInfo>(
      controller: provider._ctl,
      options: AnimatedInfinitePaginationOptions(
        scrollDirection: scrollDirection,
        gridDelegate: gridDelegate,
        itemBuilder: (context, MediaCardInfo item, int index) =>
            itemBuilder(context, index, item),
      ),
    );
  }
}
