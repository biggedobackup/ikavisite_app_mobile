import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// Duree minimale d'affichage du splash : juste assez pour que l'animation
  /// d'entree se termine, sans imposer d'attente artificielle.
  static const Duration _minSplashDuration = Duration(milliseconds: 900);

  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  // Palette identique à login_screen
  static const Color kIkaBlue = Color(0xFF1270B8);
  static const Color kIkaRed = Color(0xFFDC2626);
  static const Color kBg = Color(0xFFF4F7FB);
  static const Color kCard = Color(0xFFFFFFFF);
  static const Color kBlueSoft = Color(0xFFEFF6FF);
  static const Color kTextMuted = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.7, curve: Curves.elasticOut)),
    );

    _controller.forward();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final auth = context.read<AuthProvider>();

    // La session est restauree depuis SQLite uniquement : plus aucun appel
    // reseau ne retarde l'arrivee sur le tableau de bord. La seule attente
    // restante est celle de l'animation d'entree.
    await Future.wait<void>([
      auth.restoreLocalSession(),
      Future<void>.delayed(_minSplashDuration),
    ]);

    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      auth.isLoggedIn ? '/dashboard' : '/login',
    );

    // Rafraichissement du profil en tache de fond : ne doit jamais retarder
    // la navigation.
    unawaited(auth.refreshSessionInBackground());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: kIkaBlue.withValues(alpha: 0.10),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: kBlueSoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(10),
                      child: Image.asset('assets/images/logo.png'),
                    ),
                    const SizedBox(height: 18),

                    // Marque
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.3),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: _controller,
                          curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
                        )),
                        child: Column(
                          children: [
                            RichText(
                              text: const TextSpan(
                                style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8),
                                children: [
                                  TextSpan(text: 'IKA', style: TextStyle(color: kIkaBlue)),
                                  TextSpan(text: 'VISITE', style: TextStyle(color: kIkaRed)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "Contrôle d'accès & sécurité",
                              style: TextStyle(
                                fontSize: 12.5,
                                color: kTextMuted,
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Loader
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: Column(
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                kIkaBlue.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Chargement…',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: kTextMuted,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
