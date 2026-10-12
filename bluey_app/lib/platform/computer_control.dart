import 'dart:async';
import 'dart:io';
import 'dart:ui';

class ComputerControl {
  static bool computerControlEnabled = true;
  static double stoppedUntil = 0.0;

  static const Set<String> refusedShortcuts = {
    "cmd+shift+q",
    "cmd+option+shift+q",
    "ctrl+cmd+q",
    "cmd+option+escape",
    "cmd+option+esc",
    "ctrl+alt+delete",
    "ctrl+alt+del"
  };

  static String? checkRefusal() {
    if (!computerControlEnabled) {
      return "Computer control is turned off in settings. You can still look and point.";
    }
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    if (now < stoppedUntil) {
      return "The user pressed stop. Don't do anything else until they ask again.";
    }
    return null;
  }

  static void stopActions() {
    stoppedUntil = (DateTime.now().millisecondsSinceEpoch / 1000.0) + 6.0;
  }

  static Future<String> click(Offset spot, {bool right = false, bool doubleClick = false}) async {
    final refusal = checkRefusal();
    if (refusal != null) return refusal;

    // Simulate click action
    final verb = right ? "Right-clicked" : (doubleClick ? "Double-clicked" : "Clicked");
    return "$verb at ${spot.dx.round()},${spot.dy.round()}";
  }

  static Future<String> typeText(String text, {bool pressReturn = false}) async {
    final refusal = checkRefusal();
    if (refusal != null) return refusal;

    if (text.toLowerCase().contains("password") || text.toLowerCase().contains("secret")) {
      return "That looks like sensitive data. Ask the user to type it themselves.";
    }

    if (pressReturn) {
      return "Typed '$text' and pressed Return.";
    }
    return "Typed '$text'.";
  }

  static Future<String> pressKeys(String combo) async {
    final refusal = checkRefusal();
    if (refusal != null) return refusal;

    final normalized = combo.toLowerCase().replaceAll(" ", "");
    if (refusedShortcuts.contains(normalized)) {
      return "I won't press that shortcut (it logs out, locks or force-quits). Ask the user to do it.";
    }

    return "Pressed $combo.";
  }

  static Future<String> scroll(String direction, {double amount = 3.0}) async {
    final refusal = checkRefusal();
    if (refusal != null) return refusal;

    return "Scrolled $direction.";
  }

  static Future<String> drag(Offset from, Offset to) async {
    final refusal = checkRefusal();
    if (refusal != null) return refusal;

    return "Dragged from ${from.dx.round()},${from.dy.round()} to ${to.dx.round()},${to.dy.round()}.";
  }

  static Future<String> openApp(String name) async {
    final refusal = checkRefusal();
    if (refusal != null) return refusal;

    final cleanName = name.trim();
    if (cleanName.isEmpty) return "Which app?";

    try {
      if (Platform.isLinux) {
        await Process.run('gtk-launch', [cleanName]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', cleanName]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-a', cleanName]);
      }
      return "Opened $cleanName.";
    } catch (e) {
      return "Attempted to open $cleanName.";
    }
  }

  static Future<String> openURL(String text) async {
    final refusal = checkRefusal();
    if (refusal != null) return refusal;

    var address = text.trim();
    if (!address.contains("://")) {
      address = "https://$address";
    }

    try {
      final uri = Uri.parse(address);
      if (Platform.isLinux) {
        await Process.run('xdg-open', [uri.toString()]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', uri.toString()]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [uri.toString()]);
      }
      return "Opened ${uri.host}.";
    } catch (e) {
      return "Attempted to open $address.";
    }
  }
}
