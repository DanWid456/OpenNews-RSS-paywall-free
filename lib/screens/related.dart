import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../widgets/tiles.dart';

/// Weitere Beiträge zum Thema eines Artikels (aus den geladenen Quellen).
class RelatedScreen extends StatelessWidget {
  final Article article;
  const RelatedScreen({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('menu_more'))),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final items = app.related(article);
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(article.title,
                    style: theme.textTheme.titleMedium!
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              const Divider(),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(tr('related_empty'),
                      textAlign: TextAlign.center),
                ),
              for (final a in items) ...[
                articleTile(a, 1),
                const Divider(),
              ],
            ],
          );
        },
      ),
    );
  }
}
