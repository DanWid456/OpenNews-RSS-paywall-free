import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'l10n.dart';
import 'models.dart';
import 'services/db.dart';
import 'services/feed_search.dart';
import 'services/net.dart';
import 'services/paywall.dart';
import 'services/purchases.dart';
import 'services/region.dart';
import 'services/rss_parser.dart';

/// Gesamter App-Zustand: Einstellungen, Quellenkatalog, Artikel und Abruf.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  late SharedPreferences _prefs;
  final AppDb db = AppDb();
  final ProService pro = ProService();

  FeedCatalog catalog = FeedCatalog.empty();
  List<CustomFeed> customFeeds = [];
  List<Article> _articles = [];
  List<Article> bookmarks = [];
  Map<String, SourceStats> stats = {};
  int hiddenCount = 0;

  /// Anpassungen pro Feed-Adresse: `name`, `category`, `enabled`.
  Map<String, Map<String, dynamic>> _overrides = {};

  List<FeedEntry>? _entries;
  Map<String, FeedEntry>? _entryByUrl;

  bool refreshing = false;
  int checkTotal = 0;
  int checkDone = 0;
  String? lastError;

  /// Aktuell gewähltes Thema im Feed (`null` = alle).
  String? selectedCategory;
  String search = '';

  @override
  void notifyListeners() {
    // Jede Zustandsänderung kann Namen, Themen oder Auswahl der Feeds
    // betreffen – die abgeleitete Liste wird beim nächsten Zugriff neu gebaut.
    _entries = null;
    _entryByUrl = null;
    super.notifyListeners();
  }

  // --- Einstellungen ---

  bool get onboarded => _prefs.getBool('onboarded') ?? false;
  String get country => _prefs.getString('country') ?? 'CH';
  String get language => _prefs.getString('language') ?? 'de';

  List<String> get interests {
    final stored = _prefs.getStringList('interests') ?? const <String>[];
    final valid = kCategoryIds.where(stored.contains).toList();
    return valid.isEmpty ? const ['top'] : valid;
  }

  int get viewMode => _prefs.getInt('viewMode') ?? 1;
  bool get deepCheck => _prefs.getBool('deepCheck') ?? true;
  List<String> get mutedWords => _prefs.getStringList('mutedWords') ?? const [];
  ThemeMode get themeMode =>
      ThemeMode.values[(_prefs.getInt('themeMode') ?? 0).clamp(0, 2).toInt()];

  /// `system` oder ein Sprachkürzel aus [kUiLanguages].
  String get uiLanguage => _prefs.getString('uiLanguage') ?? 'system';

  bool get isPro => pro.isPro;
  bool get canAddFeed => isPro || customFeeds.length < kFreeCustomFeeds;

  void _applyUiLanguage() {
    final choice = uiLanguage;
    setUiLanguage(choice == 'system'
        ? PlatformDispatcher.instance.locale.languageCode.toLowerCase()
        : choice);
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _applyUiLanguage();
    await db.open();
    await _loadCatalog();
    await _loadCustomFeeds();
    _loadOverrides();
    if (!onboarded) {
      final region = await detectRegion();
      await _prefs.setString('country', region.country);
      await _prefs.setString('language', region.language);
    }
    pro.addListener(notifyListeners);
    unawaited(pro.init(_prefs));
    await _reload(notify: false);
    if (onboarded) {
      unawaited(refresh());
      unawaited(syncCatalog());
    }
  }

  Future<void> _loadCustomFeeds() async {
    final loaded = await db.customFeeds();
    customFeeds = [
      for (final f in loaded)
        kCategoryIds.contains(f.category)
            ? f
            : CustomFeed(f.url, f.title, 'top', f.unfiltered),
    ];
  }

  void _loadOverrides() {
    _overrides = {};
    try {
      final raw = jsonDecode(_prefs.getString('feedOverrides') ?? '{}');
      if (raw is Map) {
        raw.forEach((k, v) {
          if (k is String && v is Map) {
            _overrides[k] = Map<String, dynamic>.from(v);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveOverrides() async {
    await _prefs.setString('feedOverrides', jsonEncode(_overrides));
  }

  // --- Quellenkatalog ---

  Future<void> _loadCatalog() async {
    FeedCatalog? bundled;
    try {
      bundled =
          FeedCatalog.parse(await rootBundle.loadString('assets/feeds.json'));
    } catch (_) {}
    FeedCatalog? stored;
    try {
      final text = await db.kvGet('feeds_json');
      if (text != null) stored = FeedCatalog.parse(text);
    } catch (_) {}
    // Die neuere der beiden Versionen gewinnt (App-Update vs. Online-Update).
    if (stored != null &&
        stored.schemaVersion <= kSupportedSchema &&
        (bundled == null || stored.version > bundled.version)) {
      catalog = stored;
    } else {
      catalog = bundled ?? FeedCatalog.empty();
    }
    _entries = null;
    _entryByUrl = null;
  }

  /// Holt eine neuere feeds.json von GitHub. Gibt eine Statusmeldung zurück.
  Future<String> syncCatalog() async {
    if (!kRemoteConfigured) return tr('sync_off');
    final res = await fetchUrl(kRemoteFeedsUrl, maxBytes: 2000000);
    if (res == null || res.status != 200) return tr('sync_unreachable');
    try {
      final text = decodeBody(res.bytes);
      final remote = FeedCatalog.parse(text);
      if (remote.schemaVersion > kSupportedSchema) {
        return tr('sync_needs_update');
      }
      if (remote.version <= catalog.version) {
        return tr('sync_current', {'v': catalog.version});
      }
      await db.kvSet('feeds_json', text);
      catalog = remote;
      notifyListeners();
      unawaited(refresh());
      return tr('sync_updated', {'v': remote.version});
    } catch (_) {
      return tr('sync_invalid');
    }
  }

  // --- Feeds, wie sie in der App erscheinen ---

  String _defaultListName(NewsSource s, List<String> cats) {
    if (s.feeds.length > 1 && cats.isNotEmpty) {
      return '${s.name} – ${tr('cat_${cats.first}')}';
    }
    return s.name;
  }

  List<FeedEntry> _buildEntries() {
    // Katalogquellen in der Nachrichtensprache; gibt es keine, die des Landes.
    var sources =
        catalog.sources.where((x) => x.language == language).toList();
    if (sources.isEmpty) {
      sources = catalog.sources.where((x) => x.country == country).toList();
    }
    final out = <FeedEntry>[];
    for (final s in [...sources, ...customFeeds.map((f) => f.toSource())]) {
      for (final f in s.feeds) {
        final o = _overrides[f.url];
        final name = s.isCustom ? '' : ((o?['name'] as String?) ?? '').trim();
        final cat = s.isCustom ? null : o?['category'] as String?;
        final cats = (cat != null && kCategoryIds.contains(cat))
            ? [cat]
            : f.categories.where(kCategoryIds.contains).toList();
        // Quellen des eigenen Landes und eigene Feeds sind von Haus aus an,
        // gleichsprachige Quellen anderer Länder aus.
        final defaultOn = s.isCustom || s.country == country;
        out.add(FeedEntry(
          source: s,
          feed: f,
          label: name.isNotEmpty ? name : s.name,
          listName: name.isNotEmpty ? name : _defaultListName(s, cats),
          categories: cats,
          enabled: (o?['enabled'] as bool?) ?? defaultOn,
        ));
      }
    }
    return out;
  }

  List<FeedEntry> get entries => _entries ??= _buildEntries();

  Map<String, FeedEntry> get _byUrl =>
      _entryByUrl ??= {for (final e in entries) e.url: e};

  List<FeedEntry> _activeEntriesOf(Article a) => [
        for (final u in a.feedUrls)
          if (_byUrl[u]?.enabled ?? false) _byUrl[u]!,
      ];

  /// Name der Quelle, wie er in der Artikelliste steht.
  String sourceLabel(Article a) {
    for (final u in a.feedUrls) {
      final e = _byUrl[u];
      if (e != null) return e.label;
    }
    return a.sourceName;
  }

  /// Erstes Thema des Artikels (für die Anzeige).
  String? firstCategory(Article a) {
    for (final e in _activeEntriesOf(a)) {
      if (e.categories.isNotEmpty) return e.categories.first;
    }
    return null;
  }

  // --- Artikel-Listen ---

  /// Themen-Reiter im Feed: gewählte Interessen plus Themen eigener Feeds.
  List<String> get tabs {
    final out = <String>{...interests};
    for (final e in entries) {
      if (e.isCustom && e.enabled) out.addAll(e.categories);
    }
    return kCategoryIds.where(out.contains).toList();
  }

  static final _nonWord = RegExp(r'[^a-z0-9äöüàâéèêçîôûìòù]+');

  bool _statusVisible(Article a) =>
      a.status == PaywallStatus.free ||
      a.status == PaywallStatus.unclear ||
      (a.status == PaywallStatus.unchecked && !deepCheck);

  List<Article> get feed {
    final wanted = interests.toSet();
    final muted = mutedWords.map((w) => w.toLowerCase()).toList();
    final query = search.trim().toLowerCase();
    final seen = <String>{};
    final out = <Article>[];
    for (final a in _articles) {
      final active = _activeEntriesOf(a);
      if (active.isEmpty || !_statusVisible(a)) continue;
      final cats = <String>{for (final e in active) ...e.categories};
      final isCustom = active.any((e) => e.isCustom);
      if (!isCustom && !cats.any(wanted.contains)) continue;
      if (selectedCategory != null && !cats.contains(selectedCategory)) {
        continue;
      }
      final text = '${a.title} ${a.summary}'.toLowerCase();
      if (muted.any(text.contains)) continue;
      if (query.isNotEmpty && !text.contains(query)) continue;
      // Gleiche Meldung aus mehreren Feeds nur einmal zeigen.
      final key = a.title.toLowerCase().replaceAll(_nonWord, '');
      if (key.isNotEmpty && !seen.add(key)) continue;
      out.add(a);
    }
    return out;
  }

  Set<String> _keywords(String title) => title
      .toLowerCase()
      .split(_nonWord)
      .where((w) => w.length >= 5)
      .toSet();

  /// Weitere Artikel zum selben Thema: Titel, die mindestens zwei längere
  /// Wörter mit [a] teilen (bei sehr kurzen Titeln eines).
  List<Article> related(Article a) {
    final words = _keywords(a.title);
    if (words.isEmpty) return const [];
    final need = words.length >= 3 ? 2 : 1;
    final scored = <MapEntry<Article, int>>[];
    final seen = <String>{};
    for (final b in _articles) {
      if (b.link == a.link || !_statusVisible(b)) continue;
      if (_activeEntriesOf(b).isEmpty) continue;
      final score = _keywords(b.title).where(words.contains).length;
      if (score < need) continue;
      final key = b.title.toLowerCase().replaceAll(_nonWord, '');
      if (!seen.add(key)) continue;
      scored.add(MapEntry(b, score));
    }
    scored.sort((x, y) {
      final byScore = y.value.compareTo(x.value);
      return byScore != 0
          ? byScore
          : y.key.published.compareTo(x.key.published);
    });
    return scored.take(30).map((e) => e.key).toList();
  }

  Future<void> _reload({bool notify = true}) async {
    _articles = await db.recent();
    bookmarks = await db.bookmarks();
    hiddenCount = await db.hiddenCount();
    final s = <String, SourceStats>{};
    for (final a in _articles) {
      for (final u in a.feedUrls) {
        final st = s.putIfAbsent(u, () => SourceStats());
        if (a.status == PaywallStatus.free) st.free++;
        if (a.status == PaywallStatus.paywall) st.paywall++;
        if (a.status == PaywallStatus.unclear) st.unclear++;
      }
    }
    stats = s;
    if (notify) notifyListeners();
  }

  // --- Abruf und Prüfung ---

  Future<void> _pool<T>(
      List<T> items, int workers, Future<void> Function(T) fn) async {
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final item = items[next++];
        try {
          await fn(item);
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));
  }

  Future<void> refresh() async {
    if (refreshing) return;
    refreshing = true;
    lastError = null;
    notifyListeners();
    try {
      final wanted = interests.toSet();
      final jobs = entries
          .where((e) =>
              e.enabled && (e.isCustom || e.categories.any(wanted.contains)))
          .toList();
      var failures = 0;
      await _pool<FeedEntry>(jobs, 4, (e) async {
        if (!await _loadFeed(e)) failures++;
      });
      if (entries.isEmpty) {
        lastError = tr('err_no_sources');
      } else if (jobs.isNotEmpty && failures == jobs.length) {
        lastError = tr('err_offline');
      }
      await db.prune();
      await _reload();
      if (deepCheck) await _runDeepCheck();
    } finally {
      refreshing = false;
      checkTotal = 0;
      checkDone = 0;
      await _reload();
    }
  }

  Future<bool> _loadFeed(FeedEntry e) async {
    final res = await fetchUrl(e.url, maxBytes: 3000000);
    if (res == null || res.status != 200) return false;
    final ParsedFeed parsed;
    try {
      parsed = parseFeed(decodeBody(res.bytes));
    } catch (_) {
      return false;
    }
    final rules = catalog.generic.merge(e.source.rules);
    final now = DateTime.now();
    final list = <Article>[];
    for (final it in parsed.items.take(40)) {
      if (!it.link.startsWith('http') || it.title.isEmpty) continue;
      var status = PaywallStatus.unchecked;
      if (e.source.unfiltered) {
        status = PaywallStatus.free;
      } else if (matchesRules(
          link: it.link, title: it.title, summary: it.summary, rules: rules)) {
        status = PaywallStatus.paywall;
      }
      var published = it.published ?? now;
      if (published.isAfter(now)) published = now;
      list.add(Article(
        link: it.link,
        feedUrls: [e.url],
        sourceId: e.source.id,
        sourceName: e.source.name,
        title: it.title,
        summary: it.summary,
        imageUrl: it.imageUrl,
        content: it.content,
        categories: e.feed.categories,
        published: published,
        status: status,
      ));
    }
    await db.insertNew(list, e.url);
    return true;
  }

  Future<void> _runDeepCheck() async {
    final sourceById = {for (final e in entries) e.source.id: e.source};
    final todo = (await db.unchecked(kDeepCheckBatch * 3))
        .where((a) => _activeEntriesOf(a).isNotEmpty)
        .take(kDeepCheckBatch)
        .toList();
    if (todo.isEmpty) return;
    checkTotal = todo.length;
    checkDone = 0;
    notifyListeners();
    await _pool<Article>(todo, 3, (a) async {
      final patterns = [
        ...catalog.generic.htmlContains,
        ...?sourceById[a.sourceId]?.rules.htmlContains,
      ];
      final result = await checkArticle(a.link, patterns);
      if (result != null) {
        final needsImage = (a.imageUrl ?? '').isEmpty;
        await db.updateCheck(
            a.link, result.status, needsImage ? result.image : null);
      }
      checkDone++;
      if (checkDone % 5 == 0) await _reload();
    });
  }

  // --- Aktionen auf Artikeln ---

  Future<void> markRead(Article a) async {
    if (a.isRead) return;
    await db.setRead(a.link);
    await _reload();
  }

  Future<void> toggleBookmark(Article a) async {
    await db.setBookmarked(a.link, !a.bookmarked);
    await _reload();
  }

  Future<void> reportPaywall(Article a) async {
    await db.reportPaywall(a.link);
    await _reload();
  }

  /// Öffnet ein vorausgefülltes GitHub-Issue zur gemeldeten Paywall.
  Future<void> openIssueFor(Article a) async {
    if (!kIssuesConfigured) return;
    final uri = Uri.https('github.com', '/$kIssueRepo/issues/new', {
      'title': 'Paywall nicht erkannt: ${a.sourceName}',
      'body': 'Quelle: ${a.sourceName} (${a.sourceId})\nLink: ${a.link}\n'
          'Titel: ${a.title}\n',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> openInBrowser(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // --- Einstellungen ändern ---

  void setCategory(String? id) {
    selectedCategory = id;
    notifyListeners();
  }

  void setSearch(String value) {
    search = value;
    notifyListeners();
  }

  Future<void> finishOnboarding(
      String country, String language, List<String> interests) async {
    await _prefs.setString('country', country);
    await _prefs.setString('language', language);
    await _prefs.setStringList('interests', interests);
    await _prefs.setBool('onboarded', true);
    notifyListeners();
    unawaited(refresh());
    unawaited(syncCatalog());
  }

  Future<void> setRegion(String country, String language) async {
    await _prefs.setString('country', country);
    await _prefs.setString('language', language);
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> setInterests(List<String> value) async {
    await _prefs.setStringList('interests', value);
    if (selectedCategory != null && !tabs.contains(selectedCategory)) {
      selectedCategory = null;
    }
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> setViewMode(int mode) async {
    await _prefs.setInt('viewMode', mode);
    notifyListeners();
  }

  Future<void> setDeepCheck(bool value) async {
    await _prefs.setBool('deepCheck', value);
    notifyListeners();
    if (value) unawaited(refresh());
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setInt('themeMode', mode.index);
    notifyListeners();
  }

  Future<void> setUiLanguageChoice(String code) async {
    await _prefs.setString('uiLanguage', code);
    _applyUiLanguage();
    notifyListeners();
  }

  Future<void> addMutedWord(String word) async {
    final w = word.trim();
    if (w.isEmpty || mutedWords.contains(w)) return;
    await _prefs.setStringList('mutedWords', [...mutedWords, w]);
    notifyListeners();
  }

  Future<void> removeMutedWord(String word) async {
    await _prefs.setStringList(
        'mutedWords', mutedWords.where((w) => w != word).toList());
    notifyListeners();
  }

  // --- Feeds anpassen ---

  Future<void> setFeedEnabled(String url, bool enabled) async {
    (_overrides[url] ??= <String, dynamic>{})['enabled'] = enabled;
    await _saveOverrides();
    notifyListeners();
    if (enabled) unawaited(refresh());
  }

  /// Name und Thema eines Katalog-Feeds überschreiben.
  Future<void> setFeedOverride(String url,
      {required String name, required String category}) async {
    final o = _overrides[url] ??= <String, dynamic>{};
    o['name'] = name.trim();
    o['category'] = category;
    await _saveOverrides();
    if (selectedCategory != null && !tabs.contains(selectedCategory)) {
      selectedCategory = null;
    }
    notifyListeners();
    unawaited(refresh());
  }

  /// Name und Thema eines Katalog-Feeds auf die Vorgabe zurücksetzen.
  Future<void> resetFeedOverride(String url) async {
    final o = _overrides[url];
    if (o == null) return;
    o.remove('name');
    o.remove('category');
    if (o.isEmpty) _overrides.remove(url);
    await _saveOverrides();
    notifyListeners();
    unawaited(refresh());
  }

  // --- Eigene Feeds ---

  /// Prüft die Adresse und speichert den Feed. Gibt eine Fehlermeldung
  /// zurück oder `null` bei Erfolg.
  Future<String?> addCustomFeed({
    required String url,
    required String title,
    required String category,
    required bool unfiltered,
  }) async {
    var u = url.trim();
    if (u.isEmpty) return tr('err_empty');
    if (!u.startsWith('http')) u = 'https://$u';
    final res = await fetchUrl(u, maxBytes: 3000000);
    if (res == null || res.status != 200) return tr('err_unreachable');
    final ParsedFeed parsed;
    try {
      parsed = parseFeed(decodeBody(res.bytes));
    } catch (_) {
      return tr('err_no_feed');
    }
    if (parsed.items.isEmpty) return tr('err_no_items');
    var name = title.trim();
    if (name.isEmpty) name = parsed.title;
    if (name.isEmpty) name = Uri.parse(u).host;
    await db.saveCustomFeed(CustomFeed(u, name, category, unfiltered));
    await _loadCustomFeeds();
    notifyListeners();
    unawaited(refresh());
    return null;
  }

  Future<void> updateCustomFeed(CustomFeed old,
      {required String title,
      required String category,
      required bool unfiltered}) async {
    final name = title.trim().isEmpty ? old.title : title.trim();
    await db.saveCustomFeed(CustomFeed(old.url, name, category, unfiltered));
    if (old.unfiltered != unfiltered) {
      // Ungefiltert: alles zeigen. Gefiltert: alles neu prüfen.
      await db.resetStatus(old.sourceId,
          unfiltered ? PaywallStatus.free : PaywallStatus.unchecked);
    }
    await _loadCustomFeeds();
    if (selectedCategory != null && !tabs.contains(selectedCategory)) {
      selectedCategory = null;
    }
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> removeCustomFeed(CustomFeed f) async {
    await db.deleteCustomFeed(f.url);
    await db.deleteBySource(f.sourceId);
    _overrides.remove(f.url);
    await _saveOverrides();
    await _loadCustomFeeds();
    await _reload();
  }

  CustomFeed? customFeedByUrl(String url) {
    for (final f in customFeeds) {
      if (f.url == url) return f;
    }
    return null;
  }

  Future<List<FeedSuggestion>> suggestFeeds(String query) => searchFeeds(
        query,
        catalog: catalog,
        country: country,
        nameOf: (s, f) => _defaultListName(
            s, f.categories.where(kCategoryIds.contains).toList()),
      );

  String exportOpml() {
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<opml version="2.0">')
      ..writeln('<head><title>$kAppName</title></head>')
      ..writeln('<body>');
    for (final f in customFeeds) {
      b.writeln('<outline type="rss" text="${esc(f.title)}" '
          'xmlUrl="${esc(f.url)}"/>');
    }
    b
      ..writeln('</body>')
      ..writeln('</opml>');
    return b.toString();
  }

  /// Liest Feed-Adressen aus OPML-Text oder aus einer Liste mit einer
  /// Adresse pro Zeile. Gibt die Anzahl hinzugefügter Feeds zurück; hört
  /// auf, sobald ohne Pro die Freigrenze erreicht ist.
  Future<int> importFeeds(String text) async {
    final urls = <String>{};
    for (final m in RegExp('xmlUrl=["\']([^"\']+)["\']').allMatches(text)) {
      urls.add(m.group(1)!.replaceAll('&amp;', '&'));
    }
    if (urls.isEmpty) {
      for (final line in text.split('\n')) {
        final l = line.trim();
        if (l.startsWith('http')) urls.add(l);
      }
    }
    final known = customFeeds.map((f) => f.url).toSet();
    var added = 0;
    for (final u in urls) {
      if (known.contains(u)) continue;
      if (!canAddFeed) break;
      final error = await addCustomFeed(
          url: u, title: '', category: 'top', unfiltered: false);
      if (error == null) added++;
    }
    return added;
  }
}
