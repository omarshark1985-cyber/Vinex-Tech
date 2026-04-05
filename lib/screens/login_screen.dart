import 'dart:async';
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _firebaseConnected = false;
  Timer? _connTimer;
  StreamSubscription<bool>? _connSub;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fadeAnimation =
        Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    ));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));
    _animController.forward();
    // Subscribe to Firebase connection stream for instant UI updates
    _firebaseConnected = DatabaseService.isFirebaseConnected;
    _connSub = DatabaseService.connectionStream.listen((connected) {
      if (mounted) setState(() => _firebaseConnected = connected);
    });
    // Also poll every second as backup
    _connTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final connected = DatabaseService.isFirebaseConnected;
      if (connected != _firebaseConnected && mounted) {
        setState(() => _firebaseConnected = connected);
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _connTimer?.cancel();
    _animController.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 600));

    final user = await DatabaseService.loginAsync(
      _usernameCtrl.text.trim(),
      _passwordCtrl.text.trim(),
    );

    setState(() => _isLoading = false);

    if (user != null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(currentUser: user),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Invalid username or password. Please try again.'),
            ],
          ),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600; // تابلت أو ديسكتوب
    final cardWidth = isWide ? 460.0 : double.infinity;
    final logoSize = isWide ? 130.0 : 110.0;
    final titleFontSize = isWide ? 34.0 : 28.0;
    final hPadding = isWide ? 0.0 : 24.0;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryBlueDark,
              AppTheme.primaryBlue,
              AppTheme.primaryBlueLight,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: hPadding, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ─── Logo Section ────────────────────────────────────
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        Container(
                          width: logoSize,
                          height: logoSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius:
                                BorderRadius.circular(isWide ? 26 : 22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(isWide ? 24 : 20),
                            child: Image.asset(
                              'assets/images/company_logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.inventory_2_rounded,
                                size: 55,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Vinex Technology',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Storage Management System',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: isWide ? 16 : 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: isWide ? 40 : 32),

                  // ─── Login Card ──────────────────────────────────────
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Container(
                        width: cardWidth,
                        padding: EdgeInsets.all(isWide ? 36 : 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Welcome Back',
                                style: TextStyle(
                                  fontSize: isWide ? 26 : 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textDark,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Sign in to continue',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.textGrey,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              // ── Firebase status badge ──────────────────
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 400),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _firebaseConnected
                                      ? const Color(0xFFE8F5E9)
                                      : const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _firebaseConnected
                                        ? const Color(0xFF81C784)
                                        : const Color(0xFFFFB74D),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _firebaseConnected
                                          ? Icons.cloud_done_rounded
                                          : Icons.cloud_sync_rounded,
                                      size: 16,
                                      color: _firebaseConnected
                                          ? const Color(0xFF2E7D32)
                                          : const Color(0xFFE65100),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _firebaseConnected
                                          ? 'Cloud Connected — Data Synced'
                                          : 'Connecting to cloud...',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: _firebaseConnected
                                            ? const Color(0xFF2E7D32)
                                            : const Color(0xFFE65100),
                                      ),
                                    ),
                                    if (!_firebaseConnected) ...[
                                      const SizedBox(width: 6),
                                      const SizedBox(
                                        width: 10,
                                        height: 10,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: Color(0xFFE65100),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),

                              // Username
                              TextFormField(
                                controller: _usernameCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Username',
                                  hintText: 'Enter your username',
                                  prefixIcon: const Icon(
                                    Icons.person_outline_rounded,
                                    color: AppTheme.primaryBlue,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty)
                                        ? 'Username is required'
                                        : null,
                              ),
                              const SizedBox(height: 16),

                              // Password
                              TextFormField(
                                controller: _passwordCtrl,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  hintText: 'Enter your password',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                    color: AppTheme.primaryBlue,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: AppTheme.textGrey,
                                    ),
                                    onPressed: () => setState(() =>
                                        _obscurePassword =
                                            !_obscurePassword),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(12),
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.isEmpty)
                                        ? 'Password is required'
                                        : null,
                                onFieldSubmitted: (_) => _login(),
                              ),
                              const SizedBox(height: 28),

                              // Login Button
                              SizedBox(
                                height: 52,
                                child: ElevatedButton(
                                  onPressed:
                                      _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        AppTheme.primaryBlue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child:
                                              CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : const Text(
                                          'Sign In',
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    '© 2025 Vinex Technology v1.0',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
