#!/usr/bin/env bash
set -euo pipefail

template_dir="${1:-${GODOT_EXPORT_TEMPLATE_DIR:-${HOME}/.local/share/godot/export_templates/4.3.stable}}"
template_archive="${template_dir}/android_source.zip"
project_root="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
template_identifier="${3:-$(basename "${template_dir%/}")}"
android_dir="${project_root}/android"
build_dir="${android_dir}/build"
temp_dir="$(mktemp -d)"
temp_build_dir="${temp_dir}/build"
trap 'rm -rf "${temp_dir}"' EXIT

if [[ ! -f "${template_archive}" ]]; then
  echo "Missing Godot 4.3 Gradle template: ${template_archive}" >&2
  exit 1
fi

if [[ -z "${template_identifier}" ]]; then
  echo "Godot Android Gradle template identifier must not be empty." >&2
  exit 1
fi

mkdir -p "${temp_build_dir}"
unzip -q "${template_archive}" -d "${temp_build_dir}"

for required_path in gradlew settings.gradle build.gradle gradle/wrapper/gradle-wrapper.properties; do
  if [[ ! -e "${temp_build_dir}/${required_path}" ]]; then
    echo "Godot 4.3 Gradle source template is missing ${required_path} at its archive root." >&2
    unzip -Z1 "${template_archive}" | sed -n '1,120p' >&2
    exit 1
  fi
done

# Godot 4.3's built-in installer creates this file inside the build directory
# so the editor does not scan the generated Android project as game resources.
: > "${temp_build_dir}/.gdignore"
chmod +x "${temp_build_dir}/gradlew"

mkdir -p "${android_dir}"
rm -rf "${build_dir}"
mv "${temp_build_dir}" "${build_dir}"

# Godot 4.3 validates this sibling marker before starting any Gradle build.
# For the default android_source.zip, its value is VERSION_FULL_CONFIG
# (4.3.stable for the pinned official editor and matching templates).
printf '%s\n' "${template_identifier}" > "${android_dir}/.build_version"

printf 'Installed Godot Android Gradle template at %s\n' "${build_dir}"
printf 'Godot Android template identifier: %s\n' "${template_identifier}"
printf 'Godot Android build marker: %s\n' "${android_dir}/.build_version"
