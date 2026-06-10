#!/bin/bash
# One-time provisioning of Talend Open Studio into the `tos_studio` volume.
#
# Downloads the last open-source release (TOS DI 8.0.1, Apache License 2.0)
# from the configured mirror, unpacks it, prunes everything not needed for
# headless command-line builds, and marks the volume ready.
set -euo pipefail

TOS_HOME="${TOS_HOME:-/opt/tos}"
TOS_DOWNLOAD_URL="${TOS_DOWNLOAD_URL:-https://archive.org/download/talend-studio/TOS_DI-20211109_1610-V8.0.1.zip}"
ZIP="${TOS_HOME}/tos-di.zip"
STUDIO="${TOS_HOME}/studio"

if [ -f "${TOS_HOME}/.ready" ]; then
  echo "[prepare-studio] already provisioned, nothing to do"
  exit 0
fi

echo "[prepare-studio] downloading ${TOS_DOWNLOAD_URL}"
# -C - resumes a partial download if the container restarted mid-transfer.
curl -fL -C - --retry 5 --retry-delay 10 -o "${ZIP}" "${TOS_DOWNLOAD_URL}"

echo "[prepare-studio] unpacking ..."
rm -rf "${TOS_HOME}/unpack" "${STUDIO}"
mkdir -p "${TOS_HOME}/unpack"
unzip -q "${ZIP}" -d "${TOS_HOME}/unpack"

# The zip contains a single top-level directory (TOS_DI-<build>-V<version>).
inner="$(find "${TOS_HOME}/unpack" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [ -z "${inner}" ] || [ ! -d "${inner}/plugins" ]; then
  echo "[prepare-studio] ERROR: unexpected archive layout (no plugins/ found)" >&2
  exit 2
fi
mv "${inner}" "${STUDIO}"
rmdir "${TOS_HOME}/unpack" 2>/dev/null || true

echo "[prepare-studio] pruning GUI/OS payloads we never use headless ..."
rm -rf "${STUDIO}"/Talend-Studio-win-* \
       "${STUDIO}"/Talend-Studio-osx-* \
       "${STUDIO}"/Talend-Studio-macosx-* \
       "${STUDIO}"/*.exe "${STUDIO}"/*.ini.bak \
       "${STUDIO}"/uninstall* 2>/dev/null || true

rm -f "${ZIP}"

launcher="$(find "${STUDIO}/plugins" -maxdepth 1 -name 'org.eclipse.equinox.launcher_*.jar' | head -1)"
if [ -z "${launcher}" ]; then
  echo "[prepare-studio] ERROR: equinox launcher missing" >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# Compile and install our headless CI builder application.
# Talend never open-sourced its CommandLine plugin, so we compile our own
# ~200-line driver against the Studio's plugins (all Apache-2.0): logon
# project -> code generation -> build -> zip.
# ---------------------------------------------------------------------------
echo "[prepare-studio] compiling the CI builder plugin against the studio ..."
PLUGIN_SRC="/app/plugin"
BUILD_DIR="$(mktemp -d)"
mkdir -p "${BUILD_DIR}/classes"
mapfile -t PLUGIN_SOURCES < <(find "${PLUGIN_SRC}/src" -name '*.java')
javac -nowarn --release 11 \
  -cp "${STUDIO}/plugins/*" \
  -d "${BUILD_DIR}/classes" \
  "${PLUGIN_SOURCES[@]}"
cp -r "${PLUGIN_SRC}/META-INF" "${PLUGIN_SRC}/plugin.xml" "${BUILD_DIR}/classes/"
PLUGIN_JAR="${STUDIO}/plugins/org.talendadmin.cibuilder_1.0.0.jar"
(cd "${BUILD_DIR}/classes" && jar cfm "${PLUGIN_JAR}" META-INF/MANIFEST.MF .)
rm -rf "${BUILD_DIR}"

# Register the bundle with the simpleconfigurator (no p2 round-trip needed).
BUNDLES_INFO="${STUDIO}/configuration/org.eclipse.equinox.simpleconfigurator/bundles.info"
if ! grep -q "org.talendadmin.cibuilder" "${BUNDLES_INFO}"; then
  echo "org.talendadmin.cibuilder,1.0.0,plugins/org.talendadmin.cibuilder_1.0.0.jar,4,false" >> "${BUNDLES_INFO}"
fi

touch "${TOS_HOME}/.ready"
echo "[prepare-studio] DONE — studio + CI builder plugin ready at ${STUDIO}"
