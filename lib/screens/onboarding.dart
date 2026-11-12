import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../l10n.dart';
import '../widgets/pickers.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final app = AppState.instance;
  late String country = app.country;
  late String language = app.language;
  final Set<String> selected = {'top'};

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            Text(tr('welcome'), style: text.headlineMedium),
            const SizedBox(height: 8),
            Text(tr('welcome_text'), style: text.bodyLarge),
            const SizedBox(height: 32),
            Text(tr('your_region'), style: text.titleMedium),
            const SizedBox(height: 4),
            Text(tr('region_auto'), style: text.bodySmall),
            const SizedBox(height: 12),
            RegionPicker(
              country: country,
              language: language,
              onChanged: (c, l) => setState(() {
                country = c;
                language = l;
              }),
            ),
            const SizedBox(height: 32),
            Text(tr('interests_q'), style: text.titleMedium),
            const SizedBox(height: 12),
            InterestChips(
              selected: selected,
              onChanged: (s) => setState(() {
                selected
                  ..clear()
                  ..addAll(s);
              }),
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => app.finishOnboarding(country, language,
                      kCategoryIds.where(selected.contains).toList()),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: Text(tr('start')),
            ),
          ],
        ),
      ),
    );
  }
}
