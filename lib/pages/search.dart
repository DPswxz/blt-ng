import 'package:blt/utils/request_scope.dart';
import 'dart:async';

import 'package:blt/apis/bilibili/search.dart';
import 'package:blt/apis/bilibili/toview.dart';
import 'package:blt/consts/assets.dart';
import 'package:blt/consts/color.dart';
import 'package:blt/consts/search.dart';
import 'package:blt/models/video.dart' show MediaCardInfo;
import 'package:blt/pages/qr_login.dart' show showQrLoginDialog;
import 'package:blt/pages/video_detail.dart';
import 'package:blt/storages/auth.dart';
import 'package:blt/storages/search_history.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/focusable_chip.dart';
import 'package:blt/widgets/loading.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:blt/widgets/search_panels.dart';
import 'package:blt/widgets/tooltip.dart';
import 'package:blt/widgets/video_grid_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

// 搜索页状态：未登录 / 未搜索 / 搜索中 / 有结果 / 无结果 / 失败
enum _SearchState { loginRequired, idle, searching, success, empty, error }

class SearchPage extends StatefulWidget {
  // 侧栏搜索入口的通知：在搜索页再次点击侧栏"搜索"时聚焦输入框
  final ValueNotifier<int>? tappedListener;

  const SearchPage({super.key, this.tappedListener});

  @override
  State<SearchPage> createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> with WidgetsBindingObserver {
  final _requests = RequestScope();
  final _suggestRequests = RequestScope();
  final _searchRequests = RequestScope();
  bool _editing = false;
  bool _keyboardVisible = false;
  static const _suggestDebounce = Duration(milliseconds: 250);
  static const _hotWordCount = 10;

  final _inputFocusNode = FocusNode(debugLabel: 'searchInput');
  final _pageKeyFocusNode = FocusNode(
    canRequestFocus: false,
    debugLabel: 'searchPage',
  );
  final _searchController = TextEditingController();
  // 联想词单独用 ValueNotifier，避免每次联想都重建整个页面
  final _suggestions = ValueNotifier<List<String>>(const []);

  late final VideoGridViewProvider _provider;
  late _SearchState _state;

  String _keyword = '';
  SearchOrder _order = SearchOrder.totalrank;
  SearchDuration _duration = SearchDuration.all;
  int _page = 0; // 已成功提交的页码
  int _total = 0;
  int _searchSeq = 0; // 搜索请求序号，丢弃过期结果
  int _suggestSeq = 0; // 联想请求序号
  Timer? _suggestTimer;
  List<String> _history = const [];
  List<String> _hotWords = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final loggedIn = loginInfoNotifier.value.isLogin;
    _state = loggedIn ? _SearchState.idle : _SearchState.loginRequired;
    _provider = VideoGridViewProvider(onLoad: _onLoad);
    widget.tappedListener?.addListener(_onEntryTapped);
    _loadHistory();
    if (loggedIn) _loadHotWords();
  }

  @override
  void dispose() {
    _requests.dispose();
    _suggestRequests.dispose();
    _searchRequests.dispose();
    _searchSeq++;
    _suggestSeq++;
    WidgetsBinding.instance.removeObserver(this);
    _suggestTimer?.cancel();
    _suggestions.dispose();
    _searchController.dispose();
    _inputFocusNode.dispose();
    _pageKeyFocusNode.dispose();
    widget.tappedListener?.removeListener(_onEntryTapped);
    _provider.dispose();
    super.dispose();
  }

  // 返回键：联想面板展开时只收面板与键盘，不退出页面
  KeyEventResult _onKeyEvent(KeyEvent event) {
    if (event is KeyUpEvent &&
        event.logicalKey == LogicalKeyboardKey.goBack &&
        _suggestions.value.isNotEmpty) {
      _closeSuggestions();
      dismissInput();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didChangeMetrics() {
    final visible =
        WidgetsBinding
            .instance
            .platformDispatcher
            .views
            .first
            .viewInsets
            .bottom >
        0;
    if (_keyboardVisible && !visible && _editing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editing) dismissInput();
      });
    }
    _keyboardVisible = visible;
  }

  void _beginEditing() {
    if (_state == _SearchState.loginRequired || _editing) return;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editing) return;
      _inputFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  bool dismissInput() {
    if (!_editing && _suggestions.value.isEmpty) return false;
    _closeSuggestions();
    setState(() => _editing = false);
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    _inputFocusNode.requestFocus();
    return true;
  }

  void _closeSuggestions() {
    _suggestTimer?.cancel();
    _suggestSeq++;
    _suggestions.value = const [];
  }

  void focusInput() => _onEntryTapped();

  // 再次进入只聚焦输入框，确认后才编辑。
  void _onEntryTapped() {
    if (_state == _SearchState.loginRequired) return;
    if (_editing) dismissInput();
    _inputFocusNode.requestFocus();
  }

  Future<void> _loadHistory() async {
    final history = await SearchHistory.load();
    if (!mounted) return;
    setState(() => _history = history);
  }

  Future<void> _loadHotWords() async {
    try {
      final words = await _requests.run(
        () => searchHotWords(limit: _hotWordCount),
      );
      if (!mounted) return;
      setState(() => _hotWords = words);
    } catch (_) {
      // 热搜加载失败静默处理，不影响搜索本身
    }
  }

  // 输入联想：防抖 + 序号防串台，失败静默
  void _onKeywordChanged(String text) {
    _suggestTimer?.cancel();
    final keyword = text.trim();
    if (keyword.isEmpty) {
      _closeSuggestions();
      return;
    }
    _suggestTimer = Timer(_suggestDebounce, () => _requestSuggest(keyword));
  }

  Future<void> _requestSuggest(String keyword) async {
    final seq = ++_suggestSeq;
    try {
      final words = await _suggestRequests.run(
        () => searchSuggest(keyword),
        replace: true,
      );
      if (!mounted || seq != _suggestSeq) return;
      // 输入框内容已变化时丢弃过期联想
      if (_searchController.text.trim() != keyword) return;
      _suggestions.value = words;
    } catch (_) {
      // 联想失败静默处理
    }
  }

  // 点击历史/热搜/联想词：回填输入框并直接搜索
  void _onWordTapped(String word) {
    _closeSuggestions();
    _searchController.text = word;
    _searchController.selection = TextSelection.collapsed(offset: word.length);
    FocusManager.instance.primaryFocus?.unfocus();
    _onSubmit(text: word);
  }

  void _onSubmit({String? text}) {
    final keyword = (text ?? _searchController.text).trim();
    if (keyword.isEmpty) return;
    if (!loginInfoNotifier.value.isLogin) {
      pushTooltipInfo(context, '请先点击屏幕左上的默认头像进行登录！');
      return;
    }

    if (_editing) setState(() => _editing = false);
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    // 提交后收起键盘与联想面板，避免遮挡结果
    FocusManager.instance.primaryFocus?.unfocus();
    _closeSuggestions();
    unawaited(SearchHistory.add(keyword).then((_) => _loadHistory()));
    unawaited(_runSearch(keyword));
  }

  // 发起一次搜索（首屏）：成功才提交页码与总数
  Future<void> _runSearch(String keyword) async {
    final seq = ++_searchSeq;
    _provider.clear();
    setState(() {
      _keyword = keyword;
      _state = _SearchState.searching;
    });

    try {
      final result = await _searchRequests.run(
        () =>
            searchVideos(keyword, page: 1, order: _order, duration: _duration),
        replace: true,
      );
      if (!mounted || seq != _searchSeq) return;

      _page = 1;
      _total = result.total;
      _provider.clear();
      _provider.addAll(result.videos);
      _provider.hasMore = result.pages > 1 && result.videos.isNotEmpty;
      setState(() {
        _state = result.videos.isEmpty
            ? _SearchState.empty
            : _SearchState.success;
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() => _state = _SearchState.error);
    }
  }

  // 翻页：失败不提交页码，重试时仍请求同一页
  Future<(List<MediaCardInfo>, bool)> _onLoad({
    bool isFetchMore = false,
  }) async {
    if (!isFetchMore) {
      // 首屏由页面自己发起（autoRefresh: false），这里只做防御性返回
      return (const <MediaCardInfo>[], _provider.hasMore);
    }

    final seq = _searchSeq;
    final page = _page + 1;
    final result = await searchVideos(
      _keyword,
      page: page,
      order: _order,
      duration: _duration,
    );
    if (seq != _searchSeq) {
      return (const <MediaCardInfo>[], _provider.hasMore);
    }
    _page = page;
    return (result.videos, page < result.pages && result.videos.isNotEmpty);
  }

  void _onOrderChanged(SearchOrder order) {
    if (_order == order) return;
    setState(() => _order = order);
    unawaited(_runSearch(_keyword));
  }

  void _onDurationChanged(SearchDuration duration) {
    if (_duration == duration) return;
    setState(() => _duration = duration);
    unawaited(_runSearch(_keyword));
  }

  Future<void> _onClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      barrierDismissible: false,
      builder: (dialogContext) => _buildClearHistoryDialog(dialogContext),
    );
    if (confirmed != true || !mounted) return;

    await SearchHistory.clear();
    if (!mounted) return;
    setState(() => _history = const []);
  }

  void _onVideoTapped(_, MediaCardInfo video) {
    // Keep the history, not the heavy result grid hidden beneath the detail route.
    _searchSeq++;
    _searchRequests.cancel();
    _provider.clear();
    _closeSuggestions();
    _searchController.clear();
    _inputFocusNode.unfocus();
    setState(() {
      _editing = false;
      _keyword = '';
      _page = 0;
      _total = 0;
      _state = _SearchState.idle;
    });
    Get.to(() => VideoDetailPageWrap(avid: video.avid, cid: video.cid));
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return KeyboardListener(
      focusNode: _pageKeyFocusNode,
      onKeyEvent: _onKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 输入框宽度跟随内容区宽度，窄屏不溢出
          final inputWidth = (constraints.maxWidth * 0.45).clamp(
            560 * ui,
            880 * ui,
          );
          if (_state == _SearchState.idle) {
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 1400 * ui),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(vertical: 32 * ui),
                  child: Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSearchBar(ui, inputWidth),
                          SizedBox(height: 20 * ui),
                          SearchIdlePanel(
                            history: _history,
                            hotWords: _hotWords,
                            scrollable: false,
                            onSearch: _onWordTapped,
                            onClearHistory: () => unawaited(_onClearHistory()),
                          ),
                        ],
                      ),
                      Positioned(
                        top: 80 * ui,
                        left: 0,
                        right: 0,
                        child: _buildSuggestions(inputWidth),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.only(top: 24 * ui, bottom: 16 * ui),
                child: _buildSearchBar(ui, inputWidth),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildContent(ui)),
                    // 联想浮层：输入框正下方，不推动下方内容
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildSuggestions(inputWidth),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSuggestions(double inputWidth) =>
      ValueListenableBuilder<List<String>>(
        valueListenable: _suggestions,
        builder: (context, suggestions, _) {
          if (suggestions.isEmpty) {
            return const SizedBox.shrink();
          }
          return Center(
            child: SizedBox(
              width: inputWidth,
              child: SearchSuggestPanel(
                keyword: _searchController.text,
                suggestions: suggestions,
                onSelected: _onWordTapped,
              ),
            ),
          );
        },
      );

  Widget _buildSearchBar(double ui, double inputWidth) {
    // 未登录时整行不可聚焦并灰化，避免搜了没结果还不知道原因
    final disabled = _state == _SearchState.loginRequired;
    return ExcludeFocus(
      excluding: disabled,
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: inputWidth,
              height: 72 * ui,
              child: _buildInput(ui),
            ),
            SizedBox(width: 16 * ui),
            PinkButton(
              ui: ui,
              label: '搜索',
              icon: Icons.search_rounded,
              height: 72,
              onPressed: _onSubmit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(double ui) {
    return ListenableBuilder(
      listenable: _inputFocusNode,
      builder: (context, _) => buildPinkFocusEffect(
        ui: ui,
        radius: 36 * ui,
        isFocused: _inputFocusNode.hasFocus,
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        focusedBackgroundColor: Colors.white,
        scale: 1.01,
        child: CallbackShortcuts(
          bindings: {
            if (!_editing) ...{
              const SingleActivator(LogicalKeyboardKey.enter): _beginEditing,
              const SingleActivator(LogicalKeyboardKey.select): _beginEditing,
              const SingleActivator(LogicalKeyboardKey.numpadEnter):
                  _beginEditing,
            },
            for (final entry in {
              LogicalKeyboardKey.arrowUp: TraversalDirection.up,
              LogicalKeyboardKey.arrowDown: TraversalDirection.down,
              LogicalKeyboardKey.arrowLeft: TraversalDirection.left,
              LogicalKeyboardKey.arrowRight: TraversalDirection.right,
            }.entries)
              SingleActivator(entry.key): () {
                // The native TV keyboard consumes its own arrow keys. Once keys
                // reach Flutter again, restore navigation even if no inset event arrived.
                if (_editing) dismissInput();
                _inputFocusNode.focusInDirection(entry.value);
              },
          },
          child: TextField(
            readOnly: !_editing,
            showCursor: _editing,
            onTap: _beginEditing,
            controller: _searchController,
            focusNode: _inputFocusNode,
            textAlignVertical: TextAlignVertical.center,
            textInputAction: TextInputAction.search,
            cursorColor: biliPink,
            style: TextStyle(fontSize: 24 * ui, color: Colors.black87),
            decoration: InputDecoration(
              border: InputBorder.none,
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 32 * ui,
                color: biliPink,
              ),
              hintText: '请输入搜索内容',
              hintStyle: TextStyle(
                fontSize: 24 * ui,
                color: Colors.grey.shade500,
              ),
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: _onKeywordChanged,
            onSubmitted: (text) => _onSubmit(text: text),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(double ui) {
    switch (_state) {
      case _SearchState.loginRequired:
        return _buildLoginGuide(ui);
      case _SearchState.idle:
        return _buildIdlePanel(ui);
      case _SearchState.searching:
      case _SearchState.success:
      case _SearchState.empty:
      case _SearchState.error:
        // 结果头部常驻：切换排序/时长时重建不会把焦点甩掉
        return Column(
          children: [
            SearchResultHeader(
              keyword: _keyword,
              total: _total,
              searching: _state == _SearchState.searching,
              order: _order,
              duration: _duration,
              // 首次出现时把焦点从输入框带到结果区，避免提交后焦点悬空
              autofocusFirst: true,
              onOrderChanged: _onOrderChanged,
              onDurationChanged: _onDurationChanged,
            ),
            Expanded(child: _buildResultBody(ui)),
          ],
        );
    }
  }

  Widget _buildResultBody(double ui) {
    switch (_state) {
      case _SearchState.searching:
        return buildLoadingStyle1();
      case _SearchState.error:
        return buildErrorRetryWidget(() => unawaited(_runSearch(_keyword)));
      case _SearchState.empty:
        return _buildEmptyResult(ui);
      default:
        return VideoGridView(
          provider: _provider,
          autoRefresh: false,
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
          noItemsWidget: FractionallySizedBox(
            widthFactor: 0.2,
            child: Image.asset(Images.empty, fit: BoxFit.contain),
          ),
        );
    }
  }

  Widget _buildIdlePanel(double ui) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 1400 * ui),
        child: SearchIdlePanel(
          history: _history,
          hotWords: _hotWords,
          autofocusFirst: true,
          onSearch: _onWordTapped,
          onClearHistory: () => unawaited(_onClearHistory()),
        ),
      ),
    );
  }

  // 无结果时给热搜兜底，避免用户困在空页面
  Widget _buildEmptyResult(double ui) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: 24 * ui, horizontal: 48 * ui),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 72 * ui,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: 16 * ui),
            Text(
              '没有找到「$_keyword」相关视频',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28 * ui, color: Colors.grey.shade700),
            ),
            if (_hotWords.isNotEmpty) ...[
              SizedBox(height: 32 * ui),
              Text(
                '试试这些热搜',
                style: TextStyle(
                  fontSize: 24 * ui,
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: 16 * ui),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16 * ui,
                runSpacing: 16 * ui,
                children: [
                  for (final word in _hotWords.take(5))
                    FocusableChip(
                      label: word,
                      onTap: () => _onWordTapped(word),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoginGuide(double ui) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_circle_rounded, size: 96 * ui, color: biliPink),
          SizedBox(height: 16 * ui),
          Text(
            '登录后即可搜索视频',
            style: TextStyle(fontSize: 28 * ui, color: Colors.black87),
          ),
          SizedBox(height: 24 * ui),
          PinkButton(
            ui: ui,
            label: '去登录',
            icon: Icons.qr_code_rounded,
            autofocus: true,
            onPressed: () => showQrLoginDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildClearHistoryDialog(BuildContext dialogContext) {
    final ui = context.ui;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: 640 * ui),
        padding: EdgeInsets.fromLTRB(28 * ui, 20 * ui, 28 * ui, 20 * ui),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(24 * ui),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 40 * ui,
              offset: Offset(0, 12 * ui),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8 * ui),
                  decoration: BoxDecoration(
                    gradient: pinkGradient,
                    borderRadius: BorderRadius.circular(12 * ui),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.white,
                    size: 26 * ui,
                  ),
                ),
                SizedBox(width: 12 * ui),
                Text(
                  '清空搜索历史',
                  style: TextStyle(
                    fontSize: 30 * ui,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            SizedBox(height: 14 * ui),
            Divider(
              height: 2 * ui,
              color: Colors.black.withValues(alpha: 0.06),
            ),
            SizedBox(height: 16 * ui),
            Text(
              '清空后无法恢复，确定要清空全部搜索历史吗？',
              style: TextStyle(fontSize: 24 * ui, color: Colors.grey.shade700),
            ),
            SizedBox(height: 20 * ui),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PinkButton(
                  ui: ui,
                  label: '取消',
                  autofocus: true,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                SizedBox(width: 12 * ui),
                PinkButton(
                  ui: ui,
                  label: '清空',
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
