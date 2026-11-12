import 'dart:convert';

/// Prüfstatus eines Artikels. Die Reihenfolge ist Teil des DB-Formats.
enum PaywallStatus { unchecked, free, paywall, unclear }

List<String> _strList(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : <String>[];

class PaywallRules {
  final List<String> urlContains;
  final List<String> titlePrefixes;
  final List<String> textContains;
  final List<String> htmlContains;

  const PaywallRules({
    this.urlContains = const [],
    this.titlePrefixes = const [],
    this.textContains = const [],
    this.htmlContains = const [],
  });

  factory PaywallRules.fromJson(dynamic j) {
    if (j is! Map) return const PaywallRules();
    return PaywallRules(
      urlContains: _strList(j['urlContains']),
      titlePrefixes: _strList(j['titlePrefixes']),
      textContains: _strList(j['textContains']),
      htmlContains: _strList(j['htmlContains']),
    );
  }

  PaywallRules merge(PaywallRules o) => PaywallRules(
        urlContains: [...urlContains, ...o.urlContains],
        titlePrefixes: [...titlePrefixes, ...o.titlePrefixes],
        textContains: [...textContains, ...o.textContains],
        htmlContains: [...htmlContains, ...o.htmlContains],
      );
}

class FeedDef {
  final String url;
  final List<String> categories;
  const FeedDef(this.url, this.categories);
}

class NewsSource {
  final String id;
  final String name;
  final String country;
  final String language;
  final PaywallRules rules;
  final List<FeedDef> feeds;
  final bool isCustom;

  /// Nur bei eigenen Feeds: alle Beiträge ohne Paywall-Prüfung anzeigen.
  final bool unfiltered;

  const NewsSource({
    required this.id,
    required this.name,
    required this.country,
    required this.language,
    required this.rules,
    required this.feeds,
    this.isCustom = false,
    this.unfiltered = false,
  });
}

class FeedCatalog {
  final int schemaVersion;
  final int version;
  final PaywallRules generic;
  final List<NewsSource> sources;

  const FeedCatalog({
    required this.schemaVersion,
    required this.version,
    required this.generic,
    required this.sources,
  });

  factory FeedCatalog.empty() => const FeedCatalog(
      schemaVersion: 1, version: 0, generic: PaywallRules(), sources: []);

  /// Wirft [FormatException], wenn die Datei nicht brauchbar ist.
  static FeedCatalog parse(String text) {
    final j = jsonDecode(text);
    if (j is! Map) throw const FormatException('feeds.json: kein Objekt');
    final schema = j['schemaVersion'];
    final version = j['version'];
    final rawSources = j['sources'];
    if (schema is! int || version is! int || rawSources is! List) {
      throw const FormatException('feeds.json: Pflichtfelder fehlen');
    }
    final sources = <NewsSource>[];
    for (final s in rawSources) {
      if (s is! Map) continue;
      final id = s['id']?.toString() ?? '';
      final rawFeeds = s['feeds'];
      if (id.isEmpty || rawFeeds is! List) continue;
      final feeds = <FeedDef>[];
      for (final f in rawFeeds) {
        if (f is! Map) continue;
        final url = f['url']?.toString() ?? '';
        if (!url.startsWith('http')) continue;
        feeds.add(FeedDef(url, _strList(f['categories'])));
      }
      if (feeds.isEmpty) continue;
      sources.add(NewsSource(
        id: id,
        name: s['name']?.toString() ?? id,
        country: (s['country']?.toString() ?? '').toUpperCase(),
        language: (s['language']?.toString() ?? '').toLowerCase(),
        rules: PaywallRules.fromJson(s['paywall']),
        feeds: feeds,
      ));
    }
    if (sources.isEmpty) {
      throw const FormatException('feeds.json: keine gültigen Quellen');
    }
    return FeedCatalog(
      schemaVersion: schema,
      version: version,
      generic: PaywallRules.fromJson(j['generic']),
      sources: sources,
    );
  }
}

class CustomFeed {
  final String url;
  final String title;
  final String category;
  final bool unfiltered;
  const CustomFeed(this.url, this.title, this.category, this.unfiltered);

  String get sourceId => 'custom:$url';

  NewsSource toSource() => NewsSource(
        id: sourceId,
        name: title,
        country: '',
        language: '',
        rules: const PaywallRules(),
        feeds: [
          FeedDef(url, [category])
        ],
        isCustom: true,
        unfiltered: unfiltered,
      );
}

class Article {
  final String link;
  final String sourceId;
  final String sourceName;
  final String title;
  final String summary;
  final String? imageUrl;

  /// Volltext aus dem Feed (HTML), falls der Feed ihn mitliefert.
  final String? content;
  final List<String> categories;

  /// Adressen aller Feeds, in denen der Artikel vorkam.
  final List<String> feedUrls;
  final DateTime published;
  final PaywallStatus status;
  final bool isRead;
  final bool bookmarked;

  const Article({
    required this.link,
    required this.feedUrls,
    required this.sourceId,
    required this.sourceName,
    required this.title,
    required this.summary,
    required this.categories,
    required this.published,
    required this.status,
    this.imageUrl,
    this.content,
    this.isRead = false,
    this.bookmarked = false,
  });

  bool get hasFullText => (content ?? '').length > 1500;

  Map<String, Object?> toMap() => {
        'link': link,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'title': title,
        'summary': summary,
        'imageUrl': imageUrl,
        'content': content,
        'categories': categories.join(','),
        'feedUrl': '\n${feedUrls.join('\n')}\n',
        'published': published.millisecondsSinceEpoch,
        'status': status.index,
        'isRead': isRead ? 1 : 0,
        'bookmarked': bookmarked ? 1 : 0,
      };

  factory Article.fromMap(Map<String, Object?> m) {
    final st = (m['status'] as int?) ?? 0;
    final cats = (m['categories'] as String?) ?? '';
    return Article(
      link: m['link'] as String,
      feedUrls: ((m['feedUrl'] as String?) ?? '')
          .split('\n')
          .where((s) => s.isNotEmpty)
          .toList(),
      sourceId: (m['sourceId'] as String?) ?? '',
      sourceName: (m['sourceName'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      summary: (m['summary'] as String?) ?? '',
      imageUrl: m['imageUrl'] as String?,
      content: m['content'] as String?,
      categories: cats.isEmpty ? <String>[] : cats.split(','),
      published: DateTime.fromMillisecondsSinceEpoch(
          (m['published'] as int?) ?? 0),
      status: PaywallStatus.values[
          (st < 0 || st >= PaywallStatus.values.length) ? 0 : st],
      isRead: ((m['isRead'] as int?) ?? 0) == 1,
      bookmarked: ((m['bookmarked'] as int?) ?? 0) == 1,
    );
  }
}

/// Ein Feed, wie er in der App erscheint: Katalog- oder eigener Feed samt
/// den Anpassungen des Nutzers (Name, Thema, ein/aus).
class FeedEntry {
  final NewsSource source;
  final FeedDef feed;

  /// Kurzer Name für die Artikelliste.
  final String label;

  /// Name in der Quellenliste.
  final String listName;
  final List<String> categories;
  final bool enabled;

  const FeedEntry({
    required this.source,
    required this.feed,
    required this.label,
    required this.listName,
    required this.categories,
    required this.enabled,
  });

  String get url => feed.url;
  bool get isCustom => source.isCustom;
}

class FeedSuggestion {
  final String title;
  final String url;
  const FeedSuggestion(this.title, this.url);
}

/// Zähler pro Feed für die Paywall-Quote.
class SourceStats {
  int free = 0;
  int paywall = 0;
  int unclear = 0;

  int get total => free + paywall + unclear;
  int get paywallPercent => total == 0 ? 0 : (paywall * 100 / total).round();
}
