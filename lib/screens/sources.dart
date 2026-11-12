import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../widgets/feed_dialogs.dart';
import '../widgets/pickers.dart';

/// Alle Feeds mit Thema und Paywall-Quote. Der Schalter schaltet einen Feed
/// ein oder aus; ein Tipp auf den Namen öffnet Name und Thema.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  String _subtitle(FeedEntry e, SourceStats? s) {
    final cat =
        e.categories.isEmpty ? '' : '${tr('cat_${e.categories.first}')}\n';
    if (e.source.unfiltered) return '$cat${tr('filter_off')}';
    if (s == null || s.total == 0) return '$cat${tr('stats_none')}';
    return cat +
        tr('stats_line', {
          'f': s.free,
          'p': s.paywall,
          'u': s.unclear,
          'q': s.paywallPercent,
        });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final all = app.entries;
        final own = all
            .where((e) => !e.isCustom && e.source.country == app.country)
            .toList();
        final other = all
            .where((e) => !e.isCustom && e.source.country != app.country)
            .toList();
        final custom = all.where((e) => e.isCustom).toList();

        Widget tile(FeedEntry e) => ListTile(
              title: Text(e.listName),
              subtitle: Text(_subtitle(e, app.stats[e.url])),
              isThreeLine: true,
              onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => EditFeedDialog(entry: e)),
              trailing: Switch(
                value: e.enabled,
                onChanged: (v) => app.setFeedEnabled(e.url, v),
              ),
            );

        return Scaffold(
          appBar: AppBar(title: Text(tr('nav_sources'))),
          floatingActionButton: FloatingActionButton(
            tooltip: tr('add_feed'),
            onPressed: () => showAddFeed(context),
            child: const Icon(Icons.add),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(tr('sources_hint'), style: text.bodySmall),
              ),
              if (all.isEmpty) ListTile(title: Text(tr('err_no_sources'))),
              if (own.isNotEmpty) SectionHeader(tr('src_own_country')),
              for (final e in own) tile(e),
              if (other.isNotEmpty) SectionHeader(tr('src_other')),
              for (final e in other) tile(e),
              if (custom.isNotEmpty) SectionHeader(tr('src_custom')),
              for (final e in custom) tile(e),
            ],
          ),
        );
      },
    );
  }
}
