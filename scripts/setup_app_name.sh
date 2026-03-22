#!/bin/bash

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# setup_app_name.sh
#
# Sets the user-visible display name of the Flutter app across all platforms.
#
# Usage:
#   ./scripts/setup_app_name.sh "My App"
#
# Platforms updated:
#   Android  → android/app/src/main/AndroidManifest.xml  (android:label)
#   iOS      → ios/Runner/Info.plist                      (CFBundleDisplayName + CFBundleName)
#   macOS    → macos/Runner/Configs/AppInfo.xcconfig      (PRODUCT_NAME)
#   Linux    → linux/CMakeLists.txt                       (BINARY_NAME)
#   Windows  → windows/CMakeLists.txt                     (BINARY_NAME)
#              windows/runner/main.cpp                     (window title)
#   Web      → web/manifest.json                          (name + short_name)
#              web/index.html                              (<title>)
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Argument validation ───────────────────────────────────────────────────────

NEW_NAME="${1:-}"

if [ -z "${NEW_NAME}" ]; then
  echo "Usage: $0 \"App Name\""
  echo "Example: $0 \"Citizen Swarm\""
  exit 1
fi

if [ ${#NEW_NAME} -lt 1 ] || [ ${#NEW_NAME} -gt 30 ]; then
  echo "Error: app name must be 1–30 characters (got ${#NEW_NAME})"
  exit 1
fi

echo "Setting app display name to: \"${NEW_NAME}\""
echo ""

# ── Helpers ───────────────────────────────────────────────────────────────────

# replace_in_file <file> <old> <new>
# Skips silently if file doesn't exist or pattern not found.
replace_in_file() {
  local file="$1"
  local old="$2"
  local new="$3"

  if [ ! -f "${file}" ]; then
    echo "  [skip] file not found: ${file}"
    return
  fi

  if ! grep -qF "${old}" "${file}"; then
    echo "  [skip] pattern not found in ${file##"${PROJECT_ROOT}/"}"
    return
  fi

  # macOS sed needs -i '' but GNU sed uses -i; handle both
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "s|${old}|${new}|g" "${file}"
  else
    sed -i '' "s|${old}|${new}|g" "${file}"
  fi

  echo "  [ok]   ${file##"${PROJECT_ROOT}/"}"
}

# detect_current_name <file> <regex>
# Extracts the current app name from a file using grep + sed.
detect_current_name() {
  local file="$1"
  local pattern="$2"
  if [ ! -f "${file}" ]; then
    echo ""
    return
  fi
  grep -o "${pattern}" "${file}" | head -n 1 | sed 's/.*"\(.*\)".*/\1/' || echo ""
}

# ── Detect current name (source of truth = Android manifest) ─────────────────

ANDROID_MANIFEST="${PROJECT_ROOT}/android/app/src/main/AndroidManifest.xml"
CURRENT_NAME=""

if [ -f "${ANDROID_MANIFEST}" ]; then
  CURRENT_NAME="$(grep -o 'android:label="[^"]*"' "${ANDROID_MANIFEST}" \
    | head -n 1 \
    | sed 's/android:label="//;s/"//')"
fi

if [ -z "${CURRENT_NAME}" ]; then
  echo "Warning: could not detect current app name; will attempt best-effort replacements."
  echo ""
else
  echo "Current name: \"${CURRENT_NAME}\""
  echo ""
  if [ "${CURRENT_NAME}" = "${NEW_NAME}" ]; then
    echo "App name is already \"${NEW_NAME}\". Nothing to do."
    exit 0
  fi
fi

# ── Android ───────────────────────────────────────────────────────────────────

echo "── Android ──────────────────────────────────────────────────────────"
if [ -n "${CURRENT_NAME}" ]; then
  replace_in_file \
    "${ANDROID_MANIFEST}" \
    "android:label=\"${CURRENT_NAME}\"" \
    "android:label=\"${NEW_NAME}\""
else
  # Fall back to the Flutter default if nothing was detected
  replace_in_file \
    "${ANDROID_MANIFEST}" \
    'android:label="mobile"' \
    "android:label=\"${NEW_NAME}\""
fi

# ── iOS ───────────────────────────────────────────────────────────────────────

echo "── iOS ───────────────────────────────────────────────────────────────"
IOS_PLIST="${PROJECT_ROOT}/ios/Runner/Info.plist"

update_plist_string_value() {
  local plist="$1"
  local key="$2"
  local new_val="$3"

  if [ ! -f "${plist}" ]; then
    echo "  [skip] file not found: ${plist}"
    return
  fi

  # Match the <key>KEY</key> line followed by a <string>...</string> line
  # and replace the string value using Python (available on all macOS/Linux CI).
  if command -v python3 &>/dev/null; then
    python3 - "${plist}" "${key}" "${new_val}" <<'EOF'
import sys, re

path, key, new_val = sys.argv[1], sys.argv[2], sys.argv[3]

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Match <key>KEY</key>\n\t<string>OLD</string> and replace the string value
pattern = r'(<key>{}</key>\s*<string>)[^<]*(</string>)'.format(re.escape(key))
replacement = r'\g<1>{}\g<2>'.format(new_val)
new_content, count = re.subn(pattern, replacement, content)

if count == 0:
    print(f"  [skip] key '{key}' not found in {path}")
    sys.exit(0)

with open(path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"  [ok]   {path.split('/')[-3]}/{path.split('/')[-2]}/{path.split('/')[-1]}  ({key})")
EOF
  else
    # Fallback: sed-based (works when current value is known)
    if [ -n "${CURRENT_NAME}" ]; then
      replace_in_file "${plist}" "<string>${CURRENT_NAME}</string>" "<string>${new_val}</string>"
    else
      echo "  [skip] python3 not available and current name unknown; update ${plist} manually"
    fi
  fi
}

update_plist_string_value "${IOS_PLIST}" "CFBundleDisplayName" "${NEW_NAME}"
update_plist_string_value "${IOS_PLIST}" "CFBundleName"        "${NEW_NAME}"

# ── macOS ─────────────────────────────────────────────────────────────────────

echo "── macOS ─────────────────────────────────────────────────────────────"
MACOS_XCCONFIG="${PROJECT_ROOT}/macos/Runner/Configs/AppInfo.xcconfig"

if [ -f "${MACOS_XCCONFIG}" ]; then
  CURRENT_MACOS="$(grep -o 'PRODUCT_NAME = .*' "${MACOS_XCCONFIG}" | sed 's/PRODUCT_NAME = //' | tr -d '\r')"
  if [ -n "${CURRENT_MACOS}" ]; then
    replace_in_file "${MACOS_XCCONFIG}" "PRODUCT_NAME = ${CURRENT_MACOS}" "PRODUCT_NAME = ${NEW_NAME}"
  else
    replace_in_file "${MACOS_XCCONFIG}" "PRODUCT_NAME = mobile" "PRODUCT_NAME = ${NEW_NAME}"
  fi
fi

# ── Linux ─────────────────────────────────────────────────────────────────────

echo "── Linux ─────────────────────────────────────────────────────────────"
LINUX_CMAKE="${PROJECT_ROOT}/linux/CMakeLists.txt"

if [ -f "${LINUX_CMAKE}" ]; then
  CURRENT_LINUX="$(grep -o 'set(BINARY_NAME "[^"]*")' "${LINUX_CMAKE}" \
    | sed 's/set(BINARY_NAME "//;s/")//' | head -n 1)"
  if [ -n "${CURRENT_LINUX}" ]; then
    replace_in_file "${LINUX_CMAKE}" \
      "set(BINARY_NAME \"${CURRENT_LINUX}\")" \
      "set(BINARY_NAME \"${NEW_NAME}\")"
  fi
fi

# ── Windows ───────────────────────────────────────────────────────────────────

echo "── Windows ───────────────────────────────────────────────────────────"
WIN_CMAKE="${PROJECT_ROOT}/windows/CMakeLists.txt"
WIN_MAIN="${PROJECT_ROOT}/windows/runner/main.cpp"

if [ -f "${WIN_CMAKE}" ]; then
  CURRENT_WIN="$(grep -o 'set(BINARY_NAME "[^"]*")' "${WIN_CMAKE}" \
    | sed 's/set(BINARY_NAME "//;s/")//' | head -n 1)"
  if [ -n "${CURRENT_WIN}" ]; then
    replace_in_file "${WIN_CMAKE}" \
      "set(BINARY_NAME \"${CURRENT_WIN}\")" \
      "set(BINARY_NAME \"${NEW_NAME}\")"
  fi
fi

# Windows title in main.cpp uses L"..." wide string literals
if [ -f "${WIN_MAIN}" ]; then
  CURRENT_WIN_TITLE="$(grep -o 'L"[^"]*"' "${WIN_MAIN}" | head -n 1 | tr -d 'L"')"
  if [ -n "${CURRENT_WIN_TITLE}" ]; then
    replace_in_file "${WIN_MAIN}" "L\"${CURRENT_WIN_TITLE}\"" "L\"${NEW_NAME}\""
  fi
fi

# ── Web ───────────────────────────────────────────────────────────────────────

echo "── Web ───────────────────────────────────────────────────────────────"
WEB_MANIFEST="${PROJECT_ROOT}/web/manifest.json"
WEB_INDEX="${PROJECT_ROOT}/web/index.html"

if [ -f "${WEB_MANIFEST}" ]; then
  # "name": "OLD" and "short_name": "OLD"
  CURRENT_WEB_NAME="$(python3 -c "
import json, sys
with open('${WEB_MANIFEST}') as f:
    d = json.load(f)
print(d.get('name', ''))
" 2>/dev/null || grep -o '"name": "[^"]*"' "${WEB_MANIFEST}" | sed 's/"name": "//;s/"//' | head -n 1)"

  if [ -n "${CURRENT_WEB_NAME}" ]; then
    replace_in_file "${WEB_MANIFEST}" \
      "\"name\": \"${CURRENT_WEB_NAME}\"" \
      "\"name\": \"${NEW_NAME}\""
    replace_in_file "${WEB_MANIFEST}" \
      "\"short_name\": \"${CURRENT_WEB_NAME}\"" \
      "\"short_name\": \"${NEW_NAME}\""
  else
    replace_in_file "${WEB_MANIFEST}" '"name": "mobile"'       "\"name\": \"${NEW_NAME}\""
    replace_in_file "${WEB_MANIFEST}" '"short_name": "mobile"' "\"short_name\": \"${NEW_NAME}\""
  fi
fi

if [ -f "${WEB_INDEX}" ]; then
  # Detect the <title> value directly from the file (may differ from manifest name)
  CURRENT_WEB_TITLE="$(grep -o '<title>[^<]*</title>' "${WEB_INDEX}" \
    | sed 's/<title>//;s/<\/title>//' | head -n 1)"
  if [ -n "${CURRENT_WEB_TITLE}" ]; then
    replace_in_file "${WEB_INDEX}" \
      "<title>${CURRENT_WEB_TITLE}</title>" \
      "<title>${NEW_NAME}</title>"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "Done. App display name set to \"${NEW_NAME}\"."
echo "Next: flutter clean && flutter pub get"
