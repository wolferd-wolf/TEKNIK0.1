#!/usr/bin/env bash
set -euo pipefail

keystore_path="${1:-${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-${HOME}/.local/share/godot/teknik-debug.keystore}}"
keystore_alias="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
keystore_password="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"

mkdir -p "$(dirname "${keystore_path}")"

if [[ ! -f "${keystore_path}" ]]; then
  keytool \
    -keyalg RSA \
    -genkeypair \
    -alias "${keystore_alias}" \
    -keypass "${keystore_password}" \
    -keystore "${keystore_path}" \
    -storepass "${keystore_password}" \
    -dname "CN=Android Debug,O=Android,C=US" \
    -validity 9999 \
    -deststoretype pkcs12 \
    -noprompt
fi

keytool \
  -list \
  -v \
  -keystore "${keystore_path}" \
  -storepass "${keystore_password}" \
  -alias "${keystore_alias}"
