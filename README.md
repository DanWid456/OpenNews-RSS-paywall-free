# OpenNews 1.0

RSS-News-Reader für Android (Flutter), der Artikel hinter Bezahlschranken
ausblendet. Alles läuft auf dem Gerät, es gibt keinen eigenen Server.

## Einrichten

1. Den Inhalt dieses Ordners ins Repository
   `DanWid456/OpenNews-RSS-paywall-free` (Branch `main`) hochladen.
2. Die Quellenliste wird online aus `assets/feeds.json` dieses Repositorys
   nachgeladen. Die Adresse steht in `lib/config.dart`.
3. Der Workflow `.github/workflows/build.yml` baut bei jedem Push auf `main`
   eine Test-APK (Artefakt `opennews-apk`). In dieser APK ist Pro ohne Kauf
   freigeschaltet (`UNLOCK_PRO`).

## Quellen pflegen: `assets/feeds.json`

```json
{
  "schemaVersion": 1,
  "version": 2,
  "generic": { "urlContains": [], "titlePrefixes": [], "textContains": [], "htmlContains": [] },
  "sources": [
    {
      "id": "beispiel",
      "name": "Beispielblatt",
      "country": "CH",
      "language": "de",
      "paywall": {
        "urlContains": ["/plus/"],
        "titlePrefixes": ["Abo:"],
        "textContains": [],
        "htmlContains": ["class=\"paywall\""]
      },
      "feeds": [
        { "url": "https://example.org/rss/wirtschaft", "categories": ["wirtschaft"] }
      ]
    }
  ]
}
```

- `version` bei jeder Änderung um 1 erhöhen – nur dann übernimmt die App die
  Datei. `schemaVersion` nur ändern, wenn sich der Aufbau ändert.
- `country`: `CH`, `DE`, `AT`, `FR`, `IT`, `ES`, `GB`, `US`, `CA`.
  `language`: `de`, `fr`, `it`, `en`, `es`.
- `categories`: `top`, `inland`, `ausland`, `politik`, `wirtschaft`, `technik`,
  `sport`, `kultur`, `gesundheit`, `alltag`.
- Angezeigt werden alle Quellen in der Nachrichtensprache des Nutzers. Quellen
  des eigenen Landes sind von Haus aus eingeschaltet, die übrigen aus.
- `"paywallFree": true` bei einer Quelle: Ihre Artikel gelten ohne
  Tiefenprüfung als frei. Nur für Quellen ohne Bezahlschranke, deren Seiten
  sich nicht prüfen lassen (z. B. France 24).
- `"optional": true` bei einer Quelle: Sie wird angeboten, ist aber von Haus
  aus ausgeschaltet. Für Quellen mit häufiger Bezahlschranke.
- `generic.videoUrlContains`: zusätzliche Link-Bestandteile, an denen
  Video-Beiträge erkannt werden (Vorgabe in `kVideoUrlPatterns`).
- `urlContains`, `titlePrefixes`, `textContains` wirken in Stufe 1 (aus dem
  Feed), `htmlContains` in Stufe 2 (im HTML der Artikelseite).
- Der Reiter «Quellen» in der App zeigt pro Quelle die Paywall-Quote. Quellen
  mit hoher Quote oder vielen «unklar» lohnen sich nicht.

## Feeds prüfen

`tool/check_feeds.py` ruft jeden Feed aus `assets/feeds.json` ab und schreibt
einen Bericht: erreichbar, Anzahl und Alter der Artikel, Treffer der
Paywall-Regeln, Stichprobe von Artikelseiten und Zahl der Werbe-Marker. Für
fehlerhafte Feeds sucht es auf der Homepage der Quelle nach Feed-Adressen.
Der Workflow «Feeds prüfen» (`.github/workflows/feeds.yml`) startet es bei
jeder Änderung der `feeds.json` oder von Hand unter Actions.

## Wie gefiltert wird

1. **Stufe 1:** Link, Titel und Anriss gegen die Regeln aus `feeds.json`.
2. **Stufe 2:** Artikelseite einmal laden; `isAccessibleForFree`,
   `article:content_tier`, `htmlContains`-Muster. Ohne eindeutiges Signal gilt
   ein Artikel als frei, wenn genug Fliesstext im HTML steht, sonst als
   «unklar» (wird angezeigt und als «ungeprüft» markiert).
3. Das Ergebnis wird in der lokalen Datenbank gespeichert; jeder Artikel wird
   nur einmal geprüft. Pro Aktualisierung werden höchstens 60 Artikel tief
   geprüft (`kDeepCheckBatch`).

**Video-Beiträge** (Schalter in den Einstellungen, standardmässig aus) werden
am Link erkannt (`/video/`, `/vidéo/` …) und in Stufe 2 an `og:type` «video»
oder an einem `VideoObject` mit wenig Fliesstext.

Eigene Feeds werden genauso gefiltert, ausser «Alle Beiträge ungefiltert
anzeigen» ist angekreuzt. Vier eigene Feeds sind kostenlos
(`kFreeCustomFeeds`), für weitere braucht es Pro.

## Sprachen

Die Oberfläche gibt es auf Deutsch, Französisch, Italienisch, Englisch und
Spanisch (`lib/l10n.dart`). Neue Texte dort in allen fünf Sprachen ergänzen.

## Homescreen-Widget

Das Widget zeigt die neuesten frei lesbaren Artikel und lässt sich in der
Grösse verstellen. Es übernimmt den Stand der letzten Aktualisierung in der
App; im Hintergrund lädt es nichts nach. Quelltext und Layouts liegen in
`android_extra/` und werden von `tool/setup_android.sh` ins Android-Projekt
kopiert.

## Updates der Test-APK

`tool/debug.keystore` ist ein fester Test-Schlüssel (Passwort `android`).
Damit haben alle Test-APKs dieselbe Signatur und lassen sich über die
vorherige Version installieren. Der Schlüssel ist öffentlich und nur für
Tests gedacht.

## Play Store

### Im Repository
- `.github/workflows/release.yml` baut das signierte App-Bundle (`.aab`).
  Start von Hand unter Actions → «Release bauen (Play Store)». Es bricht ab,
  wenn das Bundle mit dem Test-Schlüssel signiert wäre.
- `tool/setup_android.sh` setzt Ziel- und Kompilier-API auf mindestens 36.
- App-Symbol: `android_extra/app/src/main/res/mipmap-*` (adaptiv, mit
  einfarbiger Variante für Android 13+).
- Store-Grafiken: `store/icon_512.png`, `store/feature_graphic_1024x500.png`.
- Store-Texte in fünf Sprachen: `store/STORE_LISTING.md` und
  `fastlane/metadata/android/<Sprache>/`.
- Datenschutzerklärung: `PRIVACY.md` (Link in der App unter Einstellungen →
  Über die App).

### Upload-Schlüssel einrichten (einmalig)
1. In Android Studio: Build → Generate Signed App Bundle or APK → Android App
   Bundle → «Create new…». Schlüsseldatei (`upload.jks`), Passwörter und Alias
   festlegen. **Datei und Passwörter sicher aufbewahren** – ohne sie gibt es
   keine Updates mehr.
2. Datei in Base64 umwandeln, unter Windows in PowerShell:
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload.jks")) | Set-Clipboard`
3. Im Repository unter Settings → Secrets and variables → Actions vier
   Secrets anlegen: `UPLOAD_KEYSTORE_BASE64` (der kopierte Text),
   `UPLOAD_STORE_PASSWORD`, `UPLOAD_KEY_ALIAS`, `UPLOAD_KEY_PASSWORD`.

### In der Play Console
- App anlegen, App-ID `ch.dawisoft.opennews` (nach der ersten
  Veröffentlichung nicht mehr änderbar). Play App Signing aktiv lassen.
- Einmalkauf `pro_upgrade` anlegen und aktivieren, Preis dort festlegen.
- Datenschutz-URL:
  `https://github.com/DanWid456/OpenNews-RSS-paywall-free/blob/main/PRIVACY.md`
- Datensicherheit: Die App erhebt und teilt keine Daten.
- Erklärung «News-App»: Herausgeber und Kontakt angeben; jede Meldung nennt
  ihre Quelle.
- Inhaltseinstufung (Fragebogen), Zielgruppe (nicht für Kinder), Werbung: keine.
- Screenshots vom Handy (mind. 2, besser 4–8).
- Neue private Entwicklerkonten: geschlossener Test mit mindestens 12
  Testern über 14 Tage, bevor die Produktion freigegeben wird.
- Versionsnummer: `version` in `pubspec.yaml`; die Zahl nach `+` muss bei
  jedem Upload steigen.
