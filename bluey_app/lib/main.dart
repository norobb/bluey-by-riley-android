import 'package:flutter/material.dart';
import 'storage/session_store.dart';
import 'ui/face_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SessionStore();
  await store.init();
  runApp(BlueyApp(store: store));
}

class BlueyApp extends StatelessWidget {
  final SessionStore store;

  const BlueyApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluey',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'IBMPlexSans',
      ),
      home: FaceScreen(store: store),
    );
  }
}
