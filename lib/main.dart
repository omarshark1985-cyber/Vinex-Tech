import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';
import 'services/database_service.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Step 1: Initialize Firebase ───────────────────────────────────────────
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (kDebugMode) debugPrint('✅ Firebase.initializeApp() OK');
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('duplicate-app') || msg.contains('already exists')) {
      if (kDebugMode) debugPrint('ℹ️ Firebase already initialized');
    } else {
      if (kDebugMode) debugPrint('⚠️ Firebase init error: $e');
    }
  }

  // ── Step 2: Initialize local DB + attempt Firebase connection ─────────────
  await DatabaseService.initialize();

  runApp(const VinexTechnologyApp());
}

/// Global RouteObserver — screens subscribe to get notified when they become active
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class VinexTechnologyApp extends StatelessWidget {
  const VinexTechnologyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vinex Technology',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorObservers: [routeObserver],
      builder: (context, child) {
        // Allow a small text scale (1.0 – 1.15) so mobile text stays readable
        // but never grows so large it breaks layouts.
        final mq = MediaQuery.of(context);
        final clampedScale = mq.textScaler.scale(1.0).clamp(1.0, 1.15);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(clampedScale),
          ),
          child: child!,
        );
      },
      home: const SplashGate(),
    );
  }
}

/// SplashGate: shows a loading screen while Firebase connects,
/// then navigates to LoginScreen automatically.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  String _status = 'جاري الاتصال بالسحابة...';
  bool _done = false;
  StreamSubscription<bool>? _connSub;

  @override
  void initState() {
    super.initState();
    _waitForFirebase();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  void _waitForFirebase() {
    // Fast path: already connected
    if (DatabaseService.isFirebaseConnected) {
      _goToLogin();
      return;
    }

    // Listen to connectionStream — fires instantly when REST check completes (~1-3s)
    _connSub = DatabaseService.connectionStream.listen((connected) {
      if (!mounted) return;
      if (connected) {
        setState(() => _status = '✅ متصل بالسحابة!');
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _goToLogin();
        });
      }
    });

    // Timeout: 20 seconds max — then go to login (offline mode)
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && !_done) {
        _goToLogin();
      }
    });

    // Animate status text
    _animateStatus();
  }

  Future<void> _animateStatus() async {
    final messages = [
      'جاري الاتصال بالسحابة...',
      'جاري التحقق من قاعدة البيانات...',
      'جاري الاتصال بـ Firebase...',
      'لحظة من فضلك...',
    ];
    for (final msg in messages) {
      await Future.delayed(const Duration(seconds: 3));
      if (mounted && !_done) setState(() => _status = msg);
    }
  }

  void _goToLogin() {
    if (_done) return;
    _done = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryBlueDark, AppTheme.primaryBlue, AppTheme.primaryBlueLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/company_logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.inventory_2_rounded,
                    size: 52,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Vinex Technology',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Storage Management System',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 48),
            // Spinner
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            // Status text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _status,
                key: ValueKey(_status),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
