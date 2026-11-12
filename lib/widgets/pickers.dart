import 'package:flutter/material.dart';

import '../config.dart';

/// Auswahl von Land und Sprache.
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
    return Row(
      children: [
        Expanded(
          child: _Dropdown(
            label: 'Land',
            value: country,
            options: kCountries,
            onChanged: (v) => onChanged(v, language),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Dropdown(
            label: 'Sprache',
            value: language,
            options: kLanguages,
            onChanged: (v) => onChanged(country, v),
          ),
        ),
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const _Dropdown({
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
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
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
        for (final e in kCategories.entries)
          FilterChip(
            label: Text(e.value),
            selected: selected.contains(e.key),
            onSelected: (on) {
              final next = {...selected};
              if (on) {
                next.add(e.key);
              } else {
                next.remove(e.key);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

/// Auswahl eines einzelnen Themas (für eigene Feeds).
class CategoryDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const CategoryDropdown(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _Dropdown(
      label: 'Thema',
      value: value,
      options: kCategories,
      onChanged: onChanged,
    );
  }
}
