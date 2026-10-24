import 'package:flutter_test/flutter_test.dart';
import 'package:formz/formz.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';

void main() {
  group('VmNameInput', () {
    test('pure input reports no error until dirty', () {
      expect(const VmNameInput.pure().displayError, isNull);
      expect(const VmNameInput.dirty().displayError, VmNameError.empty);
    });

    for (final ok in ['ubuntu-24.04', 'win11', 'my_vm.2', 'A']) {
      test('accepts $ok', () => expect(VmNameInput.dirty(ok).isValid, isTrue));
    }

    for (final bad in [
      '../etc',
      'a/b',
      '.hidden',
      '-flag',
      'with space',
      'café',
    ]) {
      test('rejects $bad', () {
        expect(VmNameInput.dirty(bad).error, VmNameError.invalidCharacters);
      });
    }

    test('rejects names longer than the limit', () {
      expect(VmNameInput.dirty('a' * 65).error, VmNameError.tooLong);
    });
  });

  group('SizeInput', () {
    for (final ok in ['4G', '4096M', '1.5T', '64g', '512']) {
      test('accepts $ok', () => expect(SizeInput.dirty(ok).isValid, isTrue));
    }
    for (final bad in ['0G', 'G', '4GB', '-1G', '4 G', 'abc']) {
      test('rejects $bad', () {
        expect(SizeInput.dirty(bad).error, SizeError.invalidFormat);
      });
    }
    test('empty is valid only when optional', () {
      expect(const SizeInput.dirty('', true).isValid, isTrue);
      expect(const SizeInput.dirty().error, SizeError.empty);
    });
  });

  group('CpuCoresInput', () {
    test('empty means default', () {
      expect(const CpuCoresInput.dirty().isValid, isTrue);
    });
    test('validates range and type', () {
      expect(const CpuCoresInput.dirty('4').isValid, isTrue);
      expect(const CpuCoresInput.dirty('0').error, CpuCoresError.outOfRange);
      expect(const CpuCoresInput.dirty('999').error, CpuCoresError.outOfRange);
      expect(const CpuCoresInput.dirty('four').error, CpuCoresError.notANumber);
    });
  });

  test('Formz.validate combines the create-VM form', () {
    expect(
      Formz.validate([
        const SizeInput.dirty('4G', true),
        const CpuCoresInput.dirty('2'),
        const SizeInput.dirty('64G', true),
      ]),
      isTrue,
    );
    expect(
      Formz.validate([
        const SizeInput.dirty('4GB', true),
        const CpuCoresInput.dirty('2'),
      ]),
      isFalse,
    );
  });
}
