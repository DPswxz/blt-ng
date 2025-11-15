import 'package:flutter/material.dart';

void pushTooltipInfo(
  BuildContext context,
  String text, {
  Duration duration = const Duration(milliseconds: 500),
}) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text), duration: duration));
}

void pushTooltipWarning(
  BuildContext context,
  String text, {
  Duration duration = const Duration(milliseconds: 500),
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text, style: TextStyle(color: Colors.yellow)),
      duration: duration,
    ),
  );
}
