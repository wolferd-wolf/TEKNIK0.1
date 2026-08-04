#!/usr/bin/env bash
set -euo pipefail

template_dir="${1:-${GODOT_EXPORT_TEMPLATE_DIR:-${HOME}/.local/share/godot/export_templates/4.3.stable}}"
template_archive="${template_dir}/android_source.zip"
project_root="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
android_dir="${project_root}/android"
build_dir="${android_dir}/build"

if [[ ! -f "${template_archive}" ]]; then
  echo "Missing Godot 4.3 Gradle template: ${template_archive}" >&2
  exit 1
fi

rm -rf "${build_dir}"
mkdir -p "${android_dir}"
unzip -q "${template_archive}" -d "${android_dir}"

if [[ ! -f "${build_dir}/gradlew" ]]; then
  echo "Gradle wrapper was not installed at ${build_dir}/gradlew" >&2
  exit 1
fi

chmod +x "${build_dir}/gradlew"
printf 'Installed Godot Android Gradle template at %s\n' "${build_dir}"
