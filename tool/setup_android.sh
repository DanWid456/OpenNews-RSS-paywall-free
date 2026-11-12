#!/usr/bin/env bash
# Erzeugt das Android-Projekt und ergänzt alles, was "flutter create" nicht
# mitbringt: Internet-Berechtigung, App-Name, Lint-Abschaltung und das
# Homescreen-Widget (Dateien aus android_extra/).
# Wird vom GitHub-Workflow aufgerufen, solange kein android/-Ordner im
# Repository liegt.
set -euo pipefail

# Fester Test-Schlüssel: Ohne ihn erzeugt jeder Build einen neuen Schlüssel,
# und Android lehnt die neue APK als Update der alten ab. Nur für Test-APKs;
# der Play-Store-Release bekommt einen eigenen, geheimen Schlüssel.
mkdir -p "$HOME/.android"
cp tool/debug.keystore "$HOME/.android/debug.keystore"

flutter create --platforms=android --org ch.dawisoft --project-name opennews .
rm -rf test

MANIFEST=android/app/src/main/AndroidManifest.xml

# Internet-Zugriff (fehlt im Release-Manifest) und Anzeigename.
sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$MANIFEST"
sed -i 's#android:label="opennews"#android:label="OpenNews"#' "$MANIFEST"

# Homescreen-Widget: Quelltext und Ressourcen kopieren, im Manifest anmelden.
cp -r android_extra/. android/
sed -i 's#</application>#    <receiver android:name=".NewsWidgetProvider" android:exported="true" android:label="OpenNews">\n            <intent-filter>\n                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>\n            </intent-filter>\n            <meta-data android:name="android.appwidget.provider" android:resource="@xml/news_widget_info"/>\n        </receiver>\n        <service android:name=".NewsWidgetService" android:permission="android.permission.BIND_REMOTEVIEWS" android:exported="false"/>\n    </application>#' "$MANIFEST"

# Der Release-Lint stürzt im Kauf-Plugin ab; für alle Module abschalten.
for f in android/build.gradle.kts android/build.gradle; do
  if [ -f "$f" ]; then
    printf '\nsubprojects {\n    tasks.matching { it.name.startsWith("lintVital") }.configureEach { enabled = false }\n}\n' >> "$f"
  fi
done

echo "--- AndroidManifest.xml ---"
cat "$MANIFEST"
