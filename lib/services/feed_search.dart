import 'package:html/parser.dart' as html;

import '../models.dart';
import 'net.dart';
import 'rss_parser.dart';

const _tlds = {
  'CH': ['ch', 'com', 'de', 'org'],
  'DE': ['de', 'com', 'org'],
  'AT': ['at', 'com', 'de', 'org'],
};

/// Liest die Feed-Verweise aus dem HTML einer Webseite
/// (`<link rel="alternate" type="application/rss+xml" …>`).
List<FeedSuggestion> _discover(String body, Uri base) {
  final out = <FeedSuggestion>[];
  final doc = html.parse(body);
  final siteTitle = doc.querySelector('title')?.text.trim() ?? base.host;
  for (final link in doc.querySelectorAll('link')) {
    final rel = (link.attributes['rel'] ?? '').toLowerCase();
    final type = (link.attributes['type'] ?? '').toLowerCase();
    final href = link.attributes['href'] ?? '';
    if (!rel.contains('alternate') || href.isEmpty) continue;
    if (!type.contains('rss') && !type.contains('atom')) continue;
    final Uri url;
    try {
      url = base.resolve(href);
    } catch (_) {
      continue;
    }
    if (!url.scheme.startsWith('http')) continue;
    final title = (link.attributes['title'] ?? '').trim();
    out.add(FeedSuggestion(title.isEmpty ? siteTitle : title, url.toString()));
    if (out.length >= 4) break;
  }
  return out;
}

/// Prüft eine Adresse: Ist sie selbst ein Feed, oder verweist die Seite
/// auf Feeds?
Future<List<FeedSuggestion>> _probe(String address) async {
  final Uri uri;
  try {
    uri = Uri.parse(address);
  } catch (_) {
    return const [];
  }
  final res = await fetchUrl(address,
      maxBytes: 600000, timeout: const Duration(seconds: 7));
  if (res == null || res.status != 200 || res.bytes.isEmpty) return const [];
  final body = decodeBody(res.bytes);
  try {
    final feed = parseFeed(body);
    if (feed.items.isNotEmpty) {
      return [
        FeedSuggestion(feed.title.isEmpty ? uri.host : feed.title, address)
      ];
    }
  } catch (_) {
    // Kein Feed – dann ist es vermutlich eine Webseite.
  }
  try {
    return _discover(body, uri);
  } catch (_) {
    return const [];
  }
}

/// Sucht Feeds zu einem Stichwort oder einer Adresse. Bei einem Stichwort
/// werden zuerst die bekannten Quellen durchsucht, dann naheliegende
/// Webadressen (z. B. www.stichwort.ch) ausprobiert. Liefert höchstens
/// [limit] Vorschläge.
Future<List<FeedSuggestion>> searchFeeds(
  String query, {
  required FeedCatalog catalog,
  required String country,
  required String Function(NewsSource source, FeedDef feed) nameOf,
  int limit = 8,
}) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final found = <String, FeedSuggestion>{};
  void addAll(Iterable<FeedSuggestion> items) {
    for (final s in items) {
      found.putIfAbsent(s.url, () => s);
    }
  }

  final looksLikeAddress = q.startsWith('http') || q.contains('.');
  if (looksLikeAddress) {
    final address = q.startsWith('http') ? q : 'https://$q';
    addAll(await _probe(address));
  } else {
    final needle = q.toLowerCase();
    for (final s in catalog.sources) {
      if (!s.name.toLowerCase().contains(needle)) continue;
      for (final f in s.feeds) {
        addAll([FeedSuggestion(nameOf(s, f), f.url)]);
      }
    }
    final slug = needle
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '');
    if (slug.length >= 2) {
      final tlds = _tlds[country] ?? const ['com', 'org'];
      final results = await Future.wait(
          [for (final t in tlds) _probe('https://www.$slug.$t')]);
      for (final r in results) {
        addAll(r);
      }
    }
  }
  return found.values.take(limit).toList();
}
