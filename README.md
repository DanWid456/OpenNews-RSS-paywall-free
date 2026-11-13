# OpenNews

RSS-News-Reader für Android (Flutter), der Artikel hinter Bezahlschranken
ausblendet. Alles läuft auf dem Gerät, es gibt keinen eigenen Server.

## Einrichten

1. Den Inhalt dieses Ordners ins Repository
   `DanWid456/OpenNews-RSS-paywall-free` (Branch `main`) hochladen.
2. Die Quellenliste wird online aus `assets/feeds.json` dieses Repositorys
   nachgeladen; «Weitermelden» öffnet dort ein Issue. Beides steht in
   `lib/config.dart`.
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
- `country`: `CH`, `DE`, `AT`. `language`: `de`, `fr`, `it`, `en`.
- `categories`: `top`, `inland`, `ausland`, `politik`, `wirtschaft`, `technik`,
  `sport`, `kultur`, `gesundheit`, `alltag`.
- Angezeigt werden alle Quellen in der Nachrichtensprache des Nutzers. Quellen
  des eigenen Landes sind von Haus aus eingeschaltet, die übrigen aus.
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

Eigene Feeds werden genauso gefiltert, ausser «Alle Beiträge ungefiltert
anzeigen» ist angekreuzt. Vier eigene Feeds sind kostenlos
(`kFreeCustomFeeds`), für weitere braucht es Pro.

## Sprachen

Die Oberfläche gibt es auf Deutsch, Französisch, Italienisch und Englisch
(`lib/l10n.dart`). Neue Texte dort in allen vier Sprachen ergänzen.

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

- In der Play Console ein Einmalkauf-Produkt mit der ID `pro_upgrade` anlegen.
- `android/`-Ordner einmal erzeugen (`flutter create --platforms=android --org ch.dawisoft --project-name opennews .`),
  einchecken und die Signatur festlegen. Die App-ID ist `ch.dawisoft.opennews`
  und lässt sich nach der ersten Veröffentlichung nicht mehr ändern.
- Googles Anforderungen für News-Apps beachten (Angaben zum Herausgeber,
  Quellenangabe pro Artikel).
