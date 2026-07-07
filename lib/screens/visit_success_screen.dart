import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../utils/text_styles.dart';

class VisitSuccessScreen extends StatefulWidget {
  const VisitSuccessScreen({super.key});

  @override
  State<VisitSuccessScreen> createState() => _VisitSuccessScreenState();
}

class _VisitSuccessScreenState extends State<VisitSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _slideAnim;
  late final Animation<double> _checkAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
      ),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.7, curve: Curves.easeIn),
      ),
    );

    _slideAnim = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _checkAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.6, curve: Curves.easeInOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, child) => Transform.scale(
                    scale: _scaleAnim.value,
                    child: child,
                  ),
                  child: _buildSuccessIcon(),
                ),
                const SizedBox(height: 32),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, child) => Opacity(
                    opacity: _fadeAnim.value,
                    child: Transform.translate(
                      offset: Offset(0, _slideAnim.value),
                      child: child,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Visite enregistrée !',
                        style: AppText.inter(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Votre visite a été enregistrée avec succès.\n'
                        'La synchronisation s\'effectuera automatiquement.',
                        textAlign: TextAlign.center,
                        style: AppText.inter(
                          fontSize: 14,
                          color: AppColors.textMuted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, child) => Opacity(
                    opacity: _fadeAnim.value,
                    child: child,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ikaBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/dashboard',
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.dashboard_rounded),
                      label: Text(
                        'RETOUR AU TABLEAU DE BORD',
                        style: AppText.inter(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, child) => Opacity(
                    opacity: _fadeAnim.value,
                    child: child,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/add-visit',
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: Text(
                        'AJOUTER UNE AUTRE VISITE',
                        style: AppText.inter(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessIcon() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF16A34A).withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: _checkAnim,
          builder: (_, _) => CustomPaint(
            size: const Size(60, 60),
            painter: _CheckmarkPainter(_checkAnim.value),
          ),
        ),
      ),
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  final double progress;
  _CheckmarkPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF16A34A)
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    final w = size.width;
    final h = size.height;

    final startX = w * 0.15;
    final startY = h * 0.55;
    final midX = w * 0.42;
    final midY = h * 0.75;
    final endX = w * 0.85;
    final endY = h * 0.25;

    path.moveTo(startX, startY);
    final fullLength = _calculateLength(startX, startY, midX, midY, endX, endY);
    final drawLength = fullLength * progress;

    var remaining = drawLength;
    final firstSeg = _distance(startX, startY, midX, midY);
    if (remaining <= firstSeg) {
      final t = remaining / firstSeg;
      path.lineTo(startX + (midX - startX) * t, startY + (midY - startY) * t);
    } else {
      path.lineTo(midX, midY);
      remaining -= firstSeg;
      final secondSeg = _distance(midX, midY, endX, endY);
      if (remaining > 0) {
        final t = math.min(remaining / secondSeg, 1.0);
        path.lineTo(midX + (endX - midX) * t, midY + (endY - midY) * t);
      }
    }

    canvas.drawPath(path, paint);
  }

  double _calculateLength(double x1, double y1, double x2, double y2, double x3, double y3) {
    return _distance(x1, y1, x2, y2) + _distance(x2, y2, x3, y3);
  }

  double _distance(double x1, double y1, double x2, double y2) {
    return math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
  }

  @override
  bool shouldRepaint(covariant _CheckmarkPainter oldDelegate) => oldDelegate.progress != progress;
}
