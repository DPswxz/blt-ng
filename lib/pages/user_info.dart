import 'package:blt/apis/bilibili/error.dart';
import 'package:blt/apis/bilibili/user.dart';
import 'package:blt/pages/my_library.dart';
import 'package:blt/pages/to_view.dart';
import 'package:blt/storages/auth.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/account_dialog.dart';
import 'package:blt/widgets/bilibili_image.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:flutter/material.dart';

class UserInfoPage extends StatefulWidget {
  final ValueNotifier<int>? refreshListener;
  const UserInfoPage({super.key, this.refreshListener});
  @override
  State<UserInfoPage> createState() => _UserInfoPageState();
}

class _UserInfoPageState extends State<UserInfoPage> {
  int _section = 0, _revision = 0;
  final _toViewRefresh = ValueNotifier(0);
  @override
  void initState() {
    super.initState();
    widget.refreshListener?.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.refreshListener?.removeListener(_refresh);
    _toViewRefresh.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _revision++);
    _toViewRefresh.value++;
    final mid = loginInfoNotifier.value.mid;
    if (mid == null) return;
    try {
      final info = await getMySelfInfo();
      if (mounted && loginInfoNotifier.value.mid == mid) {
        await rememberCurrentAccount(info.loginProfile, expectedMid: mid);
      }
    } on BilibiliError catch (e) {
      if (e == BilibiliError.notLoggedIn &&
          loginInfoNotifier.value.mid == mid) {
        await clearCookie();
        loginInfoNotifier.value = LoginInfo.notLogin;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return ValueListenableBuilder<LoginInfo>(
      valueListenable: loginInfoNotifier,
      builder: (context, login, _) {
        if (!login.isLogin) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('登录后查看追番追剧、收藏夹和稍后再看', style: TextStyle(fontSize: 27 * ui)),
                SizedBox(height: 24 * ui),
                PinkButton(
                  ui: ui,
                  label: '账号管理',
                  icon: Icons.manage_accounts_rounded,
                  onPressed: () => showAccountDialog(context),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: EdgeInsets.all(24 * ui),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PinkPanel(
                ui: ui,
                padding: EdgeInsets.all(20 * ui),
                child: Row(
                  children: [
                    BilibiliAvatar(login.avatar, radius: 38 * ui),
                    SizedBox(width: 24 * ui),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            login.nickname ?? '我的',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 32 * ui,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 8 * ui),
                          Text(
                            accountStatusText(login),
                            style: TextStyle(
                              fontSize: 20 * ui,
                              color: navigationAccentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 16 * ui),
                    PinkButton(
                      ui: ui,
                      label: '账号管理',
                      icon: Icons.manage_accounts_rounded,
                      onPressed: () => showAccountDialog(context),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 22 * ui),
              Row(
                children: [
                  Expanded(
                    child: LibraryTab(
                      label: '追番追剧',
                      icon: Icons.live_tv_rounded,
                      selected: _section == 0,
                      onTap: () => setState(() => _section = 0),
                    ),
                  ),
                  SizedBox(width: 18 * ui),
                  Expanded(
                    child: LibraryTab(
                      label: '收藏夹',
                      icon: Icons.folder_special_rounded,
                      selected: _section == 1,
                      onTap: () => setState(() => _section = 1),
                    ),
                  ),
                  SizedBox(width: 18 * ui),
                  Expanded(
                    child: LibraryTab(
                      label: '稍后再看',
                      icon: Icons.playlist_play_rounded,
                      selected: _section == 2,
                      onTap: () => setState(() => _section = 2),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18 * ui),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey('${login.mid}-$_revision-$_section'),
                  child: switch (_section) {
                    0 => MySubscriptions(mid: login.mid!),
                    1 => MyFavorites(mid: login.mid!),
                    _ => ToViewPage(_toViewRefresh),
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
