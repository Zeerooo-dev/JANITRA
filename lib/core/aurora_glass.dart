import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'appearance_settings.dart';

/// Low-motion, theme-aware aurora behind the workspace. This paints only;
/// interaction, authorization and navigation stay with the child screen.
class JanitraAuroraBackground extends StatefulWidget {
  const JanitraAuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  State<JanitraAuroraBackground> createState() =>
      _JanitraAuroraBackgroundState();
}

class _JanitraAuroraBackgroundState extends State<JanitraAuroraBackground>
    with WidgetsBindingObserver {
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);
  final Stopwatch _elapsed = Stopwatch();
  Timer? _timer;
  bool _foreground = true;
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
    if (mounted) setState(() {});
  }

  void _syncMotion() {
    if (!mounted) return;
    final settings = context
        .dependOnInheritedWidgetOfExactType<AppearanceScope>()
        ?.notifier;
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final highContrast = settings?.highContrast ?? false;
    final motionOff = settings?.motion == MotionPreference.off;
    final shouldAnimate =
        _foreground &&
        !reducedMotion &&
        !highContrast &&
        !motionOff &&
        TickerMode.valuesOf(context).enabled;
    if (_animate == shouldAnimate) return;
    _animate = shouldAnimate;
    if (shouldAnimate) {
      _elapsed.start();
      // Aurora drift is deliberately tiny between frames. A low-frequency
      // repaint is gentle on batteries and won't leave an infinite ticker
      // that prevents widget tests from settling.
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        _clock.value = (_elapsed.elapsedMilliseconds % 36000) / 36000;
      });
    } else {
      _timer?.cancel();
      _timer = null;
      _elapsed.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.scaffoldBackgroundColor;
    final settings = context
        .dependOnInheritedWidgetOfExactType<AppearanceScope>()
        ?.notifier;
    final highContrast = settings?.highContrast ?? false;
    if (highContrast) {
      return ColoredBox(
        key: const ValueKey('janitra-aurora-flat'),
        color: base,
        child: widget.child,
      );
    }

    final dark = theme.brightness == Brightness.dark;
    final custom = settings?.backgroundFor(theme.brightness) != null;
    // Keep custom backgrounds the dominant color, with very subtle light.
    var strength = custom ? 0.24 : 1.0;
    Color topFor(double factor) => Color.alphaBlend(
      scheme.primary.withValues(alpha: (dark ? .13 : .075) * factor),
      base,
    );
    Color bottomFor(double factor) => Color.alphaBlend(
      scheme.tertiary.withValues(alpha: (dark ? .11 : .060) * factor),
      base,
    );
    bool readable(double factor) {
      final topSample = topFor(factor);
      final bottomSample = bottomFor(factor);
      final samples = [
        topSample,
        bottomSample,
        Color.alphaBlend(
          scheme.primary.withValues(alpha: (dark ? .17 : .11) * factor),
          topSample,
        ),
        Color.alphaBlend(
          scheme.tertiary.withValues(alpha: (dark ? .17 : .105) * factor),
          bottomSample,
        ),
        Color.alphaBlend(
          scheme.secondary.withValues(alpha: (dark ? .12 : .08) * factor),
          base,
        ),
      ];
      return samples.every(
        (sample) =>
            colorContrast(scheme.onSurface, sample) >= 4.5 &&
            colorContrast(scheme.onSurfaceVariant, sample) >= 4.5,
      );
    }

    // Keep the motion visible where possible without sacrificing custom
    // foreground and muted text readability. A solid background is the final
    // fallback for unusual high-saturation/custom appearance combinations.
    for (var attempt = 0; attempt < 8 && !readable(strength); attempt++) {
      strength *= .68;
    }
    if (!readable(strength)) {
      return ColoredBox(
        key: const ValueKey('janitra-aurora-flat'),
        color: base,
        child: widget.child,
      );
    }
    final top = topFor(strength);
    final bottom = bottomFor(strength);

    // Cards throughout the embedded workspace are lightly transparent;
    // selected surfaces below additionally use an actual BackdropFilter.
    final glassTheme = theme.copyWith(
      cardTheme: theme.cardTheme.copyWith(
        color: scheme.surface.withValues(alpha: dark ? .78 : .84),
      ),
    );
    return Stack(
      key: const ValueKey('janitra-aurora-background'),
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: CustomPaint(
                  key: const ValueKey('janitra-aurora-painter'),
                  painter: _AuroraPainter(
                    time: _clock,
                    top: top,
                    middle: base,
                    bottom: bottom,
                    primary: scheme.primary,
                    secondary: scheme.secondary,
                    tertiary: scheme.tertiary,
                    strength: strength,
                    dark: dark,
                  ),
                ),
              ),
            ),
          ),
        ),
        Theme(data: glassTheme, child: widget.child),
      ],
    );
  }
}

/// Blurred surface with a restrained colored tint. The solid high-contrast
/// fallback intentionally avoids translucent backgrounds and blur.
class JanitraGlassPanel extends StatelessWidget {
  const JanitraGlassPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.gradient,
    this.radius = 19,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Gradient? gradient;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final contrast =
        context
            .dependOnInheritedWidgetOfExactType<AppearanceScope>()
            ?.notifier
            ?.highContrast ??
        false;
    final borderRadius = BorderRadius.circular(radius);
    final decoration = BoxDecoration(
      color: contrast
          ? scheme.surface
          : scheme.surface.withValues(
              alpha: theme.brightness == Brightness.dark ? .55 : .72,
            ),
      gradient: contrast ? null : gradient,
      border: Border.all(
        color: contrast
            ? scheme.outline
            : scheme.outlineVariant.withValues(alpha: .72),
      ),
      borderRadius: borderRadius,
      boxShadow: contrast
          ? null
          : [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: .085),
                blurRadius: 22,
                offset: const Offset(0, 7),
              ),
            ],
    );
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: contrast
            ? DecoratedBox(
                decoration: decoration,
                child: Material(
                  type: MaterialType.transparency,
                  child: Padding(padding: padding, child: child),
                ),
              )
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 11, sigmaY: 11),
                child: DecoratedBox(
                  decoration: decoration,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Padding(padding: padding, child: child),
                  ),
                ),
              ),
      ),
    );
  }
}

class JanitraNavigationSurface extends StatelessWidget {
  const JanitraNavigationSurface({
    super.key,
    required this.child,
    this.radius = 0,
  });

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast =
        context
            .dependOnInheritedWidgetOfExactType<AppearanceScope>()
            ?.notifier
            ?.highContrast ??
        false;
    final base = theme.appBarTheme.backgroundColor!;
    final tint = base.withValues(
      alpha: theme.brightness == Brightness.dark ? .82 : .90,
    );
    final inks = [
      theme.appBarTheme.foregroundColor!,
      theme.navigationBarTheme.labelTextStyle!.resolve({})!.color!,
    ];
    // Test both backdrop extremes so custom colors cannot hide bar controls.
    final frosted =
        !highContrast &&
        [Colors.black, Colors.white].every(
          (backdrop) => inks.every(
            (ink) =>
                colorContrast(ink, Color.alphaBlend(tint, backdrop)) >= 4.5,
          ),
        );
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: frosted ? tint : base,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: highContrast ? 1 : .45,
          ),
          width: .5,
        ),
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: frosted
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: surface,
            )
          : surface,
    );
  }
}

/// A glass version of Card for the visible workspace cards only. Preserves
/// Card's familiar margin and Material behavior, without changing data logic.
class JanitraGlassCard extends StatelessWidget {
  const JanitraGlassCard({super.key, required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => JanitraGlassPanel(
    margin: margin ?? const EdgeInsets.only(bottom: 8),
    child: child,
  );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.time,
    required this.top,
    required this.middle,
    required this.bottom,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.strength,
    required this.dark,
  }) : super(repaint: time);

  final ValueListenable<double> time;
  final Color top, middle, bottom, primary, secondary, tertiary;
  final double strength;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, middle, bottom],
          stops: const [0, .53, 1],
        ).createShader(bounds),
    );

    final phase = time.value * 2 * math.pi;
    final radius = math.max(size.width, size.height);
    void glow(Color color, Offset center, double radiusFactor, double opacity) {
      final r = radius * radiusFactor;
      final shader = RadialGradient(
        colors: [
          color.withValues(alpha: opacity * strength),
          color.withValues(alpha: opacity * strength * .44),
          color.withValues(alpha: 0),
        ],
        stops: const [0, .40, 1],
      ).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawCircle(center, r, Paint()..shader = shader);
    }

    // Long, gentle paths; these are paint-only and never intercept gestures.
    glow(
      primary,
      Offset(
        size.width * (.83 + .18 * math.sin(phase)),
        size.height * (.15 + .10 * math.cos(phase)),
      ),
      .47,
      dark ? .17 : .11,
    );
    glow(
      tertiary,
      Offset(
        size.width * (.08 + .17 * math.sin(phase + 2.1)),
        size.height * (.54 + .11 * math.cos(phase + 1.4)),
      ),
      .49,
      dark ? .17 : .105,
    );
    glow(
      secondary,
      Offset(
        size.width * (.77 + .13 * math.sin(phase + 3.2)),
        size.height * (.85 + .09 * math.cos(phase + 3)),
      ),
      .36,
      dark ? .12 : .08,
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      top != oldDelegate.top ||
      middle != oldDelegate.middle ||
      bottom != oldDelegate.bottom ||
      primary != oldDelegate.primary ||
      secondary != oldDelegate.secondary ||
      tertiary != oldDelegate.tertiary ||
      strength != oldDelegate.strength ||
      dark != oldDelegate.dark ||
      time != oldDelegate.time;
}
