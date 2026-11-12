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

/// Themen: ID (wie in feeds.json) -> Anzeigename.
const Map<String, String> kCategories = {
  'top': 'Schlagzeilen',
  'politik': 'Politik',
  'international': 'Ausland',
  'wirtschaft': 'Wirtschaft',
  'technologie': 'Technologie',
  'wissenschaft': 'Wissenschaft',
  'sport': 'Sport',
  'kultur': 'Kultur',
};

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
