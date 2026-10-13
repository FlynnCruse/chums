#!/bin/zsh
# Builds ~/Applications/Chums.app (the Mac side's one identity for permissions, and the window that asks for them; see
# main.swift) when it's missing or its source or signing identity changed, and prints the path of its executable.
#   tools/mac-app/build.zsh [--force]
#   tools/mac-app/build.zsh --expected-stamp     what an up-to-date Chums.app's stamp is (builds nothing)
# Signing: your Apple Development certificate for the configured team (the free Personal Team's works too) keeps the
# same identity across rebuilds and the yearly certificate renewal, so permissions stay. With no certificate, ad hoc:
# macOS ties permissions to that exact build, and a rebuild has to be allowed again (it says so).
set -e
HERE="${0:A:h}"
source "$HERE/../common.zsh"
APP=${CHUMS_MAC_APP:-$HOME/Applications/Chums.app}
EXE="$APP/Contents/MacOS/Chums"
BUNDLE=${CHUMS_BUNDLE:-$(chums_cfg bundleId)}; BUNDLE="${BUNDLE:-dev.chums}.mac"
TEAM=${CHUMS_TEAM:-$(chums_cfg team)}
# none set: the team bin/chums-install signs the apps with (else ad hoc, and macOS asks again after every rebuild)
[[ -z $TEAM ]] && TEAM=$(python3 "$HERE/../pick-team.py" 2>/dev/null) || true
ID=""
if [[ -n $TEAM ]]; then
  for h in $(security find-identity -v -p codesigning | awk '/Apple Development/{print $2}'); do
    ou=$(security find-certificate -a -Z -p 2>/dev/null | awk -v h=$h 'BEGIN{p=0} /^SHA-1 hash:/{p=($3==h)} p' \
      | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')
    [[ $ou == $TEAM ]] && { ID=$h; break }
  done
fi
SRC=$(cat "$HERE/main.swift" "$HERE/build.zsh" | shasum | cut -c1-16)-$BUNDLE
STAMP=$SRC-${ID:-adhoc}
[[ $1 == --expected-stamp ]] && { print -- $STAMP; exit 0 }

OLD=$(cat "$APP/Contents/Resources/stamp" 2>/dev/null || true)
if [[ $1 != --force && -x $EXE && $OLD == $STAMP ]]; then
  print -- $EXE; exit 0
fi
chums_need xcrun "Install Xcode or its command line tools: xcode-select --install"
TMP=$(mktemp -d -t chums-app); trap 'rm -rf "${TMP:?}"' EXIT
B="$TMP/Chums.app"; mkdir -p "$B/Contents/MacOS" "$B/Contents/Resources"
for arch in arm64 x86_64; do
  xcrun swiftc -O -target $arch-apple-macos13 -o "$TMP/Chums-$arch" "$HERE/main.swift"
done
lipo -create "$TMP/Chums-arm64" "$TMP/Chums-x86_64" -output "$B/Contents/MacOS/Chums"

# the icon: Noodle (the public watch app's icon; in this repo the overlay has it, in the public one the app does)
ICON=""
for d in "$CHUMS_ROOT"/app; do
  ICON=$(print -l "$d"/ChumsWatch/Assets.xcassets/AppIcon.appiconset/*.png(N) | head -1); [[ -n $ICON ]] && break
done
if [[ -n $ICON ]]; then
  IS="$TMP/Chums.iconset"; mkdir -p "$IS"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON" --out "$IS/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ICON" --out "$IS/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$IS" -o "$B/Contents/Resources/Chums.icns"
fi

# a reason line for everything an agent may touch: with no reason, macOS can refuse without showing a dialog at all
WHY="Your Chums agents do this on your Mac when you ask them to from the watch."
keys=(NSAppleEventsUsageDescription NSDesktopFolderUsageDescription NSDocumentsFolderUsageDescription
      NSDownloadsFolderUsageDescription NSRemovableVolumesUsageDescription NSNetworkVolumesUsageDescription
      NSFileProviderDomainUsageDescription NSLocalNetworkUsageDescription NSContactsUsageDescription
      NSCalendarsUsageDescription NSCalendarsFullAccessUsageDescription NSRemindersUsageDescription
      NSRemindersFullAccessUsageDescription NSPhotoLibraryUsageDescription NSSystemAdministrationUsageDescription
      NSBluetoothAlwaysUsageDescription NSMicrophoneUsageDescription NSCameraUsageDescription)
reasons=""
for k in $keys; do reasons+="  <key>$k</key><string>$WHY</string>"$'\n'; done
cat > "$B/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE</string>
  <key>CFBundleName</key><string>Chums</string>
  <key>CFBundleDisplayName</key><string>Chums</string>
  <key>CFBundleExecutable</key><string>Chums</string>
  <key>CFBundleIconFile</key><string>Chums</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
$reasons</dict></plist>
PL

# the stamp says which identity actually signed it (a locked keychain falls back to ad hoc)
sign() { print -- "$SRC-$1" > "$B/Contents/Resources/stamp"; codesign --force --timestamp=none -s "$2" "$B" >/dev/null 2>&1 }
if [[ -n $ID ]] && sign $ID $ID; then NEW=$ID; else sign adhoc - || chums_die "codesign failed"; NEW=adhoc; fi

# a new identity means macOS sees a new app: what was allowed has to be allowed again
if [[ -n $OLD && ${OLD##*-} != $NEW ]]; then
  print -u2 -- "chums: Chums.app is signed with a new identity ($([[ $NEW == adhoc ]] && print ad hoc || print your Apple Development certificate)): open Chums and click Allow All again."
elif [[ -n $OLD && $NEW == adhoc && $OLD != "$SRC-adhoc" ]]; then
  print -u2 -- "chums: Chums.app was rebuilt and is signed ad hoc: open Chums and click Allow All again."
fi

# swap in place: a LaunchAgent restarting meanwhile always finds an executable
mkdir -p "${APP:h}"
NEXT="${APP:h}/.Chums.app.new"; PREV="${APP:h}/.Chums.app.old"
rm -rf "${NEXT:?}" "${PREV:?}"; ditto "$B" "$NEXT"
[[ -d $APP ]] && mv "$APP" "$PREV"
mv "$NEXT" "$APP"; rm -rf "${PREV:?}"
# System Settings lists an app's permissions only if LaunchServices knows where the app is: tell it, every build
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$APP" 2>/dev/null || true
# what runs through the old Chums starts again through the new one (macOS checks a running program against its file);
# bin/chums-setup and bin/chums-agents reload theirs anyway and set CHUMS_NO_RESTART
if [[ -n $OLD && -z $CHUMS_NO_RESTART ]]; then
  for f in ~/Library/LaunchAgents/$CHUMS_LABEL_PREFIX.{hub,tailscaled}.plist(N) ~/Library/LaunchAgents/$CHUMS_LABEL_PREFIX.agent.*.plist(N); do
    launchctl kickstart -k gui/$(id -u)/${${f:t}%.plist} 2>/dev/null && print -u2 -- "chums: restarted ${${f:t}%.plist} on the new Chums.app"
  done
fi
print -- $EXE
