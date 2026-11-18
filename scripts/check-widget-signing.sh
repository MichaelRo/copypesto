#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Checks that an exported Pesto.app can show the Mac's Recent Clips widget (ADR 0059): check-widget-signing.sh <Pesto.app>.
# The app and its Controls extension must each embed a Developer ID profile, claim the app group and the widget's
# Keychain group, and have those claims authorized by their profile. An app group claim the profile does not authorize
# clears the app's validated entitlements on macOS, and the sync key's iCloud Keychain item is then refused, so such a
# build must not ship. The app group must be listed by name: a profile that lists only "<team>.*" may also authorize it
# (Apple DTS says so for profiles made since June 2025), but that is not checked here, so this refuses it. It does not
# prove the widget opens its snapshot; that is a hand check (docs/release.md).
set -euo pipefail
app="${1:-}"
[[ -d "$app" ]] || { echo "check-widget-signing: pass the path of Pesto.app" >&2; exit 1; }
appex="$app/Contents/PlugIns/PestoControls.appex"
[[ -d "$appex" ]] || { echo "check-widget-signing: $appex is missing" >&2; exit 1; }
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

check() {
  local bundle="$1" identifier="$2" role="$3"
  local profile="$bundle/Contents/embedded.provisionprofile"
  [[ -f "$profile" ]] || {
    echo "check-widget-signing: $profile is missing: the $role was not signed with its profile" >&2; return 1; }
  codesign -d --entitlements - --xml "$bundle" > "$scratch/$role-signed.plist" 2>/dev/null || {
    echo "check-widget-signing: could not read the $role's signed entitlements" >&2; return 1; }
  security cms -D -i "$profile" > "$scratch/$role-profile.plist" 2>/dev/null || {
    echo "check-widget-signing: could not read the $role's profile" >&2; return 1; }
  python3 -I - "$scratch/$role-signed.plist" "$scratch/$role-profile.plist" "$identifier" "$role" <<'PY'
import fnmatch, plistlib, sys

signed_path, profile_path, identifier, role = sys.argv[1:5]
group = "group.net.copypesto.pesto"
widget_suffix = ".net.copypesto.pesto.widget"
with open(signed_path, "rb") as handle:
    signed = plistlib.load(handle)
with open(profile_path, "rb") as handle:
    allowed = plistlib.load(handle).get("Entitlements", {})
problems = []

def authorized(value, patterns):
    return any(fnmatch.fnmatchcase(value, pattern) for pattern in patterns)

app_id = signed.get("com.apple.application-identifier", "")
if not app_id.endswith("." + identifier):
    problems.append(f"its application identifier is '{app_id}', not <team>.{identifier}")
if allowed.get("com.apple.application-identifier") != app_id:
    problems.append("the profile does not authorize its application identifier")
team = app_id.split(".", 1)[0]
groups = signed.get("com.apple.security.application-groups", [])
if group not in groups:
    problems.append(f"it does not claim the app group {group}")
for claimed in groups:
    if not authorized(claimed, allowed.get("com.apple.security.application-groups", [])):
        problems.append(f"the profile does not authorize the app group {claimed}")
keychain = signed.get("keychain-access-groups", [])
widget_group = team + widget_suffix
if widget_group not in keychain:
    problems.append(f"it does not claim the Keychain group {widget_group}")
for claimed in keychain:
    if not authorized(claimed, allowed.get("keychain-access-groups", [])):
        problems.append(f"the profile does not authorize the Keychain group {claimed}")
if role == "app" and (not keychain or keychain[0] != f"{team}.net.copypesto.pesto"):
    problems.append("its own Keychain group is not first, so its items would move")
if role == "extension" and keychain != [widget_group]:
    problems.append(f"it claims Keychain groups beyond the widget's: {keychain}")
if role == "extension" and signed.get("com.apple.security.app-sandbox") is not True:
    problems.append("it is not sandboxed")
for problem in problems:
    print(f"check-widget-signing ({role}): {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
}

check "$app" "net.copypesto.pesto" app
check "$appex" "net.copypesto.pesto.controls" extension
echo "widget signing ok: the app and the Controls extension share group.net.copypesto.pesto and the widget's Keychain group"
