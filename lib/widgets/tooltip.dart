import 'package:flutter/material.dart';

void pushTooltipInfo(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}
