import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html;

import '../config.dart';
import '../models.dart';
import 'net.dart';

/// Stufe 1: schneller Abgleich von Link, Titel und Anriss mit den Regeln.
bool matchesRules({
  required String link,
  required String title,
  required String summary,
  required PaywallRules rules,
}) {
  final l = link.toLowerCase();
  for (final p in rules.urlContains) {
    if (p.isNotEmpty && l.contains(p.toLowerCase())) return true;
  }
  final t = title.trimLeft().toLowerCase();
  for (final p in rules.titlePrefixes) {
    if (p.isNotEmpty && t.startsWith(p.toLowerCase())) return true;
  }
  final text = '$t ${summary.toLowerCase()}';
  for (final p in rules.textContains) {
    if (p.isNotEmpty && text.contains(p.toLowerCase())) return true;
  }
  return false;
}

class DeepCheckResult {
  final PaywallStatus status;
  final String? image;
  const DeepCheckResult(this.status, this.image);
}

final _accessRe = RegExp(
    r'"isaccessibleforfree"\s*:\s*"?(false|true)',
    caseSensitive: false);
final _tierRe = RegExp(
    'article:content_tier["\'][^>]*content=["\'](\\w+)',
    caseSensitive: false);

/// Läuft in einem eigenen Isolate (siehe [checkArticle]).
Map<String, Object?> analyzeHtml(Map<String, Object?> input) {
  final body = input['body'] as String;
  final patterns = (input['patterns'] as List).cast<String>();
  final minText = input['minText'] as int;
  final lower = body.toLowerCase();

  bool? verdictFree;
  bool unclear = false;

  for (final p in patterns) {
    if (p.isNotEmpty && lower.contains(p.toLowerCase())) {
      verdictFree = false;
      break;
    }
  }

  if (verdictFree == null) {
    final flags =
        _accessRe.allMatches(body).map((m) => m.group(1)!.toLowerCase());
    if (flags.contains('false')) {
      verdictFree = false;
    } else if (flags.contains('true')) {
      verdictFree = true;
    }
  }

  if (verdictFree == null) {
    final tier = _tierRe.firstMatch(body)?.group(1)?.toLowerCase();
    if (tier == 'locked') {
      verdictFree = false;
    } else if (tier == 'free') {
      verdictFree = true;
    } else if (tier == 'metered') {
      unclear = true;
    }
  }

  final doc = html.parse(body);
  final image =
      doc.querySelector('meta[property="og:image"]')?.attributes['content'];

  if (verdictFree == null && !unclear) {
    // Kein eindeutiges Signal: Ist überhaupt lesbarer Fliesstext da?
    // Zu wenig Text heisst Zustimmungsseite, Zählschranke oder Inhalte,
    // die erst per JavaScript nachgeladen werden.
    var paragraphs = doc.querySelectorAll('article p');
    if (paragraphs.isEmpty) paragraphs = doc.querySelectorAll('p');
    var length = 0;
    for (final p in paragraphs) {
      length += p.text.trim().length;
      if (length >= minText) break;
    }
    if (length >= minText) {
      verdictFree = true;
    } else {
      unclear = true;
    }
  }

  final PaywallStatus status;
  if (verdictFree == true) {
    status = PaywallStatus.free;
  } else if (verdictFree == false) {
    status = PaywallStatus.paywall;
  } else {
    status = PaywallStatus.unclear;
  }
  return {'status': status.index, 'image': image};
}

/// Stufe 2: lädt die Artikelseite und sucht nach Paywall-Signalen.
/// Gibt `null` zurück, wenn die Seite nicht erreichbar war (später erneut
/// versuchen).
Future<DeepCheckResult?> checkArticle(
    String url, List<String> htmlPatterns) async {
  final res = await fetchUrl(url);
  if (res == null) return null;
  if (res.status == 402) {
    return const DeepCheckResult(PaywallStatus.paywall, null);
  }
  if (res.status != 200 || res.bytes.isEmpty) {
    return const DeepCheckResult(PaywallStatus.unclear, null);
  }
  final out = await compute(analyzeHtml, <String, Object?>{
    'body': decodeBody(res.bytes),
    'patterns': htmlPatterns,
    'minText': kMinFreeTextLength,
  });
  final image = out['image'] as String?;
  return DeepCheckResult(
    PaywallStatus.values[out['status'] as int],
    (image != null && image.startsWith('http')) ? image : null,
  );
}
