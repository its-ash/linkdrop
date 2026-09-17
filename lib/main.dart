import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:theme/theme.dart';

import 'screens/library_screen.dart';
import 'services/download_manager.dart';
import 'services/share_intent_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DownloadManager.instance.init();
  await ShareIntentService.instance.init();
  await _requestStoragePermission();
  runApp(const LinkDropApp());
}

Future<void> _requestStoragePermission() async {
  if (await Permission.storage.isDenied) {
    await Permission.storage.request();
  }
  if (await Permission.photos.isDenied) {
    await Permission.photos.request();
  }
}

class LinkDropApp extends StatelessWidget {
  const LinkDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkDrop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: ThemeMode.system,
      home: const LibraryScreen(),
    );
  }
}
