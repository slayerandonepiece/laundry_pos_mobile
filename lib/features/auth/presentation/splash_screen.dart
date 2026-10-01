import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/text_styles.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback? onAnimationComplete;
  final bool animate;

  const SplashScreen({
    super.key,
    this.onAnimationComplete,
    this.animate = true,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  /// Matches standard Android 12+ SplashScreen circular icon diameter (160dp).
  static const double _kLogoDiameter = 160.0;

  late final AnimationController _controller;
  late final Animation<double> _revealAnimation;
  late final Animation<double> _textFadeAnimation;
  late final Animation<double> _textSlideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Circular reveal expands smoothly from behind the logo to cover the full screen
    _revealAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.70, curve: Curves.easeOutCubic),
    );

    // Wordmark fades in as the circular reveal sweeps past the text area
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.28, 0.85, curve: Curves.easeOut),
      ),
    );

    // Wordmark slides gently upward into its final resting position
    _textSlideAnimation = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.28, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    if (widget.animate) {
      _controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onAnimationComplete?.call();
        }
      });
      _controller.forward();
    } else {
      _controller.value = 1.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onAnimationComplete?.call();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: widget.animate
            ? Colors.white
            : AppColors.brandDeepHydro,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final center = Offset(width / 2, height / 2);

            // Compute maximum distance from center to screen corners + margin
            final maxRadius =
                (math.sqrt(width * width + height * height) / 2) + 16.0;
            const minRadius = _kLogoDiameter / 2;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Layer 1: White background (matches native splash background)
                const ColoredBox(color: Colors.white, child: SizedBox.expand()),

                // Layer 2: Circular reveal expanding Deep Hydro outward
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final currentRadius = widget.animate
                        ? minRadius +
                              (maxRadius - minRadius) * _revealAnimation.value
                        : maxRadius;

                    return ClipPath(
                      clipper: _CircleRevealClipper(
                        center: center,
                        radius: currentRadius,
                      ),
                      child: const ColoredBox(
                        color: AppColors.brandDeepHydro,
                        child: SizedBox.expand(),
                      ),
                    );
                  },
                ),

                // Layer 3: Circular logo centered at the exact screen coordinates
                Center(
                  child: ClipOval(
                    child: Image.asset(
                      AppAssets.logo,
                      width: _kLogoDiameter,
                      height: _kLogoDiameter,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                // Layer 4: Wordmark below the centered logo
                Positioned(
                  top: center.dy + (_kLogoDiameter / 2) + 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: widget.animate
                              ? Offset(0, _textSlideAnimation.value)
                              : Offset.zero,
                          child: Opacity(
                            opacity: widget.animate
                                ? _textFadeAnimation.value
                                : 1.0,
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Klen',
                                  style: TextStyle(color: Colors.white),
                                ),
                                TextSpan(
                                  text: 'POS',
                                  style: TextStyle(
                                    color: AppColors.brandElectricCyan,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Laundry POS counter',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CircleRevealClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;

  const _CircleRevealClipper({required this.center, required this.radius});

  @override
  Path getClip(Size size) {
    final path = Path();
    if (radius > 0) {
      path.addOval(Rect.fromCircle(center: center, radius: radius));
    }
    return path;
  }

  @override
  bool shouldReclip(_CircleRevealClipper oldClipper) {
    return oldClipper.radius != radius || oldClipper.center != center;
  }
}
