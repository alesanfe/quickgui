import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // Keyboard/focus traversal — the AT contract requires every action
  // reachable without a pointer.
  group('keyboard traversal', () {
    testWidgets('Tab moves focus through console input and buttons', (
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

      var moved = 0;
      String? last;
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final node = FocusManager.instance.primaryFocus;
        final desc = node?.toStringShort() ?? '';
        if (desc != last) moved++;
        last = desc;
      }
      // Focus must actually travel — a broken traversal keeps the same node.
      expect(moved, greaterThan(2));
      expect(FocusManager.instance.primaryFocus, isNotNull);
    });

    testWidgets('Escape dismisses the shortcuts dialog', (tester) async {
      await tester.pumpWidget(
        testApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ShortcutsDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(ShortcutsDialog), findsNothing);
    });
  });

  // AT-SPI semantic contract — what Orca/voiceover must observe. Pins the
  // semantics properties that accessibility tools consume.
  group('AT-SPI contract', () {
    testWidgets('state chip exposes live region semantics', (tester) async {
      await tester.pumpWidget(
        testApp(
          home: const Scaffold(
            body: VmDetailsPane(name: 'vm1', state: 'running', conf: {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.liveRegion ?? false),
        ),
        findsWidgets,
      );
    });

    testWidgets('icon buttons carry button flag and a11y label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
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
      final iconButtons = find.byType(IconButton);
      expect(iconButtons, findsWidgets);
      var labelled = 0;
      final total = tester.widgetList(iconButtons).length;
      for (var i = 0; i < total; i++) {
        final node = tester.getSemantics(iconButtons.at(i));
        final data = node.getSemanticsData();
        if (data.flagsCollection.isButton &&
            (data.label.isNotEmpty || data.tooltip.isNotEmpty)) {
          labelled++;
        }
      }
      // Every icon button Orca can reach must announce a purpose.
      expect(total, greaterThan(0));
      expect(labelled, total);
      semantics.dispose();
    });

    testWidgets('console text input is a focusable text field', (tester) async {
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
      expect(find.byWidgetPredicate((w) => w is EditableText), findsOneWidget);
    });
  });
}
