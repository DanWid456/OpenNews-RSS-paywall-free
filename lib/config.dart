/// Zentrale Einstellungen. Die Quellenliste wird aus dem GitHub-Repository
/// nachgeladen; Paywall-Meldungen öffnen dort ein Issue.
const String kRemoteFeedsUrl =
    'https://raw.githubusercontent.com/DanWid456/OpenNews-RSS-paywall-free/main/assets/feeds.json';
const String kIssueRepo = 'DanWid456/OpenNews-RSS-paywall-free';

bool get kRemoteConfigured => !kRemoteFeedsUrl.contains('OWNER/REPO');
bool get kIssuesConfigured => !kIssueRepo.contains('OWNER/REPO');

/// Höchste Schema-Version der feeds.json, die diese App-Version versteht.
const int kSupportedSchema = 1;

/// Produkt-ID des Einmalkaufs in der Play Console.
const String kProProductId = 'pro_upgrade';

/// Test-Builds: `--dart-define=UNLOCK_PRO=true` schaltet Pro ohne Kauf frei.
const bool kUnlockPro = bool.fromEnvironment('UNLOCK_PRO');

const String kUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36';

/// Themen-IDs (wie in feeds.json). Die Anzeigenamen stehen in l10n.dart
/// unter `cat_<id>`.
const List<String> kCategoryIds = [
  'top',
  'inland',
  'ausland',
  'politik',
  'wirtschaft',
  'technik',
  'sport',
  'kultur',
  'gesundheit',
  'alltag',
];

/// So viele eigene Feeds sind ohne Pro möglich.
const int kFreeCustomFeeds = 4;

const String kAppName = 'OpenNews';

const Map<String, String> kCountries = {
  'CH': 'Schweiz',
  'DE': 'Deutschland',
  'AT': 'Österreich',
};

const Map<String, String> kLanguages = {
  'de': 'Deutsch',
  'fr': 'Français',
  'it': 'Italiano',
  'en': 'English',
};

/// Wie viele Artikel pro Aktualisierung höchstens tief geprüft werden.
const int kDeepCheckBatch = 60;

/// Mindestlänge an Fliesstext, damit ein Artikel als frei lesbar gilt.
const int kMinFreeTextLength = 500;
