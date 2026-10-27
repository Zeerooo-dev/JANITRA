import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance_settings.dart';

const janitraNavy = Color(0xFF234E70);
const janitraInk = Color(0xFF202C39);
const janitraMuted = Color(0xFF526070);
const janitraBorder = Color(0xFFE3E7EB);

// Shared visual language: compact, readable, accessible touch targets.
ThemeData janitraTheme({
  Brightness brightness = Brightness.light,
  Color accent = janitraNavy,
  Color? background,
  Color? foreground,
  String font = 'Roboto',
  bool highContrast = false,
}) {
  final dark = brightness == Brightness.dark;
  final surface = background ?? (dark ? const Color(0xFF1B222C) : Colors.white);
  final scaffold =
      background ?? (dark ? const Color(0xFF10161F) : const Color(0xFFF6F8FB));
  final ink = readableColor(
    foreground ?? (dark ? const Color(0xFFEDF2F8) : janitraInk),
    surface,
    highContrast ? 7 : 4.5,
  );
  final muted = readableColor(
    dark ? const Color(0xFFB6C2D0) : janitraMuted,
    surface,
    highContrast ? 7 : 4.5,
  );
  final primary = readableColor(accent, surface, highContrast ? 7 : 4.5);
  final error = readableColor(
    dark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
    surface,
    highContrast ? 7 : 4.5,
  );
  final border = highContrast
      ? ink
      : dark
      ? const Color(0xFF485566)
      : janitraBorder;
  final family = font == 'system' ? null : font;
  Color navigationSurface(Color color) {
    for (
      var step = 0;
      highContrast &&
          step < 10 &&
          colorContrast(Colors.white, color) < 7 &&
          colorContrast(Colors.black, color) < 7;
      step++
    ) {
      color = Color.lerp(color, dark ? Colors.black : Colors.white, .2)!;
    }
    return color;
  }

  final barSurface = navigationSurface(scaffold);
  final minimum = highContrast ? 7.0 : 4.5;
  final barInk = readableColor(ink, barSurface, minimum);
  final barMuted = readableColor(muted, barSurface, minimum);
  final indicator = navigationSurface(
    Color.alphaBlend(barInk.withValues(alpha: .10), barSurface),
  );
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: family,
    scaffoldBackgroundColor: scaffold,
    visualDensity: VisualDensity.standard,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      contrastLevel: highContrast ? 1 : 0,
      primary: primary,
      error: error,
      onError: colorContrast(error, Colors.white) >= 4.5
          ? Colors.white
          : Colors.black,
      onPrimary: colorContrast(primary, Colors.white) >= 4.5
          ? Colors.white
          : Colors.black,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      outline: highContrast
          ? ink
          : dark
          ? const Color(0xFF8B9BAD)
          : const Color(0xFF93A1AD),
      outlineVariant: border,
      surfaceContainer: background,
      surfaceContainerHigh: background,
      surfaceContainerHighest: background,
      surfaceContainerLowest: background,
      surfaceContainerLow: background != null
          ? surface
          : dark
          ? const Color(0xFF202B37)
          : const Color(0xFFFBFCFD),
    ),
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        fontSize: 23,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: ink),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: barSurface,
      foregroundColor: barInk,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            ThemeData.estimateBrightnessForColor(barSurface) == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: ThemeData.estimateBrightnessForColor(barSurface),
      ),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 60,
      titleTextStyle: TextStyle(
        fontFamily: family,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: barInk,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      minVerticalPadding: 8,
      iconColor: primary,
      textColor: ink,
    ),
    dividerTheme: DividerThemeData(color: border, space: 16),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: highContrast
              ? ink
              : dark
              ? const Color(0xFF8B9BAD)
              : const Color(0xFFBBC5CE),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.8),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(
          fontFamily: family,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: surface,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(
          color: highContrast
              ? ink
              : dark
              ? const Color(0xFF8B9BAD)
              : janitraBorder,
        ),
        textStyle: TextStyle(
          fontFamily: family,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? readableColor(barInk, indicator, minimum)
              : barMuted,
        ),
      ),
      height: 70,
      elevation: 0,
      backgroundColor: barSurface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: indicator,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: family,
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? barInk : barMuted,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: _AppearanceTransitions(platform),
      },
    ),
  );
}

Color readableColor(Color color, Color background, double minimum) {
  if (colorContrast(color, background) >= minimum) return color;
  final target =
      colorContrast(Colors.white, background) >
          colorContrast(Colors.black, background)
      ? Colors.white
      : Colors.black;
  for (var step = 1; step <= 20; step++) {
    final adjusted = Color.lerp(color, target, step / 20)!;
    if (colorContrast(adjusted, background) >= minimum) return adjusted;
  }
  return target;
}

class _AppearanceTransitions extends PageTransitionsBuilder {
  const _AppearanceTransitions(this.platform);
  final TargetPlatform platform;
  PageTransitionsBuilder get _native =>
      const PageTransitionsTheme().builders[platform] ??
      const FadeUpwardsPageTransitionsBuilder();

  @override
  Duration get transitionDuration => platform == TargetPlatform.android
      ? const Duration(milliseconds: 220)
      : _native.transitionDuration;

  @override
  Duration get reverseTransitionDuration => platform == TargetPlatform.android
      ? const Duration(milliseconds: 180)
      : _native.reverseTransitionDuration;
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      MediaQuery.disableAnimationsOf(context) ||
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional
      ? child
      : _native.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}

class JanitraLogo extends StatelessWidget {
  const JanitraLogo({super.key, this.size = 80});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size / 5),
    child: Image.asset(
      'assets/icons/janitra_launcher_1024.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'JANITRA logo',
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.label, {
    super.key,
    this.action,
    this.onAction,
    this.icon = Icons.add,
    this.count,
    this.actionTooltip,
  });
  final String label;
  final String? action;
  final String? actionTooltip;
  final VoidCallback? onAction;
  final IconData icon;
  final int? count;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (count != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '$count',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (action != null)
          Tooltip(
            message: actionTooltip ?? 'Add $label',
            child: TextButton.icon(
              onPressed: onAction,
              icon: Icon(icon, size: 18),
              label: Text(action!),
            ),
          ),
      ],
    ),
  );
}

class JanitraEmptyState extends StatelessWidget {
  const JanitraEmptyState(
    this.message, {
    super.key,
    this.icon = Icons.inbox_outlined,
  });
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(
          icon,
          size: 23,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: Theme.of(context).colorScheme.primary,
    foregroundColor: Theme.of(context).colorScheme.onPrimary,
    child: Text(
      name
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty)
          .take(2)
          .map((s) => s.characters.first)
          .join()
          .toUpperCase(),
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );
}

class WorkStatusBadge extends StatelessWidget {
  const WorkStatusBadge({
    super.key,
    required this.label,
    required this.status,
    this.alignment = Alignment.centerLeft,
  });
  final String label, status;
  final AlignmentGeometry alignment;
  @override
  Widget build(BuildContext context) {
    final (color, background, icon) = switch (status) {
      'APPROVED' || 'Active' => (
        const Color(0xFF216E4B),
        const Color(0xFFEDF7F1),
        Icons.check_circle_outline,
      ),
      'PENDING_APPROVAL' || 'REOPENED_FOR_REVIEW' => (
        const Color(0xFF866010),
        const Color(0xFFFFF6DC),
        Icons.schedule,
      ),
      'REJECTED' || 'LOCKED_NOT_REVIEWED' || 'Suspended' => (
        const Color(0xFFA62B38),
        const Color(0xFFFFF0F0),
        Icons.lock_outline,
      ),
      _ => (janitraMuted, const Color(0xFFEFF1F3), Icons.circle_outlined),
    };
    return Align(
      alignment: alignment,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
