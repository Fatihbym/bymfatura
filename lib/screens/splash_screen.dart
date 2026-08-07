import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../services/deep_link_service.dart';
import '../webview_screen.dart';

class SplashScreen extends StatefulWidget {
  final DeepLinkService deepLinkService;

  const SplashScreen({super.key, required this.deepLinkService});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        FlutterNativeSplash.remove();
      } catch (_) {}
      _checkAutoLogin();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkAutoLogin() async {
    await Future.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => WebViewScreen(
          deepLinkService: widget.deepLinkService,
          initialUrl: "https://bymfatura.com/accounting/login",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Arka Plan Gradyan Katmanı
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEDF2F7), Color(0xFFF8FAFC), Color(0xFFFFFFFF)],
                ),
              ),
            ),
          ),

          // Arka Plan Çizgi Animasyon Yapılandırması
          Positioned.fill(
            child: CustomPaint(
              painter: BackgroundLinesPainter(animation: _animController),
            ),
          ),

          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Kurumsal Logo Görseli
                  Hero(
                    tag: 'app_logo',
                    child: Image.asset(
                      'assets/logo.png',
                      height: 290,
                      width: 320,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          'assets/app_icon.png',
                          height: 290,
                          width: 320,
                          fit: BoxFit.contain,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 48),
                  const CircularProgressIndicator(
                    color: Color(0xFF0075FF),
                    strokeWidth: 3,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BackgroundLinesPainter extends CustomPainter {
  final Animation<double>? animation;

  BackgroundLinesPainter({this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF0075FF).withValues(alpha: 0.075)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final circlePaint = Paint()
      ..color = const Color(0xFF0075FF).withValues(alpha: 0.055)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const double step = 35.0;
    final double shift = (animation?.value ?? 0.0) * step;

    for (double i = -size.height - (step * 2); i < size.width + (step * 2); i += step) {
      final double currentX = i + shift;
      canvas.drawLine(
        Offset(currentX, 0),
        Offset(currentX + size.height, size.height),
        linePaint,
      );
    }

    final double pulse = (animation?.value ?? 0.0) * 12.0;

    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.1), 100 + pulse, circlePaint);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.1), 180 + pulse, circlePaint);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.1), 260 + pulse, circlePaint);

    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.85), 140 - pulse, circlePaint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.85), 220 - pulse, circlePaint);
  }

  @override
  bool shouldRepaint(covariant BackgroundLinesPainter oldDelegate) => true;
}
