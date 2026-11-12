import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

class ParsedItem {
  final String title;
  final String link;
  final String summary;
  final String? content;
  final String? imageUrl;
  final DateTime? published;
  const ParsedItem({
    required this.title,
    required this.link,
    required this.summary,
    this.content,
    this.imageUrl,
    this.published,
  });
}

class ParsedFeed {
  final String title;
  final List<ParsedItem> items;
  const ParsedFeed(this.title, this.items);
}

Iterable<XmlElement> _kids(XmlElement e) => e.children.whereType<XmlElement>();

XmlElement? _first(XmlElement e, String local, {bool noPrefix = false}) {
  for (final c in _kids(e)) {
    if (c.name.local == local && (!noPrefix || c.name.prefix == null)) {
      return c;
    }
  }
  return null;
}

String _text(XmlElement e, String local, {bool noPrefix = false}) =>
    (_first(e, local, noPrefix: noPrefix)?.innerText ?? '').trim();

/// Entfernt HTML-Tags und fasst Leerraum zusammen.
String stripHtml(String s) {
  if (s.isEmpty) return '';
  final t = html.parseFragment(s).text ?? '';
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

final _imgRe = RegExp('<img[^>]+src=["\']([^"\']+)["\']', caseSensitive: false);

String? _firstImg(String htmlText) => _imgRe.firstMatch(htmlText)?.group(1);

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

final _rfc822 = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]+)?');

/// Versteht ISO-8601 (Atom, dc:date) und RFC-822 (RSS pubDate).
DateTime? parseFeedDate(String s) {
  s = s.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.toLocal();
  final m = _rfc822.firstMatch(s);
  if (m == null) return null;
  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  var dt = DateTime.utc(
    int.parse(m.group(3)!),
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6) ?? '0'),
  );
  final zone = m.group(7);
  if (zone != null && (zone.startsWith('+') || zone.startsWith('-'))) {
    final sign = zone.startsWith('-') ? -1 : 1;
    final minutes =
        int.parse(zone.substring(1, 3)) * 60 + int.parse(zone.substring(3, 5));
    dt = dt.subtract(Duration(minutes: sign * minutes));
  }
  return dt.toLocal();
}

String? _imageOf(XmlElement item, String rawSummary, String? rawContent) {
  for (final c in _kids(item)) {
    final local = c.name.local;
    final prefix = c.name.prefix;
    if (prefix == 'media' && (local == 'content' || local == 'thumbnail')) {
      final url = c.getAttribute('url');
      final type = c.getAttribute('type') ?? '';
      final medium = c.getAttribute('medium') ?? '';
      final isImage = local == 'thumbnail' ||
          type.startsWith('image') ||
          medium == 'image' ||
          (type.isEmpty && medium.isEmpty);
      if (url != null && url.isNotEmpty && isImage) return url;
    }
    if (prefix == 'media' && local == 'group') {
      final inner = _imageOf(c, '', null);
      if (inner != null) return inner;
    }
    if (local == 'enclosure') {
      final url = c.getAttribute('url');
      final type = c.getAttribute('type') ?? '';
      if (url != null && url.isNotEmpty && type.startsWith('image')) {
        return url;
      }
    }
  }
  return _firstImg(rawContent ?? '') ?? _firstImg(rawSummary);
}

String _atomLink(XmlElement entry) {
  String fallback = '';
  for (final c in _kids(entry)) {
    if (c.name.local != 'link') continue;
    final href = c.getAttribute('href') ?? '';
    if (href.isEmpty) continue;
    final rel = c.getAttribute('rel');
    if (rel == null || rel == 'alternate') return href;
    if (fallback.isEmpty) fallback = href;
  }
  return fallback;
}

/// Liest RSS 2.0, RSS 1.0 (RDF) und Atom. Wirft bei ungültigem XML.
ParsedFeed parseFeed(String body) {
  // trimLeft entfernt auch ein führendes Byte-Order-Mark.
  final doc = XmlDocument.parse(body.trimLeft());
  final root = doc.rootElement;
  final isAtom = root.name.local == 'feed';

  String feedTitle;
  Iterable<XmlElement> nodes;
  if (isAtom) {
    feedTitle = _text(root, 'title');
    nodes = _kids(root).where((e) => e.name.local == 'entry');
  } else {
    final channel = _first(root, 'channel');
    feedTitle = channel == null ? '' : _text(channel, 'title', noPrefix: true);
    nodes = root.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'item');
  }

  final items = <ParsedItem>[];
  for (final n in nodes) {
    final title = stripHtml(_text(n, 'title', noPrefix: true));
    final link = isAtom ? _atomLink(n) : _text(n, 'link', noPrefix: true);
    var rawSummary = _text(n, 'description', noPrefix: true);
    if (rawSummary.isEmpty) rawSummary = _text(n, 'summary');
    String? rawContent = _text(n, 'encoded');
    if (rawContent.isEmpty) rawContent = isAtom ? _text(n, 'content') : '';
    if (rawContent.isEmpty) rawContent = null;

    var dateText = _text(n, 'pubDate');
    if (dateText.isEmpty) dateText = _text(n, 'published');
    if (dateText.isEmpty) dateText = _text(n, 'updated');
    if (dateText.isEmpty) dateText = _text(n, 'date');

    var summary = stripHtml(rawSummary);
    if (summary.isEmpty && rawContent != null) summary = stripHtml(rawContent);
    if (summary.length > 400) summary = '${summary.substring(0, 400)}…';

    items.add(ParsedItem(
      title: title,
      link: link.trim(),
      summary: summary,
      content: rawContent,
      imageUrl: _imageOf(n, rawSummary, rawContent),
      published: parseFeedDate(dateText),
    ));
  }
  return ParsedFeed(stripHtml(feedTitle), items);
}
