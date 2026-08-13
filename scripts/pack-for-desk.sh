#!/usr/bin/env bash
#
# Събира готовия Wine в един файл за Desk: `wine-x86_64.tar.xz`.
#
# ── защо не се вземе просто цялата папка ──
#
# Wine се свързва с чужди библиотеки — libX11, freetype, zlib — които идват от
# Termux sysroot-а и НЕ са част от Wine. Пълната папка е 62 MB и в нея има
# стотици неща, които никога няма да се отворят. Затова тук се тръгва от
# самите изпълними файлове и се пита ВСЕКИ от тях какво му трябва, после
# същото за намереното, и така докато списъкът спре да расте. Влиза точно
# каквото се ползва.
#
# Библиотеките, които Android си има (libc, libm, liblog…), НЕ се пакетират:
# те са на телефона, box64 ги подава на x86 кода и втори техен екземпляр само
# би влязъл в спор с първия.
set -euo pipefail

BUILT="$HOME/compiled-files-x86_64"
SYSROOT="$HOME/termuxfs/x86_64/data/data/com.termux/files/usr"
PACK="$(pwd)/pack"
OUT="$(pwd)/output"

# Каквото Android дава само. Списъкът е нарочно точен: сгреши ли се в повече,
# липсва библиотека; сгреши ли се в по-малко, два несъвместими екземпляра на
# едно и също нещо се борят кой да отговори.
SYSTEM_LIBS="libc.so libm.so libdl.so liblog.so libandroid.so libstdc++.so
  libz.so libEGL.so libGLESv1_CM.so libGLESv2.so libGLESv3.so libvulkan.so
  libOpenSLES.so libaaudio.so libnativewindow.so libmediandk.so libjnigraphics.so"

rm -rf "$PACK" "$OUT"
mkdir -p "$PACK/bin" "$PACK/lib" "$PACK/share" "$PACK/licenses" "$OUT"

echo "── Wine ──"
cp -a "$BUILT/bin/." "$PACK/bin/"
cp -a "$BUILT/lib/." "$PACK/lib/"
cp -a "$BUILT/share/." "$PACK/share/"

# Ако unix страната липсва, Wine няма да тръгне никога — по-добре да се разбере
# тук, отколкото на телефона. (Билд #2 даде точно това: 975 MB .dll-и и нито
# една unix библиотека, защото `make` беше умрял, а никой не беше проверил.)
count_so=$(find "$PACK/lib" -name '*.so' | wc -l)
[ "$count_so" -ge 5 ] || { echo "само $count_so .so файла — unix страната липсва" >&2; exit 1; }

# Самият зареждач Wine инсталира в lib/, а в bin/ стоят само препратки към
# него ("winecfg -> wine" и още десетина). Няма ли bin/wine, всички те висят.
if [ ! -e "$PACK/bin/wine" ]; then
  real=$(find "$PACK/lib/wine" -maxdepth 2 -name wine -type f | head -1)
  [ -n "$real" ] || { echo "зареждачът wine изобщо липсва" >&2; exit 1; }
  ln -s "../lib/wine/$(basename "$(dirname "$real")")/wine" "$PACK/bin/wine"
  echo "   bin/wine → ${real#$PACK/}"
fi

# ── никому не е нужен разказът как е компилирано ────────────────────────────
#
# Измерено на билд #2: 975 MB разпънат Wine, от които огромната част е
# отладъчна информация — `wined3d.dll` е 23 MB, а без нея е 4.4 MB. Тя служи
# само на winedbg да покаже имена на функции при забиване; телефонът не я
# ползва.
#
# Маха се САМО `.debug_*` (`--strip-debug`), не и таблицата с износи.
# Проверено локално върху истинските .dll от билд #2: „Wine builtin DLL“ в
# DOS хедъра оцелява — по този надпис Wine познава кой .dll е негов и кой е
# истински уиндоузки, и без него всичко се разпада.
STRIP="$HOME/Android/Sdk/ndk/${NDK_VERSION:-27.3.13750724}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"

strip_everything() {
  find "$PACK/lib/wine" -type f \( -name '*.dll' -o -name '*.exe' \) \
    -exec "$STRIP" --strip-debug {} + 2>/dev/null || true
  find "$PACK/lib" -type f -name '*.so*' -exec "$STRIP" --strip-unneeded {} + 2>/dev/null || true
  find "$PACK/bin" -type f -perm -u+x -exec "$STRIP" --strip-all {} + 2>/dev/null || true
}

before=$(du -sm "$PACK" | cut -f1)
echo "── махане на отладъчната информация ──"
strip_everything
echo "   $before MB → $(du -sm "$PACK" | cut -f1) MB"

# ── кои чужди библиотеки наистина се ползват ─────────────────────────────────

needed_of() {
  readelf -d "$1" 2>/dev/null \
    | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' || true
}

is_system() {
  local name="$1"
  for s in $SYSTEM_LIBS; do [ "$name" = "$s" ] && return 0; done
  return 1
}

declare -A seen
queue=()

# Тръгва се от всичко изпълнимо, което ще се пусне на телефона.
while IFS= read -r -d '' file; do
  queue+=("$file")
done < <(find "$PACK/bin" "$PACK/lib" -type f \( -name '*.so' -o -perm -u+x \) -print0)

echo "── проследяване на зависимостите (${#queue[@]} файла за начало) ──"

while [ ${#queue[@]} -gt 0 ]; do
  current="${queue[0]}"
  queue=("${queue[@]:1}")
  for dep in $(needed_of "$current"); do
    [ -n "${seen[$dep]:-}" ] && continue
    seen[$dep]=1
    is_system "$dep" && continue
    # Може вече да е в самия Wine — тогава няма какво да се носи отвън.
    if find "$PACK/lib" -name "$dep" -print -quit | grep -q .; then continue; fi
    src="$SYSROOT/lib/$dep"
    if [ -f "$src" ]; then
      cp -aL "$src" "$PACK/lib/$dep"
      echo "   + $dep"
      queue+=("$PACK/lib/$dep")
    else
      echo "   ! липсва: $dep" >&2
    fi
  done
done

# Донесеното от Termux също носи отладъчна информация.
strip_everything

# ── лицензите пътуват заедно с кода ─────────────────────────────────────────
#
# Wine е LGPL-2.1. Desk може да се продава с него вътре, но е длъжен да носи
# това и да може да покаже откъде е дошъл кодът. Файлът се пише тук, а не се
# помни от някого.
cp wine-src/COPYING.LIB "$PACK/licenses/wine-LGPL-2.1.txt" 2>/dev/null || \
  cp wine-src/LICENSE "$PACK/licenses/wine-LICENSE.txt" 2>/dev/null || true

cat > "$PACK/licenses/README.txt" <<EOF
Wine — LGPL-2.1. https://www.winehq.org
Изходен код: https://github.com/${WINE_REPO:-GameNative/wine} (клон ${WINE_BRANCH:-wine-11.3})
Компилиран за Desk, комит ${WINE_SHA:-неизвестен}.

Библиотеките в lib/, които не са част от Wine, идват от Termux и запазват
своите лицензи (libX11 — MIT, FreeType — FTL/GPLv2, и т.н.).
EOF

echo "${WINE_VERSION:-11.3}-${WINE_SHA:-dev}" > "$PACK/.version"

# ── един файл ───────────────────────────────────────────────────────────────

echo "── опаковане ──"
tar -C "$PACK" -cf - . | xz -9e -T0 > "$OUT/wine-x86_64.tar.xz"
cp "$PACK/.version" "$OUT/version.txt"

echo
echo "разпънато: $(du -sh "$PACK" | cut -f1)"
echo "архив:     $(du -h "$OUT/wine-x86_64.tar.xz" | cut -f1)"
echo "версия:    $(cat "$OUT/version.txt")"
