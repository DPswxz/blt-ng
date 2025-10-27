import 'package:flutter/material.dart';

class Loading<T> extends StatefulWidget {
  final Future<T> Function() loader;
  final Widget Function(BuildContext, T) builder;

  const Loading({super.key, required this.loader, required this.builder});

  @override
  State<Loading<T>> createState() => _Loading<T>();
}

class _Loading<T> extends State<Loading<T>> {
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.pink.shade500),
          ),
          const SizedBox(height: 16),
          Text(
            '加载中...',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
