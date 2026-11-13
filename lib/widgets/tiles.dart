import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../config.dart';
import '../l10n.dart';
import '../models.dart';
import '../screens/reader.dart';
import '../screens/related.dart';

const Color kReadGreen = Color(0xFF2E9E5B);

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr('time_now');
  if (d.inMinutes < 60) return tr('time_min', {'n': d.inMinutes});
  if (d.inHours < 24) return tr('time_h', {'n': d.inHours});
  if (d.inDays < 7) return tr('time_d', {'n': d.inDays});
  return '${t.day}.${t.month}.${t.year}';
}

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

Future<void> shareArticle(Article a) async {
  try {
    await SharePlus.instance
        .share(ShareParams(text: '${a.title}\n${a.link}', subject: a.title));
  } catch (_) {}
}

Future<void> showArticleMenu(BuildContext context, Article a) async {
  final app = AppState.instance;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
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
            title: Text(a.bookmarked ? tr('menu_unsave') : tr('menu_save')),
            onTap: () {
              Navigator.pop(sheet);
              app.toggleBookmark(a);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: Text(tr('menu_share')),
            onTap: () {
              Navigator.pop(sheet);
              shareArticle(a);
            },
          ),
          ListTile(
            leading: const Icon(Icons.dynamic_feed_outlined),
            title: Text(tr('menu_more')),
            onTap: () {
              Navigator.pop(sheet);
              navigator.push(MaterialPageRoute(
                  builder: (_) => RelatedScreen(article: a)));
            },
          ),
          // Nur sinnvoll, wenn ein Tipp die Leseansicht öffnet.
          if (a.hasFullText)
            ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: Text(tr('menu_open')),
            onTap: () {
              Navigator.pop(sheet);
              app.markRead(a);
              app.openInBrowser(a.link);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(tr('menu_report')),
            subtitle: Text(tr('menu_report_sub')),
            onTap: () async {
              Navigator.pop(sheet);
              await app.reportPaywall(a);
              messenger.showSnackBar(SnackBar(
                content: Text(tr('reported')),
                action: kIssuesConfigured
                    ? SnackBarAction(
                        label: tr('report_forward'),
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

/// Grüner Haken für gelesene Artikel.
class ReadMark extends StatelessWidget {
  const ReadMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.check_circle,
        size: 18, color: kReadGreen, semanticLabel: tr('read'));
  }
}

/// Zeile mit Quelle, Thema und Zeit; rechts der Gelesen-Haken.
class _Meta extends StatelessWidget {
  final Article article;
  final bool showCategory;
  final bool showRead;
  const _Meta(this.article, {this.showCategory = true, this.showRead = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = AppState.instance;
    final grey = theme.colorScheme.onSurfaceVariant;
    final catId = showCategory ? app.firstCategory(article) : null;
    final base = theme.textTheme.bodySmall!.copyWith(color: grey);
    final line = Text.rich(
      TextSpan(children: [
        TextSpan(
          text: app.sourceLabel(article),
          style: base.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface),
        ),
        if (catId != null) TextSpan(text: ' · ${tr('cat_$catId')}'),
        TextSpan(text: ' · ${timeAgo(article.published)}'),
        if (article.status == PaywallStatus.unclear)
          TextSpan(text: ' · ${tr('unverified')}'),
      ]),
      style: base,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Row(
      children: [
        Expanded(child: line),
        if (showRead && article.isRead) ...[
          const SizedBox(width: 8),
          const ReadMark(),
        ],
      ],
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

/// Die Titelfarbe bleibt immer gleich; gelesen zeigt nur der grüne Haken.
TextStyle _titleStyle(BuildContext context, TextStyle base) => base.copyWith(
      fontWeight: FontWeight.w600,
      color: Theme.of(context).colorScheme.onSurface,
    );

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
                style: _titleStyle(context,
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
                    _Meta(article, showRead: false),
                    const SizedBox(height: 6),
                    Text(article.title,
                        style: _titleStyle(context,
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
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 12, bottom: 2),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: article.bookmarked
                          ? tr('menu_unsave')
                          : tr('menu_save'),
                      icon: Icon(article.bookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_border),
                      onPressed: () => app.toggleBookmark(article),
                    ),
                    IconButton(
                      tooltip: tr('menu_share'),
                      icon: const Icon(Icons.share_outlined),
                      onPressed: () => shareArticle(article),
                    ),
                    IconButton(
                      tooltip: tr('more'),
                      icon: const Icon(Icons.more_horiz),
                      onPressed: () => showArticleMenu(context, article),
                    ),
                    const Spacer(),
                    if (article.isRead) const ReadMark(),
                  ],
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
