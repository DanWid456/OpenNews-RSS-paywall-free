import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../screens/reader.dart';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'gerade eben';
  if (d.inMinutes < 60) return 'vor ${d.inMinutes} Min.';
  if (d.inHours < 24) return 'vor ${d.inHours} Std.';
  if (d.inDays < 7) return 'vor ${d.inDays} T.';
  return '${t.day}.${t.month}.${t.year}';
}

String categoryLabel(Article a) =>
    a.categories.isEmpty ? '' : (kCategories[a.categories.first] ?? '');

/// Öffnet die Leseansicht (bei Volltext im Feed) oder den In-App-Browser.
Future<void> openArticle(BuildContext context, Article a) async {
  final app = AppState.instance;
  await app.markRead(a);
  if (!context.mounted) return;
  if (a.hasFullText) {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ReaderScreen(article: a)));
  } else {
    await app.openInBrowser(a.link);
  }
}

Future<void> showArticleMenu(BuildContext context, Article a) async {
  final app = AppState.instance;
  final messenger = ScaffoldMessenger.of(context);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading:
                Icon(a.bookmarked ? Icons.bookmark : Icons.bookmark_border),
            title: Text(a.bookmarked ? 'Aus Merkliste entfernen' : 'Merken'),
            onTap: () {
              Navigator.pop(sheet);
              app.toggleBookmark(a);
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: const Text('Original öffnen'),
            onTap: () {
              Navigator.pop(sheet);
              app.markRead(a);
              app.openInBrowser(a.link);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Als Paywall melden'),
            subtitle: const Text('Blendet den Artikel aus'),
            onTap: () async {
              Navigator.pop(sheet);
              await app.reportPaywall(a);
              messenger.showSnackBar(SnackBar(
                content: const Text('Artikel ausgeblendet.'),
                action: kIssuesConfigured
                    ? SnackBarAction(
                        label: 'Weitermelden',
                        onPressed: () => app.openIssueFor(a))
                    : null,
              ));
            },
          ),
        ],
      ),
    ),
  );
}

class _Meta extends StatelessWidget {
  final Article article;
  final bool showCategory;
  const _Meta(this.article, {this.showCategory = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    final cat = showCategory ? categoryLabel(article) : '';
    final base = theme.textTheme.bodySmall!.copyWith(color: grey);
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: article.sourceName,
          style: base.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface),
        ),
        if (cat.isNotEmpty) TextSpan(text: ' · $cat'),
        TextSpan(text: ' · ${timeAgo(article.published)}'),
        if (article.status == PaywallStatus.unclear)
          const TextSpan(text: ' · ungeprüft'),
      ]),
      style: base,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? url;
  final double? width;
  final double height;
  final double radius;
  const _Thumb(this.url,
      {this.width, required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
    );
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: (u == null || u.isEmpty)
          ? placeholder
          : Image.network(
              u,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}

TextStyle _titleStyle(BuildContext context, Article a, TextStyle base) {
  final scheme = Theme.of(context).colorScheme;
  return base.copyWith(
    fontWeight: FontWeight.w600,
    color: a.isRead ? scheme.onSurfaceVariant : scheme.onSurface,
  );
}

/// Ansicht 1: nur Titel, sehr dicht.
class CompactTile extends StatelessWidget {
  final Article article;
  const CompactTile(this.article, {super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => openArticle(context, article),
      onLongPress: () => showArticleMenu(context, article),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(article.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _titleStyle(context, article,
                    text.bodyLarge!.copyWith(fontSize: 15, height: 1.33))),
            const SizedBox(height: 4),
            _Meta(article),
          ],
        ),
      ),
    );
  }
}

/// Ansicht 2: Vorschaubild vorne, Titel und Quelle daneben.
class MagazineTile extends StatelessWidget {
  final Article article;
  const MagazineTile(this.article, {super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => openArticle(context, article),
      onLongPress: () => showArticleMenu(context, article),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumb(article.imageUrl, width: 88, height: 88, radius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 88),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(article.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: _titleStyle(
                            context,
                            article,
                            text.bodyLarge!
                                .copyWith(fontSize: 16, height: 1.31))),
                    const SizedBox(height: 6),
                    _Meta(article, showCategory: false),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ansicht 3: grosszügige Karte mit grossem Bild und Anriss.
class CardTile extends StatelessWidget {
  final Article article;
  const CardTile(this.article, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final app = AppState.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openArticle(context, article),
          onLongPress: () => showArticleMenu(context, article),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((article.imageUrl ?? '').isNotEmpty)
                _Thumb(article.imageUrl, height: 184, radius: 0),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Meta(article),
                    const SizedBox(height: 6),
                    Text(article.title,
                        style: _titleStyle(context, article,
                            text.titleLarge!.copyWith(fontSize: 20))),
                    if (article.summary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(article.summary,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium!.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: article.bookmarked
                            ? 'Aus Merkliste entfernen'
                            : 'Merken',
                        icon: Icon(article.bookmarked
                            ? Icons.bookmark
                            : Icons.bookmark_border),
                        onPressed: () => app.toggleBookmark(article),
                      ),
                      IconButton(
                        tooltip: 'Mehr',
                        icon: const Icon(Icons.more_horiz),
                        onPressed: () => showArticleMenu(context, article),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Baut die Kachel passend zur gewählten Ansicht (0 kompakt, 1 Magazin,
/// 2 Karten).
Widget articleTile(Article a, int viewMode) {
  switch (viewMode) {
    case 0:
      return CompactTile(a, key: ValueKey(a.link));
    case 2:
      return CardTile(a, key: ValueKey(a.link));
    default:
      return MagazineTile(a, key: ValueKey(a.link));
  }
}
