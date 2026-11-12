import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
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
            Text('Willkommen', style: text.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Du siehst nur Artikel, die frei lesbar sind. Beiträge hinter '
              'einer Bezahlschranke werden ausgeblendet.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 32),
            Text('Deine Region', style: text.titleMedium),
            const SizedBox(height: 4),
            Text('Automatisch erkannt – bei Bedarf anpassen.',
                style: text.bodySmall),
            const SizedBox(height: 8),
            RegionPicker(
              country: country,
              language: language,
              onChanged: (c, l) => setState(() {
                country = c;
                language = l;
              }),
            ),
            const SizedBox(height: 32),
            Text('Was interessiert dich?', style: text.titleMedium),
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
                      kCategories.keys.where(selected.contains).toList()),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: const Text('Los geht\'s'),
            ),
          ],
        ),
      ),
    );
  }
}
