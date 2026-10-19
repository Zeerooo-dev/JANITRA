import 'package:flutter/services.dart';

class SensitiveScreen {
  static const _channel = MethodChannel('janitra/security');
  static int _count = 0;
  static Future<void> _pending = Future.value();
  static Future<void> enter() {
    _count++;
    return _set();
  }

  static Future<void> leave() {
    if (_count > 0) _count--;
    return _set();
  }

  static Future<void> _set() {
    final enabled = _count > 0;
    return _pending = _pending.then((_) async {
      try {
        await _channel.invokeMethod<void>('sensitive', enabled);
      } on MissingPluginException {
        /* Non-Android tests have no platform window. */
      }
    });
  }
}
