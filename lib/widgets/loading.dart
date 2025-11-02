import 'package:flutter/material.dart';

class LoadingWidget<T> extends StatefulWidget {
  final Future<T> Function() loader;
  final Widget Function(BuildContext, T) builder;

  const LoadingWidget({super.key, required this.loader, required this.builder});

  @override
  State<LoadingWidget<T>> createState() => _Loading<T>();
}

class _Loading<T> extends State<LoadingWidget<T>> {
  final _isLoading = ValueNotifier(true);
  late T _data;

  @override
  void initState() {
    super.initState();
    widget.loader().then((data) {
      _data = data;
      _isLoading.value = false;
    });
  }

  @override
  void dispose() {
    _isLoading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isLoading,
      builder: (context, isLoading, _) {
        if (isLoading) return _buildLoading();
        return widget.builder(context, _data);
      },
    );
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
