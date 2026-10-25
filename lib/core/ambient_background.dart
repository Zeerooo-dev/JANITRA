import 'package:flutter/material.dart';

import 'appearance_settings.dart';

/// Low-contrast atmosphere behind workspace content.
///
/// The user's ColorScheme, theme mode, custom background, and high-contrast
/// setting remain authoritative. This draws nothing on top of content and
/// never captures touches or changes accessibility semantics.
class JanitraAmbientBackground extends StatelessWidget {
  const JanitraAmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.scaffoldBackgroundColor;
    final settings = context
        .dependOnInheritedWidgetOfExactType<AppearanceScope>()
        ?.notifier;
    if (settings?.highContrast ?? false) {
      return ColoredBox(
        key: const ValueKey('janitra-ambient-flat'),
        color: base,
        child: child,
      );
    }

    final dark = theme.brightness == Brightness.dark;
    final customBackground = settings?.backgroundFor(theme.brightness) != null;
    // Custom backgrounds are user-selected; keep them unmistakably dominant.
    final primaryAlpha = customBackground ? 0.045 : (dark ? 0.16 : 0.09);
    final tertiaryAlpha = customBackground ? 0.035 : (dark ? 0.105 : 0.07);
    final top = Color.alphaBlend(
      scheme.primary.withValues(alpha: primaryAlpha),
      base,
    );
    final bottom = Color.alphaBlend(
      scheme.tertiary.withValues(alpha: tertiaryAlpha),
      base,
    );

    // An explicitly chosen foreground may only just meet the readability
    // threshold against the user's background. If tinting would break that
    // contrast, honor their solid background instead.
    final bodyInk = scheme.onSurface;
    final secondaryInk = scheme.onSurfaceVariant;
    if ([top, bottom].any(
      (color) =>
          colorContrast(bodyInk, color) < 4.5 ||
          colorContrast(secondaryInk, color) < 4.5,
    )) {
      return ColoredBox(
        key: const ValueKey('janitra-ambient-flat'),
        color: base,
        child: child,
      );
    }

    return DecoratedBox(
      key: const ValueKey('janitra-ambient-gradient'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.56, 1],
          colors: [top, base, bottom],
        ),
      ),
      child: child,
    );
  }
}
