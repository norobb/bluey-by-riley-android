import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'services/permission_manager.dart';
import 'storage/session_store.dart';
import 'ui/desktop_host_view.dart';
import 'ui/face_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SessionStore();
  await store.init();
  await PermissionManager().checkAllPermissions();
  runApp(BlueyApp(store: store));
}

class BlueyApp extends StatelessWidget {
  final SessionStore store;

  const BlueyApp({super.key, required this.store});

  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Googly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'IBMPlexSans',
      ),
      home: isDesktop ? DesktopHostView(store: store) : FaceScreen(store: store),
    );
  }
}
