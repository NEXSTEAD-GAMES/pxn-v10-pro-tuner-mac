#!/bin/sh
# Builds the app and packs it for a release: build/PXN-V10-Pro-Tuner-<version>.zip, holding one folder with
# the app, the pxntuner command-line tool and the licence.
set -eu
cd "$(dirname "$0")/.."
VERSION="$(cat VERSION)"
FOLDER="build/PXN V10 Pro Tuner $VERSION"
ZIP="build/PXN-V10-Pro-Tuner-$VERSION.zip"

./Scripts/make-app.sh

mkdir "$FOLDER"
# Copies, so build/ still holds the app and the tool where make-app.sh left them.
ditto "build/PXN V10 Pro Tuner.app" "$FOLDER/PXN V10 Pro Tuner.app"
cp build/pxntuner LICENSE "$FOLDER/"
# ditto keeps the app's signature intact inside the zip.
ditto -c -k --keepParent "$FOLDER" "$ZIP"
echo "packed $ZIP"
