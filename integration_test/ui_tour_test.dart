import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickgui/main.dart' as app;

Future<void> _settle(WidgetTester t, [int loops = 25]) async {
  for (var i = 0; i < loops; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

/// Rasterizes the window like flutter_test's captureImage: walk up from the
/// root element to the composited repaint boundary and encode its bounds.
/// Works on Wayland, X11 and nested/headless servers alike.
Future<void> _shot(WidgetTester t, String name) async {
  await t.pump();
  var ro = t.element(find.byType(MaterialApp)).renderObject!;
  while (!ro.isRepaintBoundary) {
    ro = ro.parent!;
  }
  final layer = ro.debugLayer! as OffsetLayer;
  final image = await layer.toImage(ro.paintBounds);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data != null) {
    File('/tmp/ui_$name.png').writeAsBytesSync(data.buffer.asUint8List());
  }
}

Future<bool> _tapText(WidgetTester t, String text, String shot) async {
  var f = find.widgetWithText(ElevatedButton, text);
  if (f.evaluate().isEmpty) f = find.widgetWithText(TextButton, text);
  if (f.evaluate().isEmpty) f = find.widgetWithText(ListTile, text);
  if (f.evaluate().isEmpty) f = find.text(text);
  if (f.evaluate().isEmpty) return false;
  await t.tap(f.first);
  await _settle(t);
  await _shot(t, shot);
  return true;
}

Future<void> _dismiss(WidgetTester t) async {
  for (final label in [
    'Descartar',
    'Dismiss',
    'Cancelar',
    'Cancel',
    'Cerrar',
    'Close',
  ]) {
    final f = find.text(label);
    if (f.evaluate().isNotEmpty) {
      await t.tap(f.first);
      await _settle(t, 6);
      return;
    }
  }
  final els = find.byType(AlertDialog).evaluate();
  if (els.isNotEmpty) Navigator.maybePop(els.first);
  await _settle(t, 4);
}

Future<void> _home(WidgetTester t) async {
  var guard = 0;
  while (guard++ < 5) {
    final els = find.byType(Scaffold).evaluate();
    if (els.isEmpty) return;
    final nav = Navigator.maybeOf(els.last);
    if (nav == null || !nav.canPop()) return;
    nav.pop();
    await _settle(t, 6);
  }
}

Future<void> _drawer(WidgetTester t) async {
  final m = find.byIcon(Icons.menu);
  if (m.evaluate().isNotEmpty) {
    await t.tap(m.first);
    await _settle(t, 6);
  }
}

Future<bool> _drawerTap(
  WidgetTester t,
  List<String> labels,
  String shot,
) async {
  await _drawer(t);
  for (final l in labels) {
    final f = find.text(l);
    if (f.evaluate().isNotEmpty) {
      await t.tap(f.first);
      await _settle(t);
      await _shot(t, shot);
      return true;
    }
  }
  await t.tapAt(const Offset(700, 400));
  await _settle(t, 4);
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UI tour captures all screens', (t) async {
    app.main();
    await _settle(t, 40);
    await _shot(t, '01_main');

    // Machines manager + VM row interfaces
    if (await _tapText(t, 'Gestionar máquinas existentes', '02_machines') ||
        await _tapText(t, 'Manage existing machines', '02_machines')) {
      final more = find.byIcon(Icons.more_vert);
      if (more.evaluate().isNotEmpty) {
        // Full actions menu
        await t.tap(more.first);
        await _settle(t, 6);
        await _shot(t, '03_vm_menu');
        if (await _tapText(t, 'Editar configuración', '03a_vm_config') ||
            await _tapText(t, 'Edit configuration', '03a_vm_config')) {
          await _dismiss(t);
        }
        await t.tap(more.first);
        await _settle(t, 6);
        if (await _tapText(t, 'Snapshots', '03b_vm_snapshots')) {
          await _dismiss(t);
        }
        await t.tap(more.first);
        await _settle(t, 6);
        if (await _tapText(t, 'Redirección de puertos', '03c_vm_ports') ||
            await _tapText(t, 'Port forwards', '03c_vm_ports')) {
          await _dismiss(t);
        }
        await t.tap(more.first);
        await _settle(t, 6);
        if (await _tapText(t, 'Ajustes (todo)', '03d_vm_settings') ||
            await _tapText(t, 'Settings (all)', '03d_vm_settings')) {
          // Delete confirm dialog -> capture then CANCEL
          if (await _tapText(t, 'Eliminar VM completa', '03e_delete_confirm') ||
              await _tapText(t, 'Delete whole VM', '03e_delete_confirm')) {
            await _dismiss(t);
          }
          await _dismiss(t);
        }
        // Submenus: resources, boot & network, devices
        for (final sub in [
          ['Arranque y red', 'Boot & network', '03g_submenu_boot'],
          ['Dispositivos', 'Devices', '03h_submenu_devices'],
          ['Recursos', 'Resources', '03f_submenu_resources'],
        ]) {
          await t.tap(more.first);
          await _settle(t, 6);
          if (!await _tapText(t, sub[0], sub[2])) {
            await _tapText(t, sub[1], sub[2]);
          }
          // Inside a section dialog, open one field-level dialog (Display)
          if (await _tapText(t, 'Pantalla', '${sub[2]}_field') ||
              await _tapText(t, 'Display', '${sub[2]}_field')) {
            await _dismiss(t);
          }
          await _dismiss(t);
        }
      }
    }
    await _home(t);

    // Create machines -> catalog
    if (await _tapText(t, 'Crear nuevas máquinas', '04_create') ||
        await _tapText(t, 'Create new machines', '04_create')) {
      // Open the "Sistema operativo" selector page
      final dd = find.text('Selecciona...');
      if (dd.evaluate().isNotEmpty) {
        await t.tap(dd.first);
        await _settle(t, 8);
        await _shot(t, '05_os_dropdown');
        // Pick an OS -> version selection page
        final osTile = find.text('Arch Linux');
        if (osTile.evaluate().isNotEmpty) {
          await t.tap(osTile.first);
          await _settle(t);
          await _shot(t, '05b_version_select');
          // Open the version selector page ("latest" in VERSION column)
          final ver = find.text('latest');
          if (ver.evaluate().isNotEmpty) {
            await t.tap(ver.first);
            await _settle(t, 8);
            await _shot(t, '05c_versions');
          }
        }
      }
    }
    await _home(t);

    // Every drawer entry
    await _drawerTap(t, ['Diagnóstico', 'Diagnostics'], '06_diagnostics_menu');
    await _home(t);
    await _drawerTap(t, [
      'Diagnóstico del sistema',
      'System diagnostics',
    ], '07_diag_page');
    await _home(t);
    await _drawerTap(t, [
      'Historial de descargas',
      'Download history',
    ], '08_downloads');
    await _home(t);
    await _drawerTap(t, [
      'Buscar actualizaciones',
      'Check for updates',
    ], '09_updates');
    await _home(t);
    await _drawerTap(t, ['Ajustes', 'Settings'], '10_settings');
    await _home(t);
  });
}
