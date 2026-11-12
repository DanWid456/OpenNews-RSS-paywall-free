import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../app_state.dart';
import '../l10n.dart';
import '../models.dart';
import '../widgets/tiles.dart';

/// Ablenkungsfreie Leseansicht für Artikel, deren Feed den Volltext liefert.
class ReaderScreen extends StatelessWidget {
  final Article article;
  const ReaderScreen({super.key, required this.article});

  List<String> _paragraphs() {
    final fragment = html.parseFragment(article.content ?? '');
    final out = <String>[];
    for (final e
        in fragment.querySelectorAll('p, h2, h3, h4, li, blockquote')) {
      final t = e.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) out.add(t);
    }
    if (out.isEmpty) {
      for (final line in (fragment.text ?? '').split('\n')) {
        final t = line.trim();
        if (t.isNotEmpty) out.add(t);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final app = AppState.instance;
    final paragraphs = _paragraphs();
    final image = article.imageUrl ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(app.sourceLabel(article)),
        actions: [
          IconButton(
            tooltip: tr('menu_open'),
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => app.openInBrowser(article.link),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(article.title,
              style: text.headlineSmall!
                  .copyWith(fontWeight: FontWeight.w600, height: 1.25)),
          const SizedBox(height: 8),
          Text('${app.sourceLabel(article)} · ${timeAgo(article.published)}',
              style: text.bodySmall!
                  .copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (image.isNotEmpty) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          ],
          const SizedBox(height: 16),
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(p,
                  style: text.bodyLarge!.copyWith(fontSize: 17, height: 1.55)),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => app.openInBrowser(article.link),
            icon: const Icon(Icons.open_in_browser),
            label: Text(tr('menu_open')),
          ),
        ],
      ),
    );
  }
}
