import 'package:flutter/widgets.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:quickgui/features/machines/domain/forms/vm_inputs.dart';

/// Localised messages for Formz validation errors.
extension VmInputMessages on BuildContext {
  String? vmNameError(VmNameError? e) => switch (e) {
    null => null,
    VmNameError.empty => t('A name is required'),
    VmNameError.tooLong => t('The name is too long'),
    VmNameError.invalidCharacters => t(
      'Use letters, digits, dot, dash or underscore',
    ),
  };

  String? sizeError(SizeError? e) => switch (e) {
    null => null,
    SizeError.empty => t('A size is required'),
    SizeError.invalidFormat => t('Use a size like 4G or 4096M'),
  };

  String? cpuCoresError(CpuCoresError? e) => switch (e) {
    null => null,
    CpuCoresError.notANumber => t('Enter a whole number'),
    CpuCoresError.outOfRange => t('Enter a value between 1 and 256'),
  };
}
