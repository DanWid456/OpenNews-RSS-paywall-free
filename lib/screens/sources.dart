import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';

/// Quellen der Region mit Paywall-Quote; einzeln abschaltbar.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  String _statsLine(SourceStats? s) {
    if (s == null || s.total == 0) return 'Noch keine geprüften Artikel';
    return '${s.free} frei · ${s.paywall} Paywall · ${s.unclear} unklar '
        '(Paywall-Quote ${s.paywallPercent} %)';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Quellen')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final off = app.disabledSources.toSet();
          final region = app.regionSources;
          final custom = app.customSources;

          Widget tile(NewsSource s) => SwitchListTile(
                title: Text(s.name),
                subtitle: Text(s.unfiltered
                    ? 'Ungefiltert – alle Beiträge werden angezeigt'
                    : _statsLine(app.stats[s.id])),
                value: !off.contains(s.id),
                onChanged: (v) => app.setSourceEnabled(s.id, v),
              );

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Die Paywall-Quote zeigt, wie viele Artikel einer Quelle '
                  'ausgeblendet werden mussten.',
                  style: text.bodySmall,
                ),
              ),
              if (region.isEmpty)
                const ListTile(
                  title: Text('Für diese Region und Sprache sind noch keine '
                      'Quellen hinterlegt.'),
                ),
              for (final s in region) tile(s),
              if (custom.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Eigene Feeds', style: text.titleSmall),
                ),
                for (final s in custom) tile(s),
              ],
            ],
          );
        },
      ),
    );
  }
}
