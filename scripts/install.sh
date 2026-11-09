#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-libgphoto2.sh
command -v xcodegen >/dev/null || brew install xcodegen

xcodegen generate
xcodebuild -project FujiCam.xcodeproj -scheme FujiCam -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

pkill -x FujiCam 2>/dev/null && while pgrep -x FujiCam >/dev/null; do sleep 0.2; done || true
rm -rf /Applications/FujiCam.app
cp -R build/Build/Products/Release/FujiCam.app /Applications/
open /Applications/FujiCam.app
echo "Installed /Applications/FujiCam.app"
