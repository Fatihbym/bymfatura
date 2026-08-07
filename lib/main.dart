import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/deep_link_service.dart';
import 'services/auth_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final deepLinkService = DeepLinkService();
  try {
    await deepLinkService.init().timeout(const Duration(seconds: 2));
  } catch (e) {
    debugPrint("DeepLinkService init timeout or error: $e");
  }

  final authService = AuthService();
  try {
    await authService.init().timeout(const Duration(seconds: 2));
  } catch (e) {
    debugPrint("AuthService init timeout or error: $e");
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);

  runApp(MyApp(deepLinkService: deepLinkService));
}

class MyApp extends StatelessWidget {
  final DeepLinkService deepLinkService;
  
  const MyApp({super.key, required this.deepLinkService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bym Fatura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF80C7EA)),
        useMaterial3: true,
        textTheme: GoogleFonts.nunitoSansTextTheme(ThemeData.light().textTheme),
      ),
      home: SplashScreen(deepLinkService: deepLinkService),
    );
  }
}
