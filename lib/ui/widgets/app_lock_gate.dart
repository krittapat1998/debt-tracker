import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'app_icons.dart';

/// Covers the whole app (every route) with a lock screen while the app lock
/// is on: at start, and when the app comes back after [relockAfter] away.
/// Shorter trips, like copying an SMS from Messages, do not lock it.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child, this.relockAfter = const Duration(minutes: 1)});
  final Widget child;
  final Duration relockAfter;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  late bool _locked = ref.read(appLockProvider);
  DateTime? _leftAt;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.read(appLockProvider)) return;
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _leftAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (!_locked && left != null && DateTime.now().difference(left) >= widget.relockAfter) {
          setState(() => _locked = true);
          _unlock();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _unlock() async {
    if (_asking) return;
    _asking = true;
    final ok = await ref.read(appLockServiceProvider).unlock('ปลดล็อก Debt Tracker');
    _asking = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Kept in the tree so the app stays where it was, but out of reach.
        ExcludeSemantics(excluding: _locked, child: widget.child),
        if (_locked) Positioned.fill(child: _LockScreen(onUnlock: _unlock)),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icon/app_icon_rounded.png', width: 96, height: 96),
              const SizedBox(height: 20),
              Text('Debt Tracker ล็อกอยู่', style: t.titleLarge),
              const SizedBox(height: 6),
              Text('ใช้ Face ID หรือรหัสเครื่องเพื่อเปิด', style: t.bodyMedium),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const GlyphIcon(Glyph.unlock),
                label: const Text('ปลดล็อก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
