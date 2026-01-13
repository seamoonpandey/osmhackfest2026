import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'core/theme.dart';
import 'screens/map_screen.dart';
import 'core/local_storage.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await LocalStorage.init();

  // Wait for 2 seconds to show off the beautiful splash
  await Future.delayed(const Duration(seconds: 2));

  FlutterNativeSplash.remove();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoadWatch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MapScreen(),
    );
  }
}
