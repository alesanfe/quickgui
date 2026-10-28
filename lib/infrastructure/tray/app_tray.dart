import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Best-effort system-tray integration (VISTA gap): Show/focus, Refresh
/// and Quit entries. Initialization failures are non-fatal — headless
/// sessions, WMs without a tray spec (or missing AppIndicator) simply
/// leave the app tray-less.
class AppTray with TrayListener {
  AppTray({
    this.onRefresh,
    this.showLabel = 'Show QuickGUI',
    this.refreshLabel = 'Refresh',
    this.quitLabel = 'Quit',
  });

  /// Invoked when the user picks "Refresh" — refreshes VM state.
  final VoidCallback? onRefresh;

  /// Localized menu labels — the tray has no BuildContext of its own.
  final String showLabel;
  final String refreshLabel;
  final String quitLabel;

  bool _ready = false;

  /// Sets the icon + context menu and registers the listener. Safe to
  /// call on any platform: returns false when a tray cannot be shown.
  Future<bool> init() async {
    if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
      return false;
    }
    try {
      trayManager.addListener(this);
      // macOS wants a template-friendly small PNG; logo.png doubles as
      // the app icon everywhere.
      await trayManager.setIcon('assets/images/logo.png');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: showLabel),
            MenuItem(key: 'refresh', label: refreshLabel),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: quitLabel),
          ],
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Tray unavailable: $e');
    }
    return _ready;
  }

  @override
  void onTrayIconMouseDown() => _show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await _show();
      case 'refresh':
        onRefresh?.call();
      case 'quit':
        await windowManager.destroy();
    }
  }

  Future<void> _show() async {
    try {
      final visible = await windowManager.isVisible();
      if (!visible) await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('Tray show failed: $e');
    }
  }

  Future<void> dispose() async {
    try {
      trayManager.removeListener(this);
    } catch (_) {}
    if (_ready) {
      try {
        await trayManager.destroy();
      } catch (_) {}
    }
  }
}
