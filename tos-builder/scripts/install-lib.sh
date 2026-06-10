#!/bin/bash
# Install a jar into the Studio m2 so headless builds can resolve it.
#   install-lib.sh <path-to-jar>
#
# The Maven coordinates come from the Studio's own MavenUriIndex.xml
# (jar name -> mvn:g/a/v/type). Jars unknown to the index (your own drivers,
# routine dependencies...) fall back to Talend's convention for user jars:
# org.talend.libraries:<name-without-.jar>:6.0.0. A minimal pom is written
# alongside so the embedded Maven accepts the artifact.
set -euo pipefail

JAR_PATH="${1:?usage: install-lib.sh <path-to-jar>}"
TOS_HOME="${TOS_HOME:-/opt/tos}"
STUDIO="${TOS_HOME}/studio"
M2_REPO="${STUDIO}/configuration/.m2/repository"
MVN_INDEX="${STUDIO}/configuration/MavenUriIndex.xml"

[ -f "${JAR_PATH}" ] || { echo "ERROR: no such file: ${JAR_PATH}" >&2; exit 1; }

jar="$(basename "${JAR_PATH}")"
uri="$({ grep -o "key=\"${jar}\" value=\"mvn:[^\"]*\"" "${MVN_INDEX}" 2>/dev/null || true; } \
  | sed -E 's/.*value="mvn:([^"]*)".*/\1/' | head -1)"
if [ -z "${uri}" ]; then
  uri="org.talend.libraries/${jar%.jar}/6.0.0"
fi

IFS=/ read -r g a v _ <<< "${uri}"
gpath="${g//.//}"
dest_dir="${M2_REPO}/${gpath}/${a}/${v}"
mkdir -p "${dest_dir}"
cp "${JAR_PATH}" "${dest_dir}/${a}-${v}.jar"
if [ ! -f "${dest_dir}/${a}-${v}.pom" ]; then
  cat > "${dest_dir}/${a}-${v}.pom" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>${g}</groupId>
  <artifactId>${a}</artifactId>
  <version>${v}</version>
  <packaging>jar</packaging>
</project>
EOF
fi
echo "installed ${jar} as mvn:${uri}"
