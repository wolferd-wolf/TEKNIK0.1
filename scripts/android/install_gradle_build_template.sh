#!/usr/bin/env bash
set -euo pipefail

template_dir="${1:-${GODOT_EXPORT_TEMPLATE_DIR:-${HOME}/.local/share/godot/export_templates/4.3.stable}}"
template_archive="${template_dir}/android_source.zip"
project_root="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
android_dir="${project_root}/android"
build_dir="${android_dir}/build"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT

if [[ ! -f "${template_archive}" ]]; then
  echo "Missing Godot 4.3 Gradle template: ${template_archive}" >&2
  exit 1
fi

unzip -q "${template_archive}" -d "${temp_dir}"
gradlew_path="$(find "${temp_dir}" -type f -name gradlew -print -quit)"

if [[ -z "${gradlew_path}" ]]; then
  echo "Godot Gradle template does not contain a gradlew wrapper." >&2
  unzip -Z1 "${template_archive}" | sed -n '1,80p' >&2
  exit 1
fi

template_root="$(dirname "${gradlew_path}")"
relative_root="${template_root#${temp_dir}/}"
if [[ "${template_root}" == "${temp_dir}" ]]; then
  relative_root="."
fi

echo "Godot Gradle template root: ${relative_root}"

for required_path in gradlew settings.gradle build.gradle gradle/wrapper/gradle-wrapper.properties; do
  if [[ ! -e "${template_root}/${required_path}" ]]; then
    echo "Godot Gradle template is missing ${required_path} under ${relative_root}." >&2
    exit 1
  fi
done

rm -rf "${build_dir}"
mkdir -p "${build_dir}"
cp -a "${template_root}/." "${build_dir}/"
chmod +x "${build_dir}/gradlew"

printf 'Installed Godot Android Gradle template at %s\n' "${build_dir}"
