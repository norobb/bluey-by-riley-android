import 'package:flutter/services.dart';

typedef HotKeyHandler = void Function();

enum HotKeyAction {
  toggleAwake, // ⌥Space
  pointHere,   // ⌃⌥P
  toggleFollow,// ⌃⌥F
  goHome,      // ⌃⌥D
  talkTest,    // ⌃⌥T
  toggleShow,  // ⌃⌥H
  stopActions; // ⌃⌥S
}

class GlobalHotKeyManager {
  static final GlobalHotKeyManager _instance = GlobalHotKeyManager._internal();
  factory GlobalHotKeyManager() => _instance;
  GlobalHotKeyManager._internal();

  final Map<HotKeyAction, HotKeyHandler> _handlers = {};

  void register(HotKeyAction action, HotKeyHandler handler) {
    _handlers[action] = handler;
  }

  void unregister(HotKeyAction action) {
    _handlers.remove(action);
  }

  void trigger(HotKeyAction action) {
    _handlers[action]?.call();
  }

  bool handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isControl = HardwareKeyboard.instance.isControlPressed;

    if (isAlt && event.logicalKey == LogicalKeyboardKey.space) {
      trigger(HotKeyAction.toggleAwake);
      return true;
    } else if (isControl && isAlt) {
      if (event.logicalKey == LogicalKeyboardKey.keyP) {
        trigger(HotKeyAction.pointHere);
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
        trigger(HotKeyAction.toggleFollow);
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.keyD) {
        trigger(HotKeyAction.goHome);
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.keyT) {
        trigger(HotKeyAction.talkTest);
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.keyH) {
        trigger(HotKeyAction.toggleShow);
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
        trigger(HotKeyAction.stopActions);
        return true;
      }
    }
    return false;
  }

  void handleRawKeyEvent(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;

    final isAlt = event.isAltPressed;
    final isControl = event.isControlPressed;

    if (isAlt && event.logicalKey == LogicalKeyboardKey.space) {
      trigger(HotKeyAction.toggleAwake);
    } else if (isControl && isAlt) {
      if (event.logicalKey == LogicalKeyboardKey.keyP) {
        trigger(HotKeyAction.pointHere);
      } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
        trigger(HotKeyAction.toggleFollow);
      } else if (event.logicalKey == LogicalKeyboardKey.keyD) {
        trigger(HotKeyAction.goHome);
      } else if (event.logicalKey == LogicalKeyboardKey.keyT) {
        trigger(HotKeyAction.talkTest);
      } else if (event.logicalKey == LogicalKeyboardKey.keyH) {
        trigger(HotKeyAction.toggleShow);
      } else if (event.logicalKey == LogicalKeyboardKey.keyS) {
        trigger(HotKeyAction.stopActions);
      }
    }
  }
}
