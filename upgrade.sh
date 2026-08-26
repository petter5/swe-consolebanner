#!/bin/bash
#
# Safely upgrade an existing swe-consolebanner install on a running
# Smoothwall Express 3.1 box: fetch and install the release tarball, then
# regenerate the banner immediately.
#
# For a FRESH install (no existing swe-consolebanner), don't use this
# script - see the README's "New install" section instead.
#
# Usage (as root, on the Smoothwall box):
#   curl -fsSL -o upgrade.sh https://raw.githubusercontent.com/petter5/swe-consolebanner/master/upgrade.sh
#   less upgrade.sh   # read it before running anything as root
#   bash upgrade.sh

set -e

VERSION="0.1.0"
MOD_HOME="/var/smoothwall/mods-available/consolebanner"

echo "=== swe-consolebanner upgrade to ${VERSION} ==="

if [ "$(id -u)" != "0" ]; then
	echo "Must be run as root." >&2
	exit 1
fi

if [ ! -d "${MOD_HOME}" ]; then
	echo "No existing install found at ${MOD_HOME} - this script is for" >&2
	echo "upgrades only. For a fresh install, see the README instead." >&2
	exit 1
fi

INSTALLED_VERSION=""
if [ -f "${MOD_HOME}/VERSION" ]; then
	INSTALLED_VERSION=$(sed -n 's/^MOD_VERSION=//p' "${MOD_HOME}/VERSION")
fi

if [ "${INSTALLED_VERSION}" = "${VERSION}" ]; then
	echo "${MOD_HOME} is already on ${VERSION} - nothing to do."
	exit 0
fi

echo "--- Fetching ${VERSION} ---"
cd /tmp
rm -rf consolebanner consolebanner.tar.gz
curl -fsSL -o consolebanner.tar.gz "https://github.com/petter5/swe-consolebanner/releases/download/${VERSION}/swe-consolebanner-${VERSION}.tar.gz"
tar xzf consolebanner.tar.gz
mv "swe-consolebanner-${VERSION}" consolebanner
cd consolebanner

echo "--- Installing (enable-consolebanner) ---"
echo y | perl enable-consolebanner

echo "=== Done - /etc/issue regenerated, mod at ${VERSION} ==="
