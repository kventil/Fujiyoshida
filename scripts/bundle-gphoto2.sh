#!/bin/zsh
set -euo pipefail

BREW_PREFIX="${BREW_PREFIX:-/opt/homebrew}"
GPHOTO="$SRCROOT/vendor/gphoto2"
APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
FRAMEWORKS="$APP/Contents/Frameworks"
GP_DIR="$FRAMEWORKS/libgphoto2"
EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"

rm -rf "$GP_DIR"
mkdir -p "$GP_DIR/camlibs" "$GP_DIR/iolibs"

cp "$GPHOTO"/lib/libgphoto2/*/ptp2.so "$GP_DIR/camlibs/"
cp "$GPHOTO"/lib/libgphoto2_port/*/usb1.so "$GP_DIR/iolibs/"

brew_deps() {
  otool -L "$1" | tail -n +2 | awk '{print $1}' | grep -E "^($BREW_PREFIX|$GPHOTO)/" || true
}

typeset -A seen
queue=("$EXECUTABLE" "$GP_DIR"/camlibs/*.so "$GP_DIR"/iolibs/*.so)

while (( ${#queue} )); do
  file="${queue[1]}"
  queue=("${queue[@]:1}")
  for dep in $(brew_deps "$file"); do
    name="${dep:t}"
    if [[ -z "${seen[$name]:-}" ]]; then
      seen[$name]=1
      cp -fL "$dep" "$FRAMEWORKS/$name"
      chmod u+w "$FRAMEWORKS/$name"
      install_name_tool -id "@rpath/$name" "$FRAMEWORKS/$name" 2>/dev/null
      queue+=("$FRAMEWORKS/$name")
    fi
    install_name_tool -change "$dep" "@rpath/$name" "$file" 2>/dev/null
  done
done

for plugin in "$GP_DIR"/camlibs/*.so "$GP_DIR"/iolibs/*.so; do
  install_name_tool -add_rpath "@loader_path/../.." "$plugin" 2>/dev/null
done
for lib in "$FRAMEWORKS"/*.dylib; do
  install_name_tool -add_rpath "@loader_path" "$lib" 2>/dev/null || true
done
if ! otool -l "$EXECUTABLE" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXECUTABLE"
fi

leftovers=$(for f in "$EXECUTABLE" "$FRAMEWORKS"/*.dylib "$GP_DIR"/*/*.so; do brew_deps "$f"; done)
if [[ -n "$leftovers" ]]; then
  echo "error: unresolved non-bundled library references:"; echo "$leftovers"; exit 1
fi

if [[ "${CODE_SIGNING_ALLOWED:-YES}" == "YES" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
  identity="$EXPANDED_CODE_SIGN_IDENTITY"
else
  identity="-"
fi
for f in "$FRAMEWORKS"/*.dylib "$GP_DIR"/*/*.so; do
  codesign --force --sign "$identity" --timestamp=none "$f"
done
