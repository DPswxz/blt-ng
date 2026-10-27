import 'dart:async';
import 'package:blt/utils/sidebar_focus_policy.dart';
import 'package:blt/consts/color.dart';
import 'package:blt/icons/iconfont.dart';
import 'package:blt/pages/dynamic.dart';
import 'package:blt/pages/history.dart';
import 'package:blt/pages/recommend.dart';
import 'package:blt/pages/search.dart';
import 'package:blt/pages/setting.dart';
import 'package:blt/pages/user_info.dart';
import 'package:blt/storages/auth.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/bilibili_image.dart';
import 'package:blt/widgets/sidebar.dart';
import 'package:blt/widgets/tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:blt/widgets/bounded_page_stack.dart';

class _PageItem {
  final IconData icon;
  final String label;
  late final Widget child;

  late final bool homePage; // 是否是首页
  late final bool needLogin; // 是否需要登陆

  final onTappedListener = ValueNotifier(0);

  _PageItem({
    required this.icon,
    required this.label,
    required Widget Function(ValueNotifier<int>) child,
    this.homePage = false,
    this.needLogin = false,
  }) {
    this.child = child(onTappedListener);
  }

  void dispose() {
    onTappedListener.dispose();
  }
}

class Page extends StatefulWidget {
  const Page({super.key});

  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  bool _exitDialogOpen = false;
  Timer? _exitBackTimer;
  final _sidebarRegion = FocusNode(
    debugLabel: 'main-sidebar',
    canRequestFocus: false,
  );
  final _contentRegion = FocusNode(
    debugLabel: 'main-content',
    canRequestFocus: false,
  );
  late final SidebarFocusPolicy _focusPolicy;
  final _searchKey = GlobalKey<SearchPageState>();
  late final List<_PageItem> _tabs;
  late ValueNotifier<int> _currentPageIndex;
  late List<FocusNode> _pageFocusNodes;

  @override
  void initState() {
    super.initState();
    _tabs = [
      _PageItem(
        icon: Icons.home_rounded,
        label: '首页',
        child: (listener) => RecommendPage(listener),
        homePage: true,
      ),

      _PageItem(
        icon: IconFont.search,
        label: '搜索',
        child: (listener) =>
            SearchPage(key: _searchKey, tappedListener: listener),
      ),
      _PageItem(
        icon: IconFont.history,
        label: '历史',
        child: (listener) => HistoryPage(listener),
        needLogin: true,
      ),
      _PageItem(
        icon: IconFont.trends,
        label: '动态',
        child: (listener) => DynamicPage(listener),
        needLogin: true,
      ),
      _PageItem(
        icon: Icons.settings_rounded,
        label: '设置',
        child: (listener) => SettingPage(refreshListener: listener),
      ),
      _PageItem(
        icon: Icons.account_circle_rounded,
        label: '我的',
        child: (listener) => UserInfoPage(refreshListener: listener),
      ),
    ];
    _pageFocusNodes = _tabs.map((e) => FocusNode()).toList();
    _currentPageIndex = ValueNotifier(_tabs.lastIndexWhere((e) => e.homePage));
    _focusPolicy = SidebarFocusPolicy(
      sidebar: _sidebarRegion,
      content: _contentRegion,
      activeTarget: () => _pageFocusNodes[_currentPageIndex.value].descendants
          .where((node) => node.canRequestFocus && !node.skipTraversal)
          .firstOrNull,
    );
  }

  @override
  void dispose() {
    _exitBackTimer?.cancel();
    _sidebarRegion.dispose();
    _contentRegion.dispose();
    _currentPageIndex.dispose();
    for (var node in _pageFocusNodes) {
      node.dispose();
    }
    for (var tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  _onTabTapped(_PageItem tab) {
    // 检查登陆，否则弹窗提醒登陆
    if (tab.needLogin && !loginInfoNotifier.value.isLogin) {
      pushTooltipInfo(
        context,
        "请先点击屏幕左上的默认头像进行登录！",
        duration: Duration(seconds: 2),
      );
      return;
    }

    final index = _tabs.indexOf(tab);
    if (_currentPageIndex.value != index) {
      _exitBackTimer?.cancel();
      _exitBackTimer = null;
      if (tab.child is SettingPage || tab.child is UserInfoPage) {
        tab.onTappedListener.value++;
      }
      _currentPageIndex.value = index;
    } else {
      tab.onTappedListener.value = DateTime.now().microsecondsSinceEpoch;
    }
  }

  void _onAvatarTapped() => _onTabTapped(_tabs.last);

  Future<void> _handleBack() async {
    if (_exitDialogOpen) return;
    if (_tabs[_currentPageIndex.value].homePage) {
      if (_exitBackTimer?.isActive == true) {
        _exitBackTimer?.cancel();
        _exitBackTimer = null;
        await SystemNavigator.pop();
      } else {
        _exitBackTimer = Timer(const Duration(seconds: 3), () {
          _exitBackTimer = null;
        });
        pushTooltipInfo(context, '再按一次返回退出应用');
      }
      return;
    }
    if (_tabs[_currentPageIndex.value].child is SearchPage) {
      _searchKey.currentState?.dismissInput();
    }
  }

  Future<void> _confirmExit() async {
    if (_exitDialogOpen) return;
    _exitDialogOpen = true;
    final ui = context.ui;
    final exit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 620 * ui,
          padding: EdgeInsets.all(32 * ui),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24 * ui),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '退出 BLT？',
                style: TextStyle(fontSize: 32 * ui, color: Colors.black),
              ),
              SizedBox(height: 28 * ui),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PinkButton(
                    ui: ui,
                    label: '继续观看',
                    autofocus: true,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                  SizedBox(width: 20 * ui),
                  PinkButton(
                    ui: ui,
                    label: '退出',
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    _exitDialogOpen = false;
    if (exit == true && mounted) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // 以1080p为基准缩放整体尺寸
    final ui = context.ui;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        // TV 场景键盘以浮层出现，不压缩布局（避免侧边栏在键盘弹出时溢出）
        resizeToAvoidBottomInset: false,
        body: Container(
          decoration: const BoxDecoration(gradient: pageBackgroundGradient),
          child: FocusTraversalGroup(
            policy: _focusPolicy,
            child: Row(
              children: [
                ValueListenableBuilder(
                  valueListenable: _currentPageIndex,
                  builder: (context, index, _) => Focus(
                    focusNode: _sidebarRegion,
                    canRequestFocus: false,
                    child: Sidebar(
                      onAvatarTap: _onAvatarTapped,
                      avatarFocusAnchor: _pageFocusNodes.last,
                      avatar: ListenableBuilder(
                        listenable: loginInfoNotifier,
                        builder: (context, child) => BilibiliAvatar(
                          loginInfoNotifier.value.avatar,
                          radius: 46 * ui,
                        ),
                      ),
                      footer: SidebarItemData(
                        icon: Icons.exit_to_app_rounded,
                        boldIcon: true,
                        label: '退出',
                        selected: false,
                        onTap: _confirmExit,
                      ),
                      items: [
                        for (var i = 0; i < _tabs.length - 1; i++)
                          SidebarItemData(
                            focusAnchor: _pageFocusNodes[i],
                            icon: _tabs[i].icon,
                            boldIcon: _tabs[i].child is DynamicPage,
                            label: _tabs[i].label,
                            selected: i == index,
                            autofocus: i == index,
                            onTap: () => _onTabTapped(_tabs[i]),
                            onRight: index == i && _tabs[i].child is SearchPage
                                ? () {
                                    if (_currentPageIndex.value != i) return;
                                    _searchKey.currentState?.focusInput();
                                  }
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Focus(
                    focusNode: _contentRegion,
                    canRequestFocus: false,
                    child: ValueListenableBuilder(
                      valueListenable: _currentPageIndex,
                      builder: (context, index, _) {
                        return ValueListenableBuilder<LoginInfo>(
                          valueListenable: loginInfoNotifier,
                          builder: (context, login, _) => BoundedPageStack(
                            // 登录状态变化时重建页面，避免残留在上一个账号的数据
                            key: ValueKey(login.mid),
                            index: index,
                            discardWhenInactive: {
                              _tabs.indexWhere(
                                (tab) => tab.child is SearchPage,
                              ),
                            },
                            children: _tabs.map((tab) => tab.child).toList(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
