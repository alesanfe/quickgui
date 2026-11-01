import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// Host-directory input with a native picker (QGUI-SHARE-001): an
/// editable path plus a Browse button, validated for existence so a
/// typo surfaces before saving instead of failing at launch.
class PathPickerField extends StatelessWidget {
  const PathPickerField({
    required this.controller,
    required this.label,
    this.helper,
    this.allowEmpty = true,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              helperText: helper,
              helperMaxLines: 4,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            validator: (raw) {
              final v = (raw ?? '').trim();
              if (v.isEmpty) {
                return allowEmpty ? null : context.t('Pick a directory');
              }
              if (!Directory(v).existsSync()) {
                return context.t('The directory does not exist');
              }
              return null;
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 4),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(context.t('Browse')),
            onPressed: () async {
              final dir = await FilePicker.getDirectoryPath(
                dialogTitle: context.t('Pick a folder'),
              );
              if (dir != null && dir.isNotEmpty) {
                controller.text = dir;
              }
            },
          ),
        ),
      ],
    );
  }
}
