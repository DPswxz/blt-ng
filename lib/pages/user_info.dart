import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:bilitv/apis/user.dart';
import 'package:bilitv/storages/cookie.dart' show clearCookie;

class UserInfoPage extends StatefulWidget {
  final ValueNotifier<bool> loginNotifier;

  const UserInfoPage({super.key, required this.loginNotifier});

  @override
  State<UserInfoPage> createState() => _UserInfoPageState();
}

class _UserInfoPageState extends State<UserInfoPage> {
  MySelf? _me;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await getMySelfInfo();
      setState(() {
        _me = info;
        _loading = false;
      });
    } on AuthError catch (e) {
      clearCookie();
      widget.loginNotifier.value = false;
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await clearCookie();
    setState(() {
      _me = null;
      _loading = true;
    });
    widget.loginNotifier.value = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_me == null) {
      return Center(child: Text('未登录'));
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundImage: CachedNetworkImageProvider(_me!.avatar),
              radius: 100,
            ),
            const SizedBox(width: 30),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _me!.name,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('等级 ${_me!.level}', style: const TextStyle(fontSize: 20)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 30),
        ElevatedButton(onPressed: _logout, child: const Text('退出登录')),
      ],
    );
  }
}
