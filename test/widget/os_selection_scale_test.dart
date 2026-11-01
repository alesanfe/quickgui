import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/catalog/domain/operating_system.dart';
import 'package:quickgui/features/catalog/domain/option.dart';
import 'package:quickgui/features/catalog/domain/version.dart';
import 'package:quickgui/features/catalog/presentation/operating_system_selection.dart';
import 'package:quickgui/features/catalog/providers/catalog_providers.dart';

import '../support/harness/test_app.dart';

OperatingSystem _os(String code, {int versions = 2, int editions = 1}) {
  final os = OperatingSystem(code.toUpperCase(), code);
  for (var v = 0; v < versions; v++) {
    final version = Version('2$v.0');
    for (var e = 0; e < editions; e++) {
      version.options.add(Option('edition-$e', 'curl'));
    }
    os.versions.add(version);
  }
  return os;
}

/// QGUI-OS-101: the OS picker must stay usable at real catalogue scale —
/// ~950 families with duplicate display names — not just with the
/// three-entry fixture.
void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  Future<void> openCatalogue(
    WidgetTester tester,
    List<OperatingSystem> catalogue,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          osCatalogueProvider.overrideWithValue(Future.value(catalogue)),
          osIconsProvider.overrideWithValue(const {}),
        ],
        child: testApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => Navigator.of(context).push<OperatingSystem>(
                MaterialPageRoute(
                  builder: (_) => const OperatingSystemSelection(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('950-entry catalogue renders virtualized and scrolls', (
    tester,
  ) async {
    final catalogue = [for (var i = 0; i < 950; i++) _os('os-$i')];
    await openCatalogue(tester, catalogue);
    // Only the visible rows are built — the rest live lazily.
    expect(find.text('OS-0'), findsOneWidget);
    expect(find.text('OS-949'), findsNothing);
    expect(find.byType(ListTile).evaluate().length, lessThan(30));
    await tester.drag(find.byType(ListView).first, const Offset(0, -40000));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters a large catalogue including duplicates', (
    tester,
  ) async {
    final catalogue = [
      _os('ubuntu'),
      _os('ubuntu-mate'), // near-duplicate name
      for (var i = 0; i < 200; i++) _os('distro-$i'),
    ];
    await openCatalogue(tester, catalogue);
    await tester.enterText(find.byType(TextField), 'ubuntu');
    await tester.pump();
    expect(find.text('UBUNTU'), findsOneWidget);
    expect(find.text('UBUNTU-MATE'), findsOneWidget);
    expect(find.text('DISTRO-0'), findsNothing);
  });

  testWidgets('no-match state names the term and clears', (tester) async {
    await openCatalogue(tester, [_os('ubuntu'), _os('debian')]);
    await tester.enterText(find.byType(TextField), 'haiku');
    await tester.pump();
    expect(find.textContaining('haiku'), findsWidgets);
    await tester.tap(find.text('Clear search'));
    await tester.pump();
    expect(find.text('UBUNTU'), findsOneWidget);
    expect(find.text('DEBIAN'), findsOneWidget);
  });

  testWidgets('tapping a row pops with the selected OS', (tester) async {
    final catalogue = [_os('ubuntu'), _os('debian')];
    final completer = _PickedOs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          osCatalogueProvider.overrideWithValue(Future.value(catalogue)),
          osIconsProvider.overrideWithValue(const {}),
        ],
        child: testApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                completer.result = await Navigator.of(context)
                    .push<OperatingSystem>(
                      MaterialPageRoute(
                        builder: (_) => const OperatingSystemSelection(),
                      ),
                    );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DEBIAN'));
    await tester.pumpAndSettle();
    expect(completer.result?.code, 'debian');
  });
}

class _PickedOs {
  OperatingSystem? result;
}
