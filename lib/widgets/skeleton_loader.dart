import 'package:flutter/material.dart';

class SkeletonLoader extends StatefulWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;

  const SkeletonLoader({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();

  static Widget box({double? width, double? height, double radius = 8, Color? color}) {
    return _SkeletonBox(width: width, height: height, radius: radius, color: color);
  }

  static Widget line({double? width, double height = 14, double radius = 4}) {
    return _SkeletonBox(width: width, height: height, radius: radius);
  }

  static Widget circle({double size = 48}) {
    return _SkeletonBox(width: size, height: size, radius: size / 2);
  }
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? Colors.grey.shade200;
    final highlight = widget.highlightColor ?? Colors.grey.shade100;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ColorFiltered(
          colorFilter: ColorFilter.mode(
            Color.lerp(highlight, base, _animation.value)!,
            BlendMode.srcATop,
          ),
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  final Color? color;

  const _SkeletonBox({
    this.width,
    this.height,
    this.radius = 8,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? Colors.grey.shade200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ── Dashboard Skeleton ──

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header banner
            Container(
              width: double.infinity,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withValues(alpha: 0.15),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader.box(width: 60, height: 12, color: Colors.white.withValues(alpha: 0.3)),
                  const SizedBox(height: 8),
                  SkeletonLoader.box(width: 140, height: 18, color: Colors.white.withValues(alpha: 0.3)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader.box(width: 100, height: 14),
                  const SizedBox(height: 12),
                  // Stats grid: 2 cols x 3 rows
                  Row(
                    children: [
                      Expanded(child: _statSkeleton()),
                      const SizedBox(width: 12),
                      Expanded(child: _statSkeleton()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _statSkeleton()),
                      const SizedBox(width: 12),
                      Expanded(child: _statSkeleton()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _statSkeleton()),
                      const SizedBox(width: 12),
                      Expanded(child: _statSkeleton()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SkeletonLoader.box(width: 160, height: 14),
                  const SizedBox(height: 12),
                  SkeletonLoader.box(width: double.infinity, height: 180, radius: 12),
                  const SizedBox(height: 20),
                  SkeletonLoader.box(width: 140, height: 14),
                  const SizedBox(height: 12),
                  SkeletonLoader.box(width: double.infinity, height: 180, radius: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statSkeleton() {
    return SkeletonLoader.box(
      height: 72,
      radius: 14,
    );
  }
}

// ── Visit Detail Skeleton ──

class VisitDetailSkeleton extends StatelessWidget {
  const VisitDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header card
            SkeletonLoader.box(width: double.infinity, height: 80, radius: 14),
            const SizedBox(height: 12),
            // Section 1
            SkeletonLoader.box(width: 140, height: 14),
            const SizedBox(height: 10),
            _rowSkeleton(),
            const SizedBox(height: 8),
            _rowSkeleton(),
            const SizedBox(height: 8),
            _rowSkeleton(),
            const SizedBox(height: 12),
            // Section 2
            SkeletonLoader.box(width: 120, height: 14),
            const SizedBox(height: 10),
            _rowSkeleton(),
            const SizedBox(height: 8),
            _rowSkeleton(),
            const SizedBox(height: 12),
            // Section 3
            SkeletonLoader.box(width: 130, height: 14),
            const SizedBox(height: 10),
            _rowSkeleton(),
            const SizedBox(height: 8),
            _rowSkeleton(),
          ],
        ),
      ),
    );
  }

  Widget _rowSkeleton() {
    return Row(
      children: [
        SkeletonLoader.box(width: 24, height: 24, radius: 6),
        const SizedBox(width: 12),
        SkeletonLoader.box(width: 80, height: 12),
        const Spacer(),
        SkeletonLoader.box(width: 120, height: 12),
      ],
    );
  }
}

// ── Profile Skeleton ──

class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SkeletonLoader.circle(size: 96),
            const SizedBox(height: 16),
            SkeletonLoader.box(width: 120, height: 14),
            const SizedBox(height: 8),
            SkeletonLoader.box(width: 160, height: 12),
            const SizedBox(height: 32),
            _fieldSkeleton(),
            const SizedBox(height: 16),
            _fieldSkeleton(),
            const SizedBox(height: 16),
            _fieldSkeleton(),
            const SizedBox(height: 16),
            _fieldSkeleton(),
          ],
        ),
      ),
    );
  }

  Widget _fieldSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonLoader.box(width: 80, height: 12),
        const SizedBox(height: 8),
        SkeletonLoader.box(width: double.infinity, height: 48, radius: 10),
      ],
    );
  }
}

// ── Visit Card Skeleton (for list pages) ──

class VisitCardSkeleton extends StatelessWidget {
  const VisitCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            SkeletonLoader.circle(size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLoader.box(width: 140, height: 13),
                  const SizedBox(height: 6),
                  SkeletonLoader.box(width: 100, height: 11),
                ],
              ),
            ),
            SkeletonLoader.box(width: 56, height: 24, radius: 8),
          ],
        ),
      ),
    );
  }
}
