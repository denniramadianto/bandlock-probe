# bandlock-probe

Alat probe **read-only** untuk riset aplikasi BandLock di Redmi 4X (santoni):
membaca kondisi modem Qualcomm (layanan QMI, preferensi jaringan/band,
kapabilitas band) lewat daemon qmuxd. Tidak menulis apa pun ke modem.

## Cara pakai (di HP, via Termux)

Sekali saja — unduh penjalannya:

```sh
mkdir -p /sdcard/bandlock-probe && curl -L https://raw.githubusercontent.com/denniramadianto/bandlock-probe/main/run.sh -o /sdcard/bandlock-probe/run.sh
```

Setelah itu, tiap menjalankan probe cukup:

```sh
sh /sdcard/bandlock-probe/run.sh
```

`run.sh` mengunduh `bandlock-ro` + `probe-core.sh` versi terbaru dari repo
ini, menjalankannya sebagai root (`su`), dan menyimpan hasil ke
`/sdcard/bandlock-probe/hasil-probe.txt`.

## Isi repo

- `run.sh` — pengunduh + penjalan otomatis (dijalankan dari Termux, tanpa su)
- `probe-core.sh` — skrip probe utama (dijalankan sebagai root oleh run.sh)
- `bandlock-ro` — helper native ARM64 (static), murni baca:
  CTL GET_VERSION_INFO, NAS GET_SYSTEM_SELECTION_PREFERENCE,
  DMS GET_BAND_CAPABILITIES via qmuxd

Bagian dari proyek BandLock (aplikasi pengatur band & RAT untuk Redmi 4X).
