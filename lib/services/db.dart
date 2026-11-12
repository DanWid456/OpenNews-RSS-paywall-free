import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';

class AppDb {
  late Database _db;

  Future<void> open() async {
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'news_reader.db'),
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Version 2 merkt sich, aus welchen Feeds ein Artikel stammt. Der
          // alte Cache hat diese Angabe nicht und wird neu aufgebaut.
          await db.execute('ALTER TABLE articles ADD COLUMN feedUrl TEXT');
          await db.delete('articles', where: 'bookmarked = 0');
        }
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE articles(
            link TEXT PRIMARY KEY,
            feedUrl TEXT,
            sourceId TEXT,
            sourceName TEXT,
            title TEXT,
            summary TEXT,
            imageUrl TEXT,
            content TEXT,
            categories TEXT,
            published INTEGER,
            status INTEGER,
            isRead INTEGER DEFAULT 0,
            bookmarked INTEGER DEFAULT 0,
            reported INTEGER DEFAULT 0
          )''');
        await db.execute(
            'CREATE INDEX idx_articles_published ON articles(published)');
        await db.execute('''
          CREATE TABLE custom_feeds(
            url TEXT PRIMARY KEY,
            title TEXT,
            category TEXT,
            unfiltered INTEGER
          )''');
        await db.execute('CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT)');
      },
    );
  }

  // --- Schlüssel/Wert (für die heruntergeladene feeds.json) ---

  Future<String?> kvGet(String key) async {
    final r =
        await _db.query('kv', where: 'k = ?', whereArgs: [key], limit: 1);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  Future<void> kvSet(String key, String value) async {
    await _db.insert('kv', {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- Artikel ---

  /// Fügt nur neue Artikel ein; bereits bekannte (und ihr Prüfstatus)
  /// bleiben unverändert.
  ///
  /// Kam ein bekannter Artikel bisher nur aus anderen Feeds, wird [feedUrl]
  /// bei ihm ergänzt. So erscheint er unter allen seinen Themen.
  Future<void> insertNew(List<Article> articles, String feedUrl) async {
    if (articles.isEmpty) return;
    final batch = _db.batch();
    for (final a in articles) {
      batch.insert('articles', a.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
      batch.rawUpdate(
          'UPDATE articles SET feedUrl = COALESCE(feedUrl, char(10)) || ? '
          "WHERE link = ? AND instr(COALESCE(feedUrl, ''), ?) = 0",
          ['$feedUrl\n', a.link, '\n$feedUrl\n']);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Article>> recent({int days = 7, int limit = 1000}) async {
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final rows = await _db.query('articles',
        where: 'published > ?',
        whereArgs: [cutoff],
        orderBy: 'published DESC',
        limit: limit);
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> unchecked(int limit) async {
    final rows = await _db.query('articles',
        where: 'status = ?',
        whereArgs: [PaywallStatus.unchecked.index],
        orderBy: 'published DESC',
        limit: limit);
    return rows.map(Article.fromMap).toList();
  }

  Future<List<Article>> bookmarks() async {
    final rows = await _db.query('articles',
        where: 'bookmarked = 1', orderBy: 'published DESC');
    return rows.map(Article.fromMap).toList();
  }

  Future<void> updateCheck(
      String link, PaywallStatus status, String? image) async {
    final values = <String, Object?>{'status': status.index};
    if (image != null) values['imageUrl'] = image;
    await _db.update('articles', values, where: 'link = ?', whereArgs: [link]);
  }

  Future<void> setRead(String link) async {
    await _db.update('articles', {'isRead': 1},
        where: 'link = ?', whereArgs: [link]);
  }

  Future<void> setBookmarked(String link, bool value) async {
    await _db.update('articles', {'bookmarked': value ? 1 : 0},
        where: 'link = ?', whereArgs: [link]);
  }

  Future<void> reportPaywall(String link) async {
    await _db.update(
        'articles', {'status': PaywallStatus.paywall.index, 'reported': 1},
        where: 'link = ?', whereArgs: [link]);
  }

  Future<int> hiddenCount({int hours = 24}) async {
    final cutoff =
        DateTime.now().subtract(Duration(hours: hours)).millisecondsSinceEpoch;
    final r = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM articles WHERE status = ? AND published > ?',
        [PaywallStatus.paywall.index, cutoff]);
    return (r.first['c'] as int?) ?? 0;
  }

  /// Entfernt Artikel, die älter als [days] Tage und nicht gemerkt sind.
  Future<void> prune({int days = 30}) async {
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    await _db.delete('articles',
        where: 'published < ? AND bookmarked = 0', whereArgs: [cutoff]);
  }

  Future<void> deleteBySource(String sourceId) async {
    await _db.delete('articles',
        where: 'sourceId = ? AND bookmarked = 0', whereArgs: [sourceId]);
  }

  /// Setzt den Prüfstatus einer Quelle zurück (z. B. wenn "ungefiltert"
  /// umgeschaltet wurde).
  Future<void> resetStatus(String sourceId, PaywallStatus status) async {
    await _db.update('articles', {'status': status.index},
        where: 'sourceId = ? AND reported = 0', whereArgs: [sourceId]);
  }

  // --- Eigene Feeds ---

  Future<List<CustomFeed>> customFeeds() async {
    final rows = await _db.query('custom_feeds', orderBy: 'title');
    return rows
        .map((r) => CustomFeed(
              r['url'] as String,
              (r['title'] as String?) ?? '',
              (r['category'] as String?) ?? 'top',
              ((r['unfiltered'] as int?) ?? 0) == 1,
            ))
        .toList();
  }

  Future<void> saveCustomFeed(CustomFeed f) async {
    await _db.insert(
        'custom_feeds',
        {
          'url': f.url,
          'title': f.title,
          'category': f.category,
          'unfiltered': f.unfiltered ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCustomFeed(String url) async {
    await _db.delete('custom_feeds', where: 'url = ?', whereArgs: [url]);
  }
}
