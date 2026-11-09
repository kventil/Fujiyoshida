#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-libgphoto2.sh
command -v xcodegen >/dev/null || brew install xcodegen

xcodegen generate
xcodebuild -project Fujiyoshida.xcodeproj -scheme Fujiyoshida -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

pkill -x Fujiyoshida 2>/dev/null && while pgrep -x Fujiyoshida >/dev/null; do sleep 0.2; done || true
rm -rf /Applications/Fujiyoshida.app
cp -R build/Build/Products/Release/Fujiyoshida.app /Applications/
open /Applications/Fujiyoshida.app
echo "Installed /Applications/Fujiyoshida.app"
