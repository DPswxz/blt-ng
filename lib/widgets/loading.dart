import 'package:flutter/material.dart';

class LoadingWidget<T> extends StatefulWidget {
  final Future<T> Function() loader;
  final Widget Function(BuildContext, T) builder;

  const LoadingWidget({super.key, required this.loader, required this.builder});

  @override
  State<LoadingWidget<T>> createState() => _Loading<T>();
}

class _Loading<T> extends State<LoadingWidget<T>> {
  bool _isLoading = true;
  late T _data;

  @override
  void initState() {
    super.initState();
    widget.loader().then((data) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoading();
    }
    return widget.builder(context, _data);
  }

  Widget _buildLoading() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset("assets/images/loading/loading1.gif"),
            const SizedBox(height: 16),
            const Text(
              '加载中...',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
