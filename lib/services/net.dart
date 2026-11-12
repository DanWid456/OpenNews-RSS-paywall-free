import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class FetchResult {
  final int status;
  final List<int> bytes;
  const FetchResult(this.status, this.bytes);
}

/// Lädt eine URL und bricht nach [maxBytes] ab. Gibt bei Netzwerkfehlern
/// `null` zurück.
Future<FetchResult?> fetchUrl(
  String url, {
  int maxBytes = 700000,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url));
    req.headers['User-Agent'] = kUserAgent;
    req.headers['Accept'] =
        'text/html,application/xhtml+xml,application/xml,application/rss+xml,*/*';
    req.headers['Accept-Language'] = 'de-CH,de;q=0.9,en;q=0.6';
    final resp = await client.send(req).timeout(timeout);
    final bytes = <int>[];
    await for (final chunk in resp.stream.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length >= maxBytes) break;
    }
    return FetchResult(resp.statusCode, bytes);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// Dekodiert als UTF-8, ausser der Anfang deklariert Latin-1/Windows-1252.
String decodeBody(List<int> bytes) {
  final headLen = bytes.length < 400 ? bytes.length : 400;
  final head = latin1.decode(bytes.sublist(0, headLen)).toLowerCase();
  if (head.contains('iso-8859-1') || head.contains('windows-1252')) {
    return latin1.decode(bytes);
  }
  return utf8.decode(bytes, allowMalformed: true);
}
