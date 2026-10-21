#!/system/bin/sh
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
#   3. Hasil tersimpan di /sdcard/bandlock-probe/hasil-probe.txt
#      -> kirim file itu ke Muse, selesai.
# =============================================================

BASE="https://raw.githubusercontent.com/denniramadianto/bandlock-probe/main"
DIR=/sdcard/bandlock-probe
mkdir -p "$DIR" 2>/dev/null

# cari pengunduh yang tersedia (Termux: curl/wget)
DL=""
if command -v curl >/dev/null 2>&1; then DL="curl -fsSL -o";
elif command -v wget >/dev/null 2>&1; then DL="wget -q -O";
fi
if [ -z "$DL" ]; then
  echo "curl/wget tidak ditemukan. Di Termux jalankan dulu:  pkg install curl"
  exit 1
fi

echo "Mengunduh versi terbaru dari GitHub..."
$DL "$DIR/bandlock-ro.new" "$BASE/bandlock-ro" || { echo "UNDUH bandlock-ro GAGAL — cek internet HP."; exit 1; }
$DL "$DIR/probe-core.sh.new" "$BASE/probe-core.sh" || { echo "UNDUH probe-core.sh GAGAL — cek internet HP."; exit 1; }
mv "$DIR/bandlock-ro.new" "$DIR/bandlock-ro"
mv "$DIR/probe-core.sh.new" "$DIR/probe-core.sh"
echo "Unduhan OK. Menjalankan probe sebagai root (mungkin muncul permintaan izin Magisk)..."
echo ""
su -c "sh $DIR/probe-core.sh"
echo ""
echo "=================================================="
echo "SELESAI. Kirim file ini ke Muse:"
echo "  $DIR/hasil-probe.txt"
echo "=================================================="
