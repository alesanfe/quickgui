import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';
import 'package:url_launcher/url_launcher.dart';

/// Inline contextual help for a field or option (QGUI-UX-001).
///
/// The essential information — what the setting does, a valid example
/// and any constraint — is rendered below the control instead of
/// hiding it behind a tooltip, so it stays visible without hover, at
/// 200% text scale and for keyboard-only users.
class FieldHelp extends StatelessWidget {
  const FieldHelp({
    required this.description,
    this.example,
    this.constraint,
    this.dependency,
    this.docLabel,
    this.docUrl,
    super.key,
  });

  /// What the setting does, in user vocabulary.
  final String description;

  /// A valid example value, rendered in monospace.
  final String? example;

  /// A restriction the value must satisfy (shown with an icon).
  final String? constraint;

  /// "Requires X" — explains why the control may be disabled or what
  /// else must be enabled first.
  final String? dependency;

  /// Optional link to external documentation.
  final String? docLabel;
  final String? docUrl;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final mono = style?.copyWith(fontFamily: 'monospace');
    return Semantics(
      container: true,
      label: description,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description, style: style),
            if (example != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SelectableText(
                  context.t('Example: {0}', args: [example!]),
                  style: mono,
                ),
              ),
            if (constraint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.rule,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: Text(constraint!, style: style)),
                  ],
                ),
              ),
            if (dependency != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.link,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: Text(dependency!, style: style)),
                  ],
                ),
              ),
            if (docUrl != null)
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => launchUrl(
                    Uri.parse(docUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      docLabel ?? context.t('Documentation'),
                      style: style?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
