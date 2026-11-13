import 'dart:ui';

import 'package:flutter_timezone/flutter_timezone.dart';

import '../config.dart';

class RegionInfo {
  final String country;
  final String language;
  const RegionInfo(this.country, this.language);
}

const _tzCountry = {
  'Europe/Zurich': 'CH',
  'Europe/Berlin': 'DE',
  'Europe/Busingen': 'DE',
  'Europe/Vienna': 'AT',
  'Europe/Paris': 'FR',
  'Europe/Rome': 'IT',
  'Europe/Madrid': 'ES',
  'Europe/London': 'GB',
  'America/Toronto': 'CA',
  'America/Montreal': 'CA',
  'America/Vancouver': 'CA',
  'America/New_York': 'US',
  'America/Chicago': 'US',
  'America/Denver': 'US',
  'America/Los_Angeles': 'US',
};

/// Ermittelt Land und Sprache ohne Standortberechtigung: Die Zeitzone zeigt,
/// wo das Gerät zuhause ist (auch bei aktivem VPN), das Gebietsschema liefert
/// die Sprache und dient als Ersatz, wenn die Zeitzone nicht weiterhilft.
Future<RegionInfo> detectRegion() async {
  final locale = PlatformDispatcher.instance.locale;
  var language = locale.languageCode.toLowerCase();
  if (!kLanguages.containsKey(language)) language = 'de';

  String timezone = '';
  try {
    // Je nach Paketversion kommt ein String oder ein Objekt mit `identifier`.
    final dynamic tz = await FlutterTimezone.getLocalTimezone();
    timezone = tz is String ? tz : (tz.identifier as String);
  } catch (_) {}

  final localeCountry = locale.countryCode?.toUpperCase();
  var country = _tzCountry[timezone] ?? localeCountry ?? 'CH';
  if (!kCountries.containsKey(country)) country = 'CH';
  return RegionInfo(country, language);
}
