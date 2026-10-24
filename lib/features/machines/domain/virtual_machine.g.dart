// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'virtual_machine.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_VirtualMachine _$VirtualMachineFromJson(Map<String, dynamic> json) =>
    _VirtualMachine(
      name: json['name'] as String,
      guestOs: json['guest_os'] as String?,
      status: json['state'] == null
          ? VmStatus.unknown
          : VmStatus.fromWire(json['state']),
      pid: (json['pid'] as num?)?.toInt(),
    );

Map<String, dynamic> _$VirtualMachineToJson(_VirtualMachine instance) =>
    <String, dynamic>{
      'name': instance.name,
      'guest_os': instance.guestOs,
      'state': _statusToJson(instance.status),
      'pid': instance.pid,
    };
