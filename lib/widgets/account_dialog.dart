import 'dart:math' as math;
import 'package:blt/apis/bilibili/user.dart';
import 'package:blt/pages/qr_login.dart';
import 'package:blt/storages/auth.dart';
import 'package:blt/utils/ui_scale.dart';
import 'package:blt/widgets/bilibili_image.dart';
import 'package:blt/widgets/pink_style.dart';
import 'package:blt/widgets/tooltip.dart';
import 'package:flutter/material.dart';

bool _accountPanelOpen = false;
Future<void> showAccountDialog(BuildContext context) async {
  if (_accountPanelOpen) return;
  _accountPanelOpen = true;
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => const AccountDialog(),
    );
  } finally {
    _accountPanelOpen = false;
  }
}

String accountStatusText(LoginInfo info) {
  var text = 'Lv${info.level ?? '--'} · ${info.membershipLabel}';
  if (info.vipStatus == 1 && (info.vipDueDate ?? 0) > 0) {
    final d = DateTime.fromMillisecondsSinceEpoch(info.vipDueDate!);
    text +=
        ' · ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} 到期';
  }
  return text;
}

Future<bool> confirmAccountAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
}) async {
  final ui = context.ui;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.5),
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 720 * ui,
            padding: EdgeInsets.all(32 * ui),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24 * ui),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.manage_accounts_rounded,
                      size: 32 * ui,
                      color: navigationAccentColor,
                    ),
                    SizedBox(width: 12 * ui),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 30 * ui,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24 * ui),
                Text(message, style: TextStyle(fontSize: 23 * ui, height: 1.5)),
                SizedBox(height: 28 * ui),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PinkButton(
                      ui: ui,
                      label: '取消',
                      autofocus: true,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                    SizedBox(width: 18 * ui),
                    PinkButton(
                      ui: ui,
                      label: confirm,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

class AccountDialog extends StatefulWidget {
  const AccountDialog({super.key});
  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  List<SavedAccount> _accounts = [];
  bool _loading = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final accounts = await loadSavedAccounts();
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '账号列表加载失败';
        });
      }
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await showQrLoginDialog(
        context,
        addOnly: loginInfoNotifier.value.isLogin,
      );
      if (mounted) await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switch(SavedAccount account) async {
    if (_busy || account.mid == loginInfoNotifier.value.mid) return;
    final yes = await confirmAccountAction(
      context,
      title: '切换账号？',
      message: '将切换到「${account.profile.nickname}」，并加载该账号的订阅、收藏夹和稍后再看。',
      confirm: '确认切换',
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    try {
      final cookies = await loadAccountCookies(account.mid);
      final info = await getMySelfInfo(cookies: cookies);
      if (!mounted) return;
      await switchSavedAccount(
        account.mid,
        refreshedProfile: info.loginProfile,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(SavedAccount account) async {
    if (_busy) return;
    final yes = await confirmAccountAction(
      context,
      title: '退出此账号？',
      message: '退出「${account.profile.nickname}」在此电视的登录。其他保存的账号不受影响。',
      confirm: '确认退出',
    );
    if (!yes || !mounted) return;
    setState(() => _busy = true);
    try {
      await removeSavedAccount(account.mid);
      if (mounted) await _reload();
    } catch (e) {
      if (mounted) showAppError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = context.ui;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(48 * ui),
      child: Container(
        width: 1120 * ui,
        height: math.min(780 * ui, MediaQuery.sizeOf(context).height * 0.82),
        padding: EdgeInsets.all(28 * ui),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24 * ui),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.manage_accounts_rounded,
                  color: navigationAccentColor,
                  size: 36 * ui,
                ),
                SizedBox(width: 12 * ui),
                Text(
                  '账号管理',
                  style: TextStyle(
                    fontSize: 32 * ui,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (_busy)
                  SizedBox(
                    width: 24 * ui,
                    height: 24 * ui,
                    child: const CircularProgressIndicator(),
                  ),
              ],
            ),
            SizedBox(height: 18 * ui),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: PinkButton(
                        ui: ui,
                        label: '加载失败 · 重试',
                        onPressed: _reload,
                      ),
                    )
                  : _accounts.isEmpty
                  ? Center(
                      child: Text(
                        '尚未添加账号',
                        style: TextStyle(
                          fontSize: 24 * ui,
                          color: Colors.black54,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.all(14 * ui),
                      itemCount: _accounts.length,
                      separatorBuilder: (_, _) => SizedBox(height: 18 * ui),
                      itemBuilder: (context, index) {
                        final account = _accounts[index],
                            info = account.profile;
                        final active =
                            loginInfoNotifier.value.mid == account.mid;
                        return Container(
                          padding: EdgeInsets.all(20 * ui),
                          decoration: BoxDecoration(
                            color: active
                                ? focusableSurfaceColor
                                : const Color(0xFFF8F8FA),
                            borderRadius: BorderRadius.circular(18 * ui),
                          ),
                          child: Row(
                            children: [
                              BilibiliAvatar(info.avatar, radius: 34 * ui),
                              SizedBox(width: 18 * ui),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      info.nickname ?? '账号 ${account.mid}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 25 * ui,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 7 * ui),
                                    Text(
                                      accountStatusText(info),
                                      style: TextStyle(
                                        fontSize: 18 * ui,
                                        height: 1.4,
                                        color: navigationAccentColor,
                                      ),
                                    ),
                                    if (account.needsLogin)
                                      Text(
                                        '登录已失效，请重新添加此账号',
                                        style: TextStyle(
                                          fontSize: 17 * ui,
                                          color: Colors.black54,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 16 * ui),
                              if (active)
                                Text(
                                  '正在使用',
                                  style: TextStyle(
                                    fontSize: 20 * ui,
                                    color: navigationAccentColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              else if (!account.needsLogin)
                                PinkButton(
                                  ui: ui,
                                  height: 44,
                                  fontSize: 20,
                                  horizontalPadding: 18,
                                  label: '切换',
                                  onPressed: () => _switch(account),
                                ),
                              SizedBox(width: 14 * ui),
                              PinkButton(
                                ui: ui,
                                height: 44,
                                fontSize: 20,
                                horizontalPadding: 18,
                                label: '退出登录',
                                onPressed: () => _remove(account),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(height: 16 * ui),
            Row(
              children: [
                PinkButton(
                  ui: ui,
                  label: '添加账号',
                  icon: Icons.person_add_alt_1_rounded,
                  autofocus: true,
                  onPressed: _add,
                ),
                const Spacer(),
                PinkButton(
                  ui: ui,
                  label: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
