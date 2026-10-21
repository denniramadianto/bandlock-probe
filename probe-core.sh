#!/system/bin/sh
# =============================================================
# Probe kelayakan BandLock (inti probe, diunduh otomatis oleh run.sh) — Redmi 4X (santoni)
# Jalankan sebagai ROOT. HANYA MEMBACA — tidak menulis apa pun
# ke modem dan tidak mengubah setting apa pun.
#
# Cara pakai (pilih salah satu):
#   A) Dari HP (Termux / aplikasi terminal):
#        su
#        sh /sdcard/bandlock-probe/probe-core.sh
#   B) Dari PC via ADB:
#        adb shell "su -c 'sh /sdcard/bandlock-probe/probe-core.sh'"
#
# Seluruh output juga disimpan ke /sdcard/bandlock-probe/hasil-probe.txt
# Kirim file itu (atau seluruh output layar) kembali ke Muse.
# =============================================================

DIR=$(dirname "$0")
mkdir -p /sdcard/bandlock-probe 2>/dev/null
OUT=/sdcard/bandlock-probe/hasil-probe.txt
TMP=/sdcard/bandlock-probe/.probe_tmp

{
echo "===== 0. Perangkat & waktu ====="
date
getprop ro.product.device
getprop ro.build.fingerprint
getprop ro.build.version.release
id

echo ""
echo "===== 1. Kernel & SELinux ====="
uname -a
getenforce 2>/dev/null || echo "(getenforce tidak ada)"

echo ""
echo "===== 2. Node perangkat modem ====="
ls -l /dev/diag /dev/diag_mdm /dev/qmi* /dev/wwan* /dev/smd* 2>/dev/null
ls /dev/socket/ 2>/dev/null | grep -i qmux || echo "(tidak ada socket qmuxd)"

echo ""
echo "===== 3. Dukungan QRTR di kernel & modul ====="
grep -i qipcrtr /proc/net/protocols || echo "QIPCRTR TIDAK ketemu di /proc/net/protocols"
grep -i qrtr /proc/net/protocols
lsmod 2>/dev/null | grep -iE "qrtr|qmi" || echo "(tidak ada modul qrtr/qmi yang sedang termuat)"
ls /vendor/lib/modules/ /system/lib/modules/ 2>/dev/null | grep -iE "qrtr|qmi" || echo "(tidak ada file modul qrtr/qmi di folder modul)"

echo ""
echo "===== 4. Alat bantu root ====="
which magiskpolicy supolicy magisk 2>/dev/null
magisk -v 2>/dev/null || true

echo ""
echo "===== 5. Info SIM & radio menurut Android ====="
getprop | grep -iE "gsm\.sim|gsm\.operator|multisim|baseband|ril\." | head -20

echo ""
echo "===== 5b. Layanan qmuxd / QRTR ====="
getprop | grep -iE "qmux|qrtr"
ls -l /dev/socket/ 2>/dev/null | grep -iE "qmux|qrtr"
echo "--- isi folder /dev/socket/qmux_radio/ ---"
ls -la /dev/socket/qmux_radio/ 2>/dev/null || echo "(folder tidak bisa dibuka)"
ps -A 2>/dev/null | grep -iE "qmux|qrtr|rild" || ps 2>/dev/null | grep -iE "qmux|qrtr|rild"

echo ""
echo "===== 6. Helper bandlock-ro v0.7 (diag EFS2: baca file kunci sel di modem) ====="
HELPER=""
for cand in "$DIR/bandlock-ro" /sdcard/bandlock-probe/bandlock-ro /data/local/tmp/bandlock-ro; do
  if [ -f "$cand" ]; then HELPER="$cand"; break; fi
done
if [ -n "$HELPER" ]; then
  echo "helper sumber: $HELPER"
  # /sdcard terpasang noexec -> binary tidak bisa jalan dari sana.
  # Salin ke /data/local/tmp (boleh exec) lalu jalankan dari sana.
  RUN=/data/local/tmp/bandlock-ro
  cp "$HELPER" "$RUN" 2>/dev/null
  chmod 755 "$RUN" 2>/dev/null
  if [ -x "$RUN" ]; then
    pkill -9 -f bandlock-ro 2>/dev/null; sleep 1; echo "(sisa helper lama dibersihkan)"
    echo "helper dijalankan dari: $RUN"
    "$RUN" status
  else
    echo "GAGAL menyalin helper ke $RUN — catat baris ini."
    ls -l "$RUN" 2>/dev/null
  fi
else
  echo "bandlock-ro TIDAK ditemukan di folder probe — bagian terpenting dilewati."
  echo "Pastikan file bandlock-ro ikut tersalin ke folder yang sama dengan skrip ini."
fi

echo ""
echo "===== 7. Penolakan SELinux terkait (dari dmesg, bila bisa dibaca) ====="
dmesg 2>/dev/null | grep -iE "avc.*(qrtr|qmi|qipcrtr)" | tail -10
echo "(bila kosong: tidak ada catatan penolakan / dmesg tidak terbaca)"

echo ""
echo "===== SELESAI — kirim file hasil-probe.txt ke Muse ====="
} 2>&1 | tee "$TMP"

cp "$TMP" "$OUT" 2>/dev/null
rm -f "$TMP" 2>/dev/null
echo ""
echo "Output tersimpan di: $OUT"
