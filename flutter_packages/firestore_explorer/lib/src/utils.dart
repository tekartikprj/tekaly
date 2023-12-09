import 'package:flutter/material.dart';

extension DocumentStateExt on State {
  void snack(String message) {
    // ignore: avoid_print
    print('snack: $message');
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
