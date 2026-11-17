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

# Play-Store-Release: Signatur mit dem eigenen Upload-Schlüssel, wenn die
# Umgebungsvariable UPLOAD_KEYSTORE gesetzt ist (Workflow «Release bauen»).
# Ohne sie bleibt es beim Test-Schlüssel. Ausserdem mindestens API 36, wie
# Google Play es seit August 2026 verlangt.
python3 - <<'PY'
import os, re, sys

KTS_SIGN = """// OPENNEWS_UPLOAD_SIGNING
            signingConfig = if (System.getenv("UPLOAD_KEYSTORE") != null) {
                signingConfigs.create("upload") {
                    storeFile = file(System.getenv("UPLOAD_KEYSTORE"))
                    storePassword = System.getenv("UPLOAD_STORE_PASSWORD")
                    keyAlias = System.getenv("UPLOAD_KEY_ALIAS")
                    keyPassword = System.getenv("UPLOAD_KEY_PASSWORD")
                }
            } else {
                signingConfigs.getByName("debug")
            }"""
GROOVY_SIGN = """// OPENNEWS_UPLOAD_SIGNING
            signingConfig System.getenv("UPLOAD_KEYSTORE") ? signingConfigs.create("upload") {
                storeFile file(System.getenv("UPLOAD_KEYSTORE"))
                storePassword System.getenv("UPLOAD_STORE_PASSWORD")
                keyAlias System.getenv("UPLOAD_KEY_ALIAS")
                keyPassword System.getenv("UPLOAD_KEY_PASSWORD")
            } : signingConfigs.debug"""

for path in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    if not os.path.exists(path):
        continue
    src = open(path).read()
    kts = path.endswith(".kts")
    sign = re.compile(r'signingConfig\s*=\s*signingConfigs\.(getByName\("debug"\)|debug)')
    if sign.search(src):
        src = sign.sub(lambda m: KTS_SIGN if kts else GROOVY_SIGN, src, count=1)
    else:
        print("WARNUNG: Signatur-Stelle in %s nicht gefunden" % path, file=sys.stderr)
    for key in ("compileSdk", "targetSdk"):
        pat = re.compile(r'(%s\s*=?\s*)flutter\.%sVersion' % (key, key))
        if kts:
            src = pat.sub(lambda m: "%smaxOf(flutter.%sVersion, 36)" % (m.group(1), key), src)
        else:
            src = pat.sub(lambda m: "%sMath.max(flutter.%sVersion, 36)" % (m.group(1), key), src)
    open(path, "w").write(src)
    print("--- %s ---" % path)
    print(src)
PY

echo "--- AndroidManifest.xml ---"
cat "$MANIFEST"
