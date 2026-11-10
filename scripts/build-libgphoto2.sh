#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${LIBGPHOTO2_VERSION:-2.5.34}"
ROOT="$PWD/vendor"
PREFIX="$ROOT/gphoto2"
SRC="$ROOT/src/libgphoto2-$VERSION"

if [[ -f "$PREFIX/lib/libgphoto2.dylib" && "${FORCE:-0}" != 1 ]]; then
  echo "libgphoto2 already built in $PREFIX"
  exit 0
fi

for dep in libusb libexif jpeg-turbo libtool gettext pkgconf; do
  brew list "$dep" >/dev/null 2>&1 || brew install "$dep"
done

mkdir -p "$ROOT/src"
rm -rf "$SRC"
curl -fsSL "https://github.com/gphoto/libgphoto2/releases/download/v$VERSION/libgphoto2-$VERSION.tar.xz" | tar -xJ -C "$ROOT/src"

python3 - "$SRC/camlibs/ptp2/config.c" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
get_old = '''static int
_get_Generic_OPCode(CONFIG_GET_ARGS) {
	gp_widget_new (GP_WIDGET_TEXT, _(menu->label), widget);
	gp_widget_set_name (*widget,menu->name);
	gp_widget_set_value  (*widget, "0x1001,0xparam1,0xparam2");'''
get_new = '''static char opcode_result[2048];

static int
_get_Generic_OPCode(CONFIG_GET_ARGS) {
	gp_widget_new (GP_WIDGET_TEXT, _(menu->label), widget);
	gp_widget_set_name (*widget,menu->name);
	gp_widget_set_value  (*widget, opcode_result[0] ? opcode_result : "0x1001,0xparam1,0xparam2");'''
put_old = '''	ret = ptp_transaction (params, &ptp, PTP_DP_GETDATA, 0, &data, &size);

	/* FIXME: handle out data (store locally?) */

	return translate_ptp_result (ret);'''
put_new = '''	if (opcode == PTP_OC_TerminateOpenCapture) {
		ret = PTP_RC_OK;
		if (params->inliveview) {
			ret = ptp_terminateopencapture (params, params->opencapture_transid);
			params->inliveview = 0;
		}
		snprintf (opcode_result, sizeof(opcode_result), "0x%04x", ret);
		return translate_ptp_result (ret);
	}

	x = strchr(val, ';');
	if (x) {
		unsigned int i, n = strlen(x + 1) / 2;
		unsigned char *out = malloc (n ? n : 1);
		for (i = 0; i < n; i++) {
			unsigned int byte;
			if (sscanf(x + 1 + i * 2, "%2x", &byte) != 1) { free (out); return GP_ERROR_BAD_PARAMETERS; }
			out[i] = byte;
		}
		ret = ptp_transaction (params, &ptp, PTP_DP_SENDDATA, n, &out, NULL);
		free (out);
		snprintf (opcode_result, sizeof(opcode_result), "0x%04x", ret);
		return translate_ptp_result (ret);
	}

	ret = ptp_transaction (params, &ptp, PTP_DP_GETDATA, 0, &data, &size);

	{
		unsigned int i, n = size;
		int len = snprintf (opcode_result, sizeof(opcode_result), "0x%04x", ret);
		if (n > (sizeof(opcode_result) - 16) / 2)
			n = (sizeof(opcode_result) - 16) / 2;
		if (n) opcode_result[len++] = ':';
		for (i = 0; i < n; i++)
			len += snprintf (opcode_result + len, sizeof(opcode_result) - len, "%02x", data[i]);
	}
	free (data);

	return translate_ptp_result (ret);'''
assert get_old in s, "opcode getter not found"
assert put_old in s, "opcode setter not found"
s = s.replace(get_old, get_new).replace(put_old, put_new)
open(path, "w").write(s)
PY

BREW="$(brew --prefix)"
export PKG_CONFIG_PATH="$BREW/opt/libusb/lib/pkgconfig:$BREW/opt/libexif/lib/pkgconfig:$BREW/opt/jpeg-turbo/lib/pkgconfig"
export CPPFLAGS="-I$BREW/opt/libtool/include -I$BREW/opt/gettext/include -I$BREW/opt/jpeg-turbo/include"
export LDFLAGS="-L$BREW/opt/libtool/lib -L$BREW/opt/gettext/lib -L$BREW/opt/jpeg-turbo/lib"

cd "$SRC"
./configure --prefix="$PREFIX" --disable-silent-rules --disable-dependency-tracking \
  --with-camlibs=ptp2 --without-gdlib --without-libcurl --disable-nls >/dev/null
make -j"$(sysctl -n hw.ncpu)" >/dev/null
make install >/dev/null
echo "Built patched libgphoto2 $VERSION into $PREFIX"
