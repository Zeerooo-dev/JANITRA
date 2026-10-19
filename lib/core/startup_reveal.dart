import 'package:flutter/material.dart';

import 'app_theme.dart';

class StartupReveal extends StatefulWidget {
  const StartupReveal({super.key, required this.child});
  final Widget child;

  @override
  State<StartupReveal> createState() => _StartupRevealState();
}

class _StartupRevealState extends State<StartupReveal>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _showing = false);
        }
      });
  late final _enter = CurveTween(
    curve: const Interval(0, 0.6, curve: Cubic(0.16, 1, 0.3, 1)),
  ).animate(_controller);
  late final _exit = Tween<double>(begin: 1, end: 0).animate(
    CurveTween(curve: const Interval(0.73, 1, curve: Cubic(0.4, 0, 1, 1)))
        .animate(_controller),
  );
  bool _started = false, _showing = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _showing = false;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeFocus(
        excluding: _showing,
        child: ExcludeSemantics(
          excluding: _showing,
          child: IgnorePointer(ignoring: _showing, child: widget.child),
        ),
      ),
      if (_showing)
        Positioned.fill(
          child: FadeTransition(
            opacity: _exit,
            child: ColoredBox(
              key: const ValueKey('startup-logo'),
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(
                child: Center(
                  child: Semantics(
                    label: 'JANITRA is starting',
                    liveRegion: true,
                    child: ExcludeSemantics(
                      child: FadeTransition(
                        opacity: Tween<double>(
                          begin: 0.6,
                          end: 1,
                        ).animate(_enter),
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.05),
                            end: Offset.zero,
                          ).animate(_enter),
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.94,
                              end: 1,
                            ).animate(_enter),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const JanitraLogo(size: 96),
                                const SizedBox(height: 16),
                                Text(
                                  'JANITRA',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
