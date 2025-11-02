import 'package:bilitv/pages/user_entry.dart';
import 'package:bilitv/pages/rcmd_page.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final _tabs = const [Tab(text: '我的'), Tab(text: '推荐')];
  final _tabTappedListeners = [ValueNotifier(0), ValueNotifier(0)];
  late final List<StatefulWidget> _tabChildren = [
    UserEntryPage(_tabTappedListeners[0]),
    RecommendPage(_tabTappedListeners[1]),
  ];
  late TabController _tabController;
  late List<FocusNode> _tabFocusNodes;

  @override
  void initState() {
    _tabController = TabController(vsync: this, length: _tabs.length);
    _tabFocusNodes = _tabs.map((e) => FocusNode()).toList();
    super.initState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var listener in _tabTappedListeners) {
      listener.dispose();
    }
    for (var node in _tabFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  _onTabFocusChanged(focus, index) {
    if (!focus) return;
    _tabController.animateTo(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  _onTabChicked(index) {
    _tabTappedListeners[index].value = DateTime.now().microsecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TabBar(
        controller: _tabController,
        tabs: List.generate(
          _tabs.length,
          (index) => FocusableActionDetector(
            focusNode: _tabFocusNodes[index],
            autofocus: index == 1,
            child: _tabs[index],
          ),
        ).toList(),
        onFocusChange: _onTabFocusChanged,
        onTap: _onTabChicked,
      ),
      // 使用 IndexedStack 使各 tab 的子 widget 在应用启动时就被构建并保持状态
      body: ListenableBuilder(
        listenable: _tabController,
        builder: (context, _) {
          return IndexedStack(
            index: _tabController.index,
            children: _tabChildren,
          );
        },
      ),
    );
  }
}
