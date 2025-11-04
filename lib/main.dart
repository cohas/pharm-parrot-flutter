import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'package:pharm_parrot_flutter/screens/main_screen.dart';
import 'package:pharm_parrot_flutter/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(),
  );
  runApp(const PharmParrotApp());
}

class PharmParrotApp extends StatelessWidget {
  const PharmParrotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PharmParrot',
      theme: AppTheme.light(),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}










