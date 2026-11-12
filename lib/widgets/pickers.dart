import 'package:flutter/material.dart';

import '../config.dart';
import '../l10n.dart';

/// Abschnittsüberschrift: Grossbuchstaben, blau.
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.titleSmall!.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Umrandetes Auswahlfeld. [options]: Wert -> Anzeigetext.
class LabeledDropdown extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.containsKey(value) ? value : options.keys.first,
          isExpanded: true,
          items: [
            for (final e in options.entries)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Auswahl von Land und Sprache der Nachrichten.
class RegionPicker extends StatelessWidget {
  final String country;
  final String language;
  final void Function(String country, String language) onChanged;

  const RegionPicker({
    super.key,
    required this.country,
    required this.language,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LabeledDropdown(
          label: tr('country'),
          value: country,
          options: {for (final c in kCountries.keys) c: tr('country_$c')},
          onChanged: (v) => onChanged(v, language),
        ),
        const SizedBox(height: 12),
        LabeledDropdown(
          label: tr('news_language'),
          value: language,
          options: kLanguages,
          onChanged: (v) => onChanged(country, v),
        ),
      ],
    );
  }
}

/// Themen-Auswahl als Chips.
class InterestChips extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const InterestChips(
      {super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final id in kCategoryIds)
          FilterChip(
            label: Text(tr('cat_$id')),
            selected: selected.contains(id),
            onSelected: (on) {
              final next = {...selected};
              if (on) {
                next.add(id);
              } else {
                next.remove(id);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

/// Auswahl eines einzelnen Themas.
class CategoryDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const CategoryDropdown(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LabeledDropdown(
      label: tr('topic'),
      value: value,
      options: {for (final id in kCategoryIds) id: tr('cat_$id')},
      onChanged: onChanged,
    );
  }
}
