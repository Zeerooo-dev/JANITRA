import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import 'apk_updater.dart';

class UpdatePromptHost extends StatefulWidget {
  const UpdatePromptHost({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.updater,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final ApkUpdater? updater;

  @override
  State<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends State<UpdatePromptHost>
    with WidgetsBindingObserver {
  ApkUpdater? _updater;
  AppRelease? _pending;
  String? _pendingPath;
  Timer? _timer;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    const repository = String.fromEnvironment('JANITRA_RELEASE_REPOSITORY');
    _updater =
        widget.updater ??
        (!kIsWeb && Platform.isAndroid && repository.isNotEmpty
            ? ApkUpdater(
                repository: repository,
                platform: AndroidUpdatePlatform(),
              )
            : null);
    // Let the existing startup and authentication flow render before checking.
    if (_updater != null) _timer = Timer(const Duration(seconds: 2), _check);
  }

  Future<void> _check() async {
    try {
      final saved = await _updater?.restorePendingPermission();
      if (saved != null) {
        _pending = saved.$1;
        _pendingPath = saved.$2;
      } else {
        _pending = await _updater?.check();
      }
      if (mounted) _showWhenReady();
    } catch (_) {
      // An optional update check must never interrupt workplace access or offline work.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _showWhenReady();
  }

  void _showWhenReady() {
    _timer?.cancel();
    if (!mounted || _shown || _pending == null) return;
    final navigator = widget.navigatorKey.currentState;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        navigator == null ||
        navigator.canPop()) {
      _timer = Timer(const Duration(seconds: 2), _showWhenReady);
      return;
    }
    _shown = true;
    showDialog<void>(
      context: navigator.overlay!.context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(
        updater: _updater!,
        release: _pending!,
        initialPath: _pendingPath,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.updater == null) _updater?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.updater,
    required this.release,
    this.initialPath,
  });
  final ApkUpdater updater;
  final AppRelease release;
  final String? initialPath;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _verifying = false;
  bool _permission = false;
  bool _waitingForSettings = false;
  bool _installRequested = false;
  String? _path;
  String? _error;
  int _received = 0;

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _path != null &&
        !_busy &&
        _waitingForSettings) {
      _waitingForSettings = false;
      _install();
    } else if (state == AppLifecycleState.resumed &&
        _path != null &&
        !_busy &&
        _installRequested &&
        !_permission &&
        _error == null) {
      _install();
    }
  }

  String _message(Object error) {
    if (error is UpdateFailure) return error.message;
    if (error is PlatformException) {
      return switch (error.code) {
        'storage' => 'Not enough storage. Free some space and try again.',
        'verification' => 'This APK failed security checks or cannot update this installation. Nothing was installed.',
        'permission' => 'Installation permission is required. You can allow it in Android settings or update later.',
        'installer' =>
          'Android could not open its installer. Try again or update later.',
        _ => 'The update could not be completed. Try again later.',
      };
    }
    return 'The download failed. Check your connection and try again.';
  }

  Future<void> _download() async {
    _installRequested = true;
    setState(() {
      _busy = true;
      _error = null;
      _received = 0;
      _verifying = false;
    });
    try {
      final path = await widget.updater.download(
        widget.release,
        (received, _) {
          if (mounted) setState(() => _received = received);
        },
        verifying: () {
          if (mounted) setState(() => _verifying = true);
        },
      );
      if (!mounted) return;
      setState(() {
        _path = path;
        _busy = false;
        _verifying = false;
      });
      await _install();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _verifying = false;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _install() async {
    if (_busy ||
        _path == null ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final allowed = await widget.updater.platform.canInstall();
      if (!mounted) return;
      if (!allowed) {
        setState(() {
          _permission = true;
          _busy = false;
        });
        return;
      }
      setState(() => _permission = false);
      await widget.updater.platform.install(_path!, widget.release);
      await widget.updater.clearPendingPermission();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _busy = false;
          if (error is PlatformException && error.code == 'verification') {
            _path = null;
            _permission = false;
          }
        });
      }
    }
  }

  Future<void> _allowInstallation() async {
    if (_waitingForSettings) return;
    _waitingForSettings = true;
    try {
      final allowed = await widget.updater.platform.canInstall();
      if (!mounted || !_waitingForSettings) return;
      if (allowed) {
        _waitingForSettings = false;
        if (mounted) await _install();
        return;
      }
      await widget.updater.rememberPermission(_path!, widget.release);
      if (!mounted || !_waitingForSettings) {
        await widget.updater.clearPendingPermission();
        return;
      }
      await widget.updater.platform.requestInstallPermission();
    } catch (error) {
      _waitingForSettings = false;
      if (mounted) setState(() => _error = _message(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.release.size;
    final progress = (_received / total).clamp(0.0, 1.0);
    final mb = (total / (1024 * 1024)).toStringAsFixed(1);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        constraints: const BoxConstraints(maxWidth: 480),
        title: Row(
          children: [
            const JanitraLogo(size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_path == null ? 'Update available' : 'Update ready'),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'JANITRA ${widget.release.version.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '$mb MB · Your account and saved work stay on this device.',
                ),
                const SizedBox(height: 20),
                Text(
                  'What’s new',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      widget.release.notes.isEmpty
                          ? 'A new version of JANITRA is available.'
                          : widget.release.notes,
                    ),
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: _verifying || _path != null ? null : progress,
                    semanticsLabel: _verifying
                        ? 'Verifying update'
                        : 'Download progress',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _verifying
                        ? 'Verifying APK security…'
                        : _path != null
                        ? 'Opening Android installer…'
                        : '${(progress * 100).floor()}% · ${(_received / (1024 * 1024)).toStringAsFixed(1)} / $mb MB',
                  ),
                ],
                if (_permission) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Allow JANITRA to install updates on the next Android screen. Android will still ask you to confirm installation.',
                  ),
                ],
                if (widget.initialPath != null &&
                    _path != null &&
                    !_busy &&
                    !_permission) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Your download was verified again. Continue with Android’s installer when you’re ready.',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    semanticsLabel: _error,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    _installRequested = false;
                    _waitingForSettings = false;
                    await widget.updater.clearPendingPermission();
                    if (context.mounted) Navigator.of(context).pop();
                  },
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : _permission
                ? _allowInstallation
                : _path != null
                ? () {
                    _installRequested = true;
                    _install();
                  }
                : _download,
            icon: Icon(
              _permission ? Icons.settings_outlined : Icons.system_update_alt,
            ),
            label: Text(
              _permission
                  ? 'Allow installation'
                  : _path != null
                  ? 'Install update'
                  : _error != null
                  ? 'Try again'
                  : 'Update Now',
            ),
          ),
        ],
      ),
    );
  }
}
