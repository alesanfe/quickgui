import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/create/presentation/create_page.dart';
import 'package:quickgui/features/machines/presentation/details/vm_console_page.dart';
import 'package:quickgui/features/machines/presentation/details/vm_details_pane.dart';
import 'package:quickgui/features/machines/providers/backend_providers.dart';
import 'package:quickgui/shared/widgets/shortcuts_dialog.dart';

import '../support/fakes/fake_virtualization_backend.dart';
import '../support/harness/test_app.dart';

void main() {
  setUpAll(TestLocalizationsDelegate.preload);

  group('dropKindFor', () {
    test('routes each supported extension', () {
      expect(dropKindFor('/x/win.iso'), 'image');
      expect(dropKindFor('/x/disk.qcow2'), 'image');
      expect(dropKindFor('/x/disk.vmdk'), 'image');
      expect(dropKindFor('/x/vm.conf'), 'conf');
      expect(dropKindFor('/x/vm.tar.gz'), 'archive');
      expect(dropKindFor('/x/vm.tgz'), 'archive');
      expect(dropKindFor('/x/readme.txt'), 'unsupported');
      expect(dropKindFor('/x/noext'), 'unsupported');
    });
  });

  group('decodePpm', () {
    test('decodes a P6 framebuffer', () async {
      // 2x2 red image
      final header = 'P6\n2 2\n255\n'.codeUnits;
      final px = List<int>.filled(12, 200);
      final image = await decodePpm(Uint8List.fromList([...header, ...px]));
      expect(image, isNotNull);
      expect(image!.width, 2);
      expect(image.height, 2);
      image.dispose();
    });

    test('rejects garbage', () async {
      expect(await decodePpm(Uint8List.fromList('nope'.codeUnits)), isNull);
      expect(await decodePpm(Uint8List(0)), isNull);
    });
  });

  group('VmConsolePage', () {
    testWidgets('stopped VM shows offline state and disables input', (
      tester,
    ) async {
      final backend = FakeVirtualizationBackend()
        ..lastActionResult = ProcessResult(0, 1, '', 'VM_MUST_BE_RUNNING');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [backendProvider.overrideWithValue(backend)],
          child: testApp(
            home: const VmConsolePage(vm: 'x', confPath: '/tmp/x.conf'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('not running'), findsWidgets);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);
    });
  });

  group('ShortcutsDialog', () {
    testWidgets('lists the documented bindings', (tester) async {
      await tester.pumpWidget(testApp(home: const ShortcutsDialog()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ctrl+1'), findsOneWidget);
      expect(find.textContaining('Ctrl+F'), findsOneWidget);
      expect(find.textContaining('Esc'), findsOneWidget);
      expect(find.textContaining('F1'), findsWidgets);
    });
  });

  group('live regions', () {
    testWidgets('details pane state chip is a live region', (tester) async {
      await tester.pumpWidget(
        testApp(
          home: const Scaffold(
            body: VmDetailsPane(name: 'vm1', state: 'running', conf: {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final semantics = tester.widgetList<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false),
        ),
      );
      expect(semantics, isNotEmpty);
    });
  });
}
