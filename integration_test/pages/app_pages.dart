// Page Object Model — one object per navigable screen exposing
// semantic actions and stable locators (keys > text > type).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class LeftMenuPage {
  const LeftMenuPage(this.t);
  final WidgetTester t;

  Finder get machines => find.textContaining('Machines');
  Finder get diagnostics =>
      find.byKey(const ValueKey('nav.diagnostics'));
  Finder get diagnosticsText => find.textContaining('Diagnostics');
  Finder get activity => find.textContaining('Activity');
  Finder get settings => find.textContaining('Settings');
  Finder get downloader => find.textContaining('Downloader');

  Future<void> goToDiagnostics() async {
    await t.tap(diagnostics.first);
    await t.pumpAndSettle();
  }

  Future<void> goToMachines() async {
    await t.tap(machines.first);
    await t.pumpAndSettle();
  }
}

class MachinesPage {
  const MachinesPage(this.t);
  final WidgetTester t;

  Finder get title => find.textContaining('Machines');
  Finder get vmList => find.byType(ListView);
  Finder get searchField => find.byType(TextField);

  bool get isVisible => title.evaluate().isNotEmpty;
  Future<void> search(String q) async {
    if (searchField.evaluate().isEmpty) return;
    await t.enterText(searchField.first, q);
    await t.pumpAndSettle();
  }
}

class DiagnosticsPageObject {
  const DiagnosticsPageObject(this.t);
  final WidgetTester t;

  Finder get backendFound => find.textContaining('Backend found');
  Finder get kvmRow => find.textContaining('KVM');
  Finder get inventorySection => find.textContaining('Inventory');

  bool get backendOk => backendFound.evaluate().isNotEmpty;
}
