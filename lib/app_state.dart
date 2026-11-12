import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'models.dart';
import 'services/db.dart';
import 'services/net.dart';
import 'services/paywall.dart';
import 'services/purchases.dart';
import 'services/region.dart';
import 'services/rss_parser.dart';

class _FeedJob {
  final NewsSource source;
  final FeedDef feed;
  const _FeedJob(this.source, this.feed);
}

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

  bool refreshing = false;
  int checkTotal = 0;
  int checkDone = 0;
  String? lastError;

  /// Aktuell gewähltes Thema im Feed (`null` = alle).
  String? selectedCategory;
  String search = '';

  // --- Einstellungen ---

  bool get onboarded => _prefs.getBool('onboarded') ?? false;
  String get country => _prefs.getString('country') ?? 'CH';
  String get language => _prefs.getString('language') ?? 'de';
  List<String> get interests =>
      _prefs.getStringList('interests') ?? const ['top'];
  int get viewMode => _prefs.getInt('viewMode') ?? 1;
  bool get deepCheck => _prefs.getBool('deepCheck') ?? true;
  List<String> get mutedWords => _prefs.getStringList('mutedWords') ?? const [];
  List<String> get disabledSources =>
      _prefs.getStringList('disabledSources') ?? const [];
  ThemeMode get themeMode =>
      ThemeMode.values[(_prefs.getInt('themeMode') ?? 0).clamp(0, 2).toInt()];

  bool get isPro => pro.isPro;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await db.open();
    await _loadCatalog();
    customFeeds = await db.customFeeds();
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
  }

  /// Holt eine neuere feeds.json von GitHub. Gibt eine Statusmeldung zurück.
  Future<String> syncCatalog() async {
    if (!kRemoteConfigured) return 'Online-Update ist noch nicht eingerichtet.';
    final res = await fetchUrl(kRemoteFeedsUrl, maxBytes: 2000000);
    if (res == null || res.status != 200) {
      return 'Quellenliste nicht erreichbar.';
    }
    try {
      final text = decodeBody(res.bytes);
      final remote = FeedCatalog.parse(text);
      if (remote.schemaVersion > kSupportedSchema) {
        return 'Neue Quellenliste braucht ein App-Update.';
      }
      if (remote.version <= catalog.version) {
        return 'Quellenliste ist aktuell (Version ${catalog.version}).';
      }
      await db.kvSet('feeds_json', text);
      catalog = remote;
      notifyListeners();
      unawaited(refresh());
      return 'Quellenliste aktualisiert (Version ${remote.version}).';
    } catch (_) {
      return 'Heruntergeladene Quellenliste ist ungültig.';
    }
  }

  /// Quellen aus dem Katalog, die zu Land und Sprache passen.
  List<NewsSource> get regionSources {
    var s = catalog.sources
        .where((x) => x.country == country && x.language == language)
        .toList();
    if (s.isEmpty) {
      s = catalog.sources.where((x) => x.language == language).toList();
    }
    if (s.isEmpty) {
      s = catalog.sources.where((x) => x.country == country).toList();
    }
    return s;
  }

  List<NewsSource> get customSources =>
      isPro ? customFeeds.map((f) => f.toSource()).toList() : const [];

  List<NewsSource> get activeSources {
    final off = disabledSources.toSet();
    return [
      ...regionSources.where((s) => !off.contains(s.id)),
      ...customSources.where((s) => !off.contains(s.id)),
    ];
  }

  // --- Artikel-Listen ---

  /// Themen-Reiter im Feed: gewählte Interessen plus Themen eigener Feeds.
  List<String> get tabs {
    final out = <String>[...interests];
    for (final f in customFeeds) {
      if (isPro && !out.contains(f.category)) out.add(f.category);
    }
    return kCategories.keys.where(out.contains).toList();
  }

  static final _nonWord = RegExp(r'[^a-z0-9äöüàéèç]+');

  List<Article> get feed {
    final activeIds = activeSources.map((s) => s.id).toSet();
    final wanted = interests.toSet();
    final muted = mutedWords.map((w) => w.toLowerCase()).toList();
    final query = search.trim().toLowerCase();
    final seen = <String>{};
    final out = <Article>[];
    for (final a in _articles) {
      if (!activeIds.contains(a.sourceId)) continue;
      final visible = a.status == PaywallStatus.free ||
          a.status == PaywallStatus.unclear ||
          (a.status == PaywallStatus.unchecked && !deepCheck);
      if (!visible) continue;
      final isCustom = a.sourceId.startsWith('custom:');
      if (!isCustom && !a.categories.any(wanted.contains)) continue;
      if (selectedCategory != null &&
          !a.categories.contains(selectedCategory)) {
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

  Future<void> _reload({bool notify = true}) async {
    _articles = await db.recent();
    bookmarks = await db.bookmarks();
    stats = await db.stats();
    hiddenCount = await db.hiddenCount();
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
      final jobs = <_FeedJob>[];
      for (final s in activeSources) {
        for (final f in s.feeds) {
          if (s.isCustom || f.categories.any(wanted.contains)) {
            jobs.add(_FeedJob(s, f));
          }
        }
      }
      var failures = 0;
      await _pool<_FeedJob>(jobs, 4, (j) async {
        if (!await _loadFeed(j)) failures++;
      });
      if (jobs.isEmpty) {
        lastError = 'Für diese Region und Sprache sind noch keine Quellen '
            'hinterlegt.';
      } else if (failures == jobs.length) {
        lastError = 'Keine Quelle erreichbar. Bitte Verbindung prüfen.';
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

  Future<bool> _loadFeed(_FeedJob j) async {
    final res = await fetchUrl(j.feed.url, maxBytes: 3000000);
    if (res == null || res.status != 200) return false;
    final ParsedFeed parsed;
    try {
      parsed = parseFeed(decodeBody(res.bytes));
    } catch (_) {
      return false;
    }
    final rules = catalog.generic.merge(j.source.rules);
    final now = DateTime.now();
    final list = <Article>[];
    for (final it in parsed.items.take(40)) {
      if (!it.link.startsWith('http') || it.title.isEmpty) continue;
      var status = PaywallStatus.unchecked;
      if (j.source.unfiltered) {
        status = PaywallStatus.free;
      } else if (matchesRules(
          link: it.link, title: it.title, summary: it.summary, rules: rules)) {
        status = PaywallStatus.paywall;
      }
      var published = it.published ?? now;
      if (published.isAfter(now)) published = now;
      list.add(Article(
        link: it.link,
        sourceId: j.source.id,
        sourceName: j.source.name,
        title: it.title,
        summary: it.summary,
        imageUrl: it.imageUrl,
        content: it.content,
        categories: j.feed.categories,
        published: published,
        status: status,
      ));
    }
    await db.insertNew(list);
    return true;
  }

  Future<void> _runDeepCheck() async {
    final byId = {for (final s in activeSources) s.id: s};
    final todo = (await db.unchecked(kDeepCheckBatch * 3))
        .where((a) => byId.containsKey(a.sourceId))
        .take(kDeepCheckBatch)
        .toList();
    if (todo.isEmpty) return;
    checkTotal = todo.length;
    checkDone = 0;
    notifyListeners();
    await _pool<Article>(todo, 3, (a) async {
      final patterns = [
        ...catalog.generic.htmlContains,
        ...byId[a.sourceId]!.rules.htmlContains,
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

  Future<void> setSourceEnabled(String id, bool enabled) async {
    final off = disabledSources.toSet();
    if (enabled) {
      off.remove(id);
    } else {
      off.add(id);
    }
    await _prefs.setStringList('disabledSources', off.toList());
    notifyListeners();
    if (enabled) unawaited(refresh());
  }

  // --- Eigene Feeds (Pro) ---

  /// Prüft die Adresse und speichert den Feed. Gibt eine Fehlermeldung
  /// zurück oder `null` bei Erfolg.
  Future<String?> addCustomFeed({
    required String url,
    required String title,
    required String category,
    required bool unfiltered,
  }) async {
    var u = url.trim();
    if (u.isEmpty) return 'Bitte eine Adresse eingeben.';
    if (!u.startsWith('http')) u = 'https://$u';
    final res = await fetchUrl(u, maxBytes: 3000000);
    if (res == null || res.status != 200) {
      return 'Die Adresse ist nicht erreichbar.';
    }
    final ParsedFeed parsed;
    try {
      parsed = parseFeed(decodeBody(res.bytes));
    } catch (_) {
      return 'Unter dieser Adresse liegt kein RSS- oder Atom-Feed.';
    }
    if (parsed.items.isEmpty) return 'Der Feed enthält keine Beiträge.';
    var name = title.trim();
    if (name.isEmpty) name = parsed.title;
    if (name.isEmpty) name = Uri.parse(u).host;
    await db.saveCustomFeed(CustomFeed(u, name, category, unfiltered));
    customFeeds = await db.customFeeds();
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
    if (old.category != category) await db.deleteBySource(old.sourceId);
    customFeeds = await db.customFeeds();
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> removeCustomFeed(CustomFeed f) async {
    await db.deleteCustomFeed(f.url);
    await db.deleteBySource(f.sourceId);
    customFeeds = await db.customFeeds();
    await _reload();
  }

  String exportOpml() {
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<opml version="2.0">')
      ..writeln('<head><title>Eigene Feeds</title></head>')
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
  /// Adresse pro Zeile. Gibt die Anzahl hinzugefügter Feeds zurück.
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
      final error = await addCustomFeed(
          url: u, title: '', category: 'top', unfiltered: false);
      if (error == null) added++;
    }
    return added;
  }
}
