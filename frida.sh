#!/system/bin/sh
# =============================================================
# BandLock — penangkap sesi Frida untuk modemcaps (SATU sesi)
#
# Jalankan dari Termux (TANPA su, skrip ini yang memanggil su):
#     sh /sdcard/bandlock-probe/frida.sh
#
# Yang dilakukan:
#   1. Mengunduh frida-server + frida-inject resmi (16.5.9, arm64)
#      dari rilis GitHub Frida + memverifikasi hash-nya
#   2. Menjalankan frida-server sebagai root
#   3. Membuka aplikasi ModemCaps lalu memasang penangkap
#      (mencatat ioctl/write/read kanal diag + nilai sesi)
#   4. Kamu berpindah ke aplikasi, membuka layar editor EFS dan
#      melihat satu file (BACA saja), lalu kembali ke sini dan
#      tekan Ctrl+C — hasil otomatis terunggah ke Muse.
# Penangkap ini READ-ONLY: hanya mencatat, tidak mengubah apa pun.
# =============================================================

FRIDA_VER=16.5.9
SHA_SERVER=ed557802fedeef4155f25fea61f55041e629811c9cb6571a161ed9629162caed
SHA_INJECT=e03e68d71ec2e89bb370666e1ead7c60a2ae93fefddeda2833629009bd126922
REL="https://github.com/frida/frida/releases/download/$FRIDA_VER"
BASE="https://raw.githubusercontent.com/denniramadianto/bandlock-probe/main"
PKG=ru.fieldtest.modemcaps
DIR=/sdcard/bandlock-probe
FDIR=$DIR/frida
mkdir -p "$FDIR" 2>/dev/null

DL=""
if command -v curl >/dev/null 2>&1; then DL="curl -fsSL -o";
elif command -v wget >/dev/null 2>&1; then DL="wget -q -O";
fi
if [ -z "$DL" ] && command -v pkg >/dev/null 2>&1; then
  echo "curl belum ada — memasang dulu..."
  pkg install -y curl
  if command -v curl >/dev/null 2>&1; then DL="curl -fsSL -o"; fi
fi
if [ -z "$DL" ]; then echo "curl/wget tidak ada. Jalankan: pkg install -y curl"; exit 1; fi
if ! command -v xz >/dev/null 2>&1; then
  echo "xz belum ada — memasang xz-utils dulu..."
  pkg install -y xz-utils
fi
command -v xz >/dev/null 2>&1 || { echo "xz tetap tidak ada — berhenti."; exit 1; }

fetch_tool() {
  # $1 = nama file lokal, $2 = nama aset rilis, $3 = hash xz yang diharapkan
  if [ -f "$FDIR/$1" ] && [ -f "$FDIR/$1.ver" ] && [ "$(cat "$FDIR/$1.ver")" = "$FRIDA_VER" ]; then
    echo "$1 sudah ada (v$FRIDA_VER)."
    return 0
  fi
  echo "Mengunduh $2 (rilis resmi Frida $FRIDA_VER)..."
  $DL "$FDIR/$2.xz" "$REL/$2-$FRIDA_VER-android-arm64.xz" || { echo "UNDUH $2 GAGAL — cek internet."; exit 1; }
  H=$(sha256sum "$FDIR/$2.xz" | cut -d' ' -f1)
  if [ "$H" != "$3" ]; then echo "HASH $2 TIDAK COCOK ($H) — unduhan korup, berhenti."; exit 1; fi
  echo "Hash $2 cocok."
  xz -df "$FDIR/$2.xz" || { echo "Ekstrak $2 GAGAL."; exit 1; }
  mv "$FDIR/$2-$FRIDA_VER-android-arm64" "$FDIR/$1"
  echo "$FRIDA_VER" > "$FDIR/$1.ver"
}

fetch_tool frida-server frida-server "$SHA_SERVER"
fetch_tool frida-inject frida-inject "$SHA_INJECT"

echo "Mengunduh skrip penangkap terbaru..."
$DL "$FDIR/capture.js" "$BASE/capture.js?t=$(date +%s)" || { echo "UNDUH capture.js GAGAL."; exit 1; }

echo "Menyiapkan frida-server di /data/local/tmp (lewat su)..."
cat > "$FDIR/.setup.sh" <<EOF
#!/system/bin/sh
cp "$FDIR/frida-server" /data/local/tmp/frida-server
cp "$FDIR/frida-inject" /data/local/tmp/frida-inject
chmod 755 /data/local/tmp/frida-server /data/local/tmp/frida-inject
if pgrep -f frida-server >/dev/null 2>&1; then
  echo "frida-server sudah berjalan."
else
  /data/local/tmp/frida-server >/data/local/tmp/frida-server.log 2>&1 &
  sleep 2
  if pgrep -f frida-server >/dev/null 2>&1; then echo "frida-server BERJALAN."
  else echo "frida-server GAGAL jalan — lihat /data/local/tmp/frida-server.log"; exit 1; fi
fi
am force-stop $PKG
EOF
su -c "sh $FDIR/.setup.sh" || exit 1

echo ""
echo "Membuka aplikasi ModemCaps..."
su -c "monkey -p $PKG -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
PID=""
i=0
while [ $i -lt 20 ]; do
  PID=$(su -c "pidof $PKG" 2>/dev/null | tr -d '\r')
  [ -n "$PID" ] && break
  sleep 1; i=$((i+1))
done
[ -n "$PID" ] || { echo "Proses $PKG tidak ditemukan — buka aplikasinya manual lalu jalankan ulang skrip ini."; exit 1; }
echo "PID aplikasi: $PID"
sleep 2

echo ""
echo "============================================================"
echo "=== TANGKAPAN AKTIF — sekarang lakukan ini di aplikasi: ==="
echo "============================================================"
echo "1. Pindah ke aplikasi ModemCaps (tombol Home / Recent)."
echo "2. Buka layar EDITOR FILE EFS (daftar file /nv/...)."
echo "3. Ketuk SATU file untuk MELIHAT isinya, contoh:"
echo "   lte_feature_enable — cukup dilihat, JANGAN diubah."
echo "4. Bila ada file cell_lock_list / earfcn_lock / pci_lock,"
echo "   boleh dibuka untuk dilihat juga."
echo "5. JANGAN mengetuk ikon tong sampah, jangan menerapkan"
echo "   perubahan apa pun, jangan mengubah centang band."
echo "6. Selesai melihat: kembali ke Termux ini, tekan Ctrl+C."
echo "============================================================"
echo "Menangkap... (Ctrl+C untuk berhenti & mengunggah hasil)"
echo ""

su -c "/data/local/tmp/frida-inject -p $PID -s $FDIR/capture.js" 2>&1 | tee "$DIR/frida-log.txt"

echo ""
echo "Membersihkan proses penangkap..."
su -c "pkill -f frida-inject" 2>/dev/null

# --- Unggah hasil otomatis ke repo privat bandlock-hasil (token yang sama) ---
TOKEN_FILE="$HOME/.bandlock-token"
HASIL="$DIR/frida-log.txt"
if [ -f "$TOKEN_FILE" ] && [ -f "$HASIL" ]; then
  TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
  REPO="denniramadianto/bandlock-hasil"
  API="https://api.github.com/repos/$REPO/contents/frida-log.txt"
  echo "Mengunggah hasil tangkapan ke Muse..."
  OLD=$(curl -fsSL -H "Authorization: Bearer $TOKEN" "$API" 2>/dev/null | sed -n 's/.*"sha": "\([0-9a-f]*\)".*/\1/p' | head -1)
  B64=$(base64 -w 0 "$HASIL" 2>/dev/null || base64 "$HASIL" | tr -d '\n')
  SHA_PART=""
  if [ -n "$OLD" ]; then SHA_PART=", \"sha\": \"$OLD\""; fi
  printf '{"message": "hasil tangkapan frida %s", "content": "%s"%s}' "$(date '+%Y-%m-%d %H:%M')" "$B64" "$SHA_PART" > "$DIR/.upload.json"
  HTTP=$(curl -sSL -w '\n%{http_code}' -X PUT -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -d @"$DIR/.upload.json" "$API" 2>/dev/null)
  CODE=$(printf '%s' "$HTTP" | tail -n 1)
  if [ "$CODE" = "200" ] || [ "$CODE" = "201" ]; then
    echo "Hasil tangkapan TERKIRIM OTOMATIS ke Muse. Selesai — terima kasih."
  else
    GMSG=$(printf '%s' "$HTTP" | sed -n 's/.*"message": *"\([^"]*\)".*/\1/p' | head -1)
    echo "Unggah GAGAL (HTTP $CODE): $GMSG — kirim baris ini ke Muse. File: $HASIL"
  fi
  rm -f "$DIR/.upload.json"
else
  echo "SELESAI. Kirim file ini ke Muse: $HASIL"
fi
