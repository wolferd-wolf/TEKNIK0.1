#!/usr/bin/env bash
set -euo pipefail

keystore_path="${1:-${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-${HOME}/.local/share/godot/teknik-test-release.keystore}}"
keystore_alias="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-teknikrelease}"
keystore_password="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-teknikrelease}"

if [[ ${#keystore_password} -lt 6 ]]; then
  echo "Release keystore password must contain at least 6 characters." >&2
  exit 2
fi

mkdir -p "$(dirname "${keystore_path}")"

if [[ ! -f "${keystore_path}" ]]; then
  keytool \
    -genkeypair \
    -v \
    -keystore "${keystore_path}" \
    -storetype PKCS12 \
    -storepass "${keystore_password}" \
    -alias "${keystore_alias}" \
    -keypass "${keystore_password}" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "CN=TEKNIK Test Release,O=TEKNIK,C=IN" \
    -noprompt
fi

keytool \
  -list \
  -v \
  -keystore "${keystore_path}" \
  -storepass "${keystore_password}" \
  -alias "${keystore_alias}"
