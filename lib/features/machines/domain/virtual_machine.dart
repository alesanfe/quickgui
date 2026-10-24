// Freezed forwards @JsonKey on factory parameters to the generated fields.
// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:quickgui/features/machines/domain/vm_status.dart';

part 'virtual_machine.freezed.dart';
part 'virtual_machine.g.dart';

/// A managed virtual machine. Built from the quickemu v1 contract
/// (`vm-list` items and `vm-status` payloads share name/state/pid).
@freezed
abstract class VirtualMachine with _$VirtualMachine {
  const VirtualMachine._();

  const factory VirtualMachine({
    required String name,
    @JsonKey(name: 'guest_os') String? guestOs,
    @JsonKey(name: 'state', fromJson: VmStatus.fromWire, toJson: _statusToJson)
    @Default(VmStatus.unknown)
    VmStatus status,
    int? pid,
  }) = _VirtualMachine;

  factory VirtualMachine.fromJson(Map<String, dynamic> json) =>
      _$VirtualMachineFromJson(json);

  bool get isRunning => status == VmStatus.running;
}

String _statusToJson(VmStatus status) => status.toWire();
