#!/system/bin/sh
# RUN_SH_VERSION=4
# =============================================================
# BandLock Probe — penjalan otomatis (cukup unduh file ini 1x)
#
# Jalankan dari Termux (TANPA su, skrip ini yang memanggil su):
#     sh /sdcard/bandlock-probe/run.sh
#
# Yang dilakukan:
#   1. Mengunduh bandlock-ro + probe-core.sh versi TERBARU dari
#      repo GitHub denniramadianto/bandlock-probe (branch main)
#   2. Menjalankan probe sebagai root via su
#   3. Hasil tersimpan di /sdcard/bandlock-probe/hasil-probe.txt lalu
#      OTOMATIS diunggah ke repo privat bandlock-hasil (bila token sudah
#      disimpan di ~/.bandlock-token) -> Muse mengambilnya dari sana.
# =============================================================

BASE="https://raw.githubusercontent.com/denniramadianto/bandlock-probe/main"
DIR=/sdcard/bandlock-probe
mkdir -p "$DIR" 2>/dev/null

# cari pengunduh yang tersedia (Termux: curl/wget)
# Termux TIDAK membawa curl dari bawaan -> pasang sendiri bila belum ada.
DL=""
if command -v curl >/dev/null 2>&1; then DL="curl -fsSL -o";
elif command -v wget >/dev/null 2>&1; then DL="wget -q -O";
fi
if [ -z "$DL" ] && command -v pkg >/dev/null 2>&1; then
  echo "curl belum ada di Termux — memasangnya dulu (sekali saja)..."
  pkg install -y curl
  if command -v curl >/dev/null 2>&1; then DL="curl -fsSL -o"; fi
fi
if [ -z "$DL" ]; then
  echo "curl/wget tidak ditemukan dan pemasangan otomatis gagal."
  echo "Di Termux jalankan manual:  pkg install -y curl   lalu ulangi run.sh."
  exit 1
fi

# Perbarui diri sendiri bila versi di repo lebih baru (berdasarkan RUN_SH_VERSION)
if [ -z "$RUN_SH_SELFUPDATE" ] && [ -f "$DIR/run.sh" ]; then
  if $DL "$DIR/run.sh.new" "$BASE/run.sh" 2>/dev/null; then
    NEW_V=$(sed -n 's/^# RUN_SH_VERSION=//p' "$DIR/run.sh.new" | head -1)
    CUR_V=$(sed -n 's/^# RUN_SH_VERSION=//p' "$DIR/run.sh" | head -1)
    if [ -n "$NEW_V" ] && [ "$NEW_V" != "$CUR_V" ]; then
      mv "$DIR/run.sh.new" "$DIR/run.sh"
      echo "run.sh diperbarui (v$CUR_V -> v$NEW_V) — menjalankan ulang..."
      RUN_SH_SELFUPDATE=1 exec sh "$DIR/run.sh"
    fi
  fi
  rm -f "$DIR/run.sh.new"
fi

echo "Mengunduh versi terbaru dari GitHub..."
$DL "$DIR/bandlock-ro.new" "$BASE/bandlock-ro" || { echo "UNDUH bandlock-ro GAGAL — cek internet HP."; exit 1; }
$DL "$DIR/probe-core.sh.new" "$BASE/probe-core.sh" || { echo "UNDUH probe-core.sh GAGAL — cek internet HP."; exit 1; }
mv "$DIR/bandlock-ro.new" "$DIR/bandlock-ro"
mv "$DIR/probe-core.sh.new" "$DIR/probe-core.sh"
echo "Unduhan OK. Menjalankan probe sebagai root (mungkin muncul permintaan izin Magisk)..."
echo "Output tampil BERJALAN langsung di bawah. Titik-titik (....) = sedang menunggu jawaban modem — itu tanda bekerja, bukan macet."
echo ""
su -c "sh $DIR/probe-core.sh"
echo ""

# --- Unggah hasil otomatis ke repo privat bandlock-hasil ---
# Token fine-grained khusus repo itu, disimpan lokal di Termux: ~/.bandlock-token
TOKEN_FILE="$HOME/.bandlock-token"
HASIL="$DIR/hasil-probe.txt"
if [ -f "$TOKEN_FILE" ] && [ -f "$HASIL" ]; then
  TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
  REPO="denniramadianto/bandlock-hasil"
  API="https://api.github.com/repos/$REPO/contents/hasil-probe.txt"
  echo "Mengunggah hasil ke Muse (repo privat bandlock-hasil)..."
  OLD=$(curl -fsSL -H "Authorization: Bearer $TOKEN" "$API" 2>/dev/null | sed -n 's/.*"sha": "\([0-9a-f]*\)".*/\1/p' | head -1)
  B64=$(base64 -w 0 "$HASIL" 2>/dev/null || base64 "$HASIL" | tr -d '\n')
  SHA_PART=""
  if [ -n "$OLD" ]; then SHA_PART=", \"sha\": \"$OLD\""; fi
  printf '{"message": "hasil probe %s", "content": "%s"%s}' "$(date '+%Y-%m-%d %H:%M')" "$B64" "$SHA_PART" > "$DIR/.upload.json"
  HTTP=$(curl -sSL -w '\n%{http_code}' -X PUT -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -d @"$DIR/.upload.json" "$API" 2>/dev/null)
  CODE=$(printf '%s' "$HTTP" | tail -n 1)
  if [ "$CODE" = "200" ] || [ "$CODE" = "201" ]; then
    echo "Hasil TERKIRIM OTOMATIS ke Muse. Kamu tidak perlu mengirim apa-apa lagi."
  else
    GMSG=$(printf '%s' "$HTTP" | sed -n 's/.*"message": *"\([^"]*\)".*/\1/p' | head -1)
    echo "Unggah otomatis GAGAL (HTTP $CODE): $GMSG"
    echo "Kirim baris error di atas ke Muse. Cadangan: kirim manual file: $HASIL"
  fi
  rm -f "$DIR/.upload.json"
else
  echo "=================================================="
  echo "SELESAI. Kirim file ini ke Muse:"
  echo "  $HASIL"
  echo "(unggah otomatis aktif setelah token disimpan — lihat petunjuk Muse)"
  echo "=================================================="
fi
