import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';
import 'package:quickgui/features/machines/presentation/shared/validated_text_dialog.dart';
import 'package:quickgui/features/machines/presentation/shared/vm_input_messages.dart';

import '../support/harness/test_app.dart';

void main() {
  testWidgets('disables confirm and shows an error for an unsafe name', (
    tester,
  ) async {
    String? result = 'untouched';
    await tester.pumpWidget(
      testApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showValidatedTextDialog<VmNameError>(
                context: context,
                title: 'Clone',
                label: 'New VM name',
                confirmLabel: 'OK',
                initialValue: 'vm-copy',
                dirty: VmNameInput.dirty,
                message: (context, e) => context.vmNameError(e),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '../etc');
    await tester.pump();
    expect(
      find.text('Use letters, digits, dot, dash or underscore'),
      findsOneWidget,
    );
    final ok = tester.widget<TextButton>(find.widgetWithText(TextButton, 'OK'));
    expect(ok.onPressed, isNull);

    await tester.enterText(find.byType(TextField), ' good-name ');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    expect(result, 'good-name');
  });
}
