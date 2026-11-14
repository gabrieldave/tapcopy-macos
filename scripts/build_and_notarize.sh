#!/bin/bash
# TapCopy — release pipeline: icon, build, sign (YH6W55MP95), DMG, double
# notarization stapling (app + dmg), verification and local installation.
# All paths are derived from the repository location: dual-Mac safe.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

APP_NAME="TapCopy"
BUNDLE_ID="com.blackeye.tapcopy"
TEAM_ID="YH6W55MP95"
SIGN_ID="Developer ID Application: David DEL RIO COLIN (${TEAM_ID})"
KEYCHAIN_PROFILE="ordena-notary"
DIST="$REPO/dist"
APP="$DIST/$APP_NAME.app"
INSTALL_DIR="/Applications"

log() { printf '\033[1;36m▶ %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31m✖ %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- version ---
if [ ! -f "$REPO/version.txt" ]; then
    printf '1.0.0\n1\n' > "$REPO/version.txt"
fi

VERSION="$(sed -n '1p' "$REPO/version.txt" | tr -d '[:space:]')"
BUILD="$(sed -n '2p' "$REPO/version.txt" | tr -d '[:space:]')"

BUMP=0
for arg in "$@"; do
    [ "$arg" = "--bump" ] && BUMP=1
done

if [ "$BUMP" = "1" ]; then
    VERSION="$(echo "$VERSION" | awk -F. '{printf "%s.%s.%d", $1, $2, $3 + 1}')"
    BUILD=$((BUILD + 1))
    printf '%s\n%s\n' "$VERSION" "$BUILD" > "$REPO/version.txt"
fi

log "TapCopy ${VERSION} (build ${BUILD}) — repo: $REPO"

mkdir -p "$DIST"

# ------------------------------------------------------------------- icon ---
log "Generando AppIcon.icns"
rm -rf "$DIST/AppIcon.iconset"
swift "$REPO/scripts/GenerateIcon.swift" "$DIST/AppIcon.iconset"
iconutil -c icns "$DIST/AppIcon.iconset" -o "$DIST/AppIcon.icns"

# ------------------------------------------------------------------ build ---
log "Compilando (release)"
swift build -c release

BINARY="$REPO/.build/release/$APP_NAME"
[ -f "$BINARY" ] || fail "Binario no encontrado: $BINARY"

# ---------------------------------------------------------------- assemble ---
log "Ensamblando ${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
cp "$DIST/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>es</string>
    <key>CFBundleDisplayName</key>
    <string>TapCopy</string>
    <key>CFBundleExecutable</key>
    <string>TapCopy</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TapCopy</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>TapCopy necesita Accesibilidad para leer el texto que seleccionas con el ratón y mostrarte la píldora de copiar. Nunca envía ni almacena tu contenido.</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 BLACK EYE — David DEL RIO COLIN. Uso interno.</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist" >/dev/null || fail "Info.plist inválido"

# ------------------------------------------------------------------- sign ---
log "Firmando con Hardened Runtime (${TEAM_ID})"
xattr -cr "$APP" || true
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "TeamIdentifier|Authority|Runtime Version" || true

# -------------------------------------------------------------------- dmg ---
DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
STAGE="$DIST/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

log "Empaquetando ${APP_NAME}-${VERSION}.dmg"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null
rm -rf "$STAGE"

codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
codesign --verify --verbose=2 "$DMG"

# --------------------------------------------------------------- notarize ---
log "Notarizando con perfil '${KEYCHAIN_PROFILE}' (puede tardar unos minutos)"
xcrun notarytool submit "$DMG" --keychain-profile "$KEYCHAIN_PROFILE" --wait

# ---------------------------------------------------- staple app and dmg ----
log "Engrapando y validando la app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

log "Engrapando y validando el .dmg"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# Gatekeeper smoke checks.
spctl --assess --type execute --verbose=2 "$APP" || fail "Gatekeeper rechazó la app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
log "SHA-256 ${APP_NAME}-${VERSION}.dmg: $SHA"

# ---------------------------------------------------------------- install ---
log "Instalando en ${INSTALL_DIR}/${APP_NAME}.app"
pkill -x "$APP_NAME" || true
sleep 0.4
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
if ! cp -R "$APP" "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null; then
    log "copia directa falló, reintentando con ditto"
    ditto "$APP" "${INSTALL_DIR}/${APP_NAME}.app" || fail "No se pudo instalar en /Applications"
fi

xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "${INSTALL_DIR}/${APP_NAME}.app"
xcrun stapler validate "${INSTALL_DIR}/${APP_NAME}.app"

open "${INSTALL_DIR}/${APP_NAME}.app"
log "Listo: TapCopy ${VERSION} (build ${BUILD}) instalado y en ejecución"
printf 'VERSION=%s\nBUILD=%s\nSHA256=%s\nDMG=%s\n' "$VERSION" "$BUILD" "$SHA" "$DMG" > "$DIST/release-info.txt"
