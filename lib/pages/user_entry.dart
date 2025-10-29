import 'package:flutter/material.dart';
import 'package:bilitv/pages/qr_login.dart';
import 'package:bilitv/pages/user_info.dart';

class UserEntryPage extends StatefulWidget {
  const UserEntryPage({super.key});

  @override
  State<UserEntryPage> createState() => _UserEntryPageState();
}

class _UserEntryPageState extends State<UserEntryPage> {
  final ValueNotifier<bool> _loginNotifier = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _loginNotifier.addListener(_onLoginChanged);
  }

  @override
  void dispose() {
    _loginNotifier.dispose();
    super.dispose();
  }

  void _onLoginChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loginNotifier.value) {
      return UserInfoPage(loginNotifier: _loginNotifier);
    }
    return QRLoginPage(loginNotifier: _loginNotifier);
  }
}
