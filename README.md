# Drople — Offline-First Activity & P2P Manager

Drople adalah aplikasi pengelola aktivitas dan catatan multi-platform (Android, Linux, Windows, macOS) berbasis **offline-first**. Aplikasi ini memungkinkan sinkronisasi catatan dan transfer file antar-perangkat secara langsung (**Peer-to-Peer**) tanpa ketergantungan pada server cloud terpusat, dengan opsi backup terenkripsi end-to-end (E2EE) ke Google Drive milik pengguna.

![P2P Architecture](P2P.jpg)

---

## Fitur Utama

- **Offline-First & Local Storage:** SQLite lokal dengan migrasi otomatis dan write-ahead logging (WAL).
- **P2P Discovery & Pairing:** Penemuan lokal otomatis via mDNS + pairing kode/QR (`DRO1:`) dengan verifikasi fingerprint SHA-256.
- **Sinkronisasi CRDT:** Merge catatan tanpa konflik menggunakan Last-Write-Wins (LWW) delta protocol melalui jaringan libp2p.
- **Transfer File P2P:** Pengiriman file terpecah dalam potongan 64 KiB dengan validasi hash SHA-256 tiap potongan dan verifikasi akhir.
- **End-to-End Encryption (E2EE):**
  - Komunikasi P2P dienkripsi via Noise Protocol (libp2p).
  - Snapshot backup dienkripsi di perangkat menggunakan **XChaCha20-Poly1305** dan kunci turunan **Argon2id** dari 12 kata mnemonic recovery key.
- **Zero-Knowledge Cloud Backup:** Unggah snapshot biner (`DRPL1`) langsung ke `appDataFolder` tersembunyi di akun Google Drive pribadi pengguna. Google tidak dapat membaca isi catatan.

---

## Struktur Repositori

```
drople/
├── core/                  # Rust Core Engine (P2P, SQLite, Kripto, Backup, FFI)
│   ├── Cargo.toml
│   └── src/
│       ├── backup/        # Google Drive v3 REST & snapshot biner
│       ├── crypto/        # XChaCha20-Poly1305, Argon2id, SHA-256
│       ├── db.rs          # Schema SQLite, CRUD, migrasi kolom
│       ├── ffi.rs         # Antarmuka C FFI untuk Flutter
│       ├── file/          # Chunking & transfer manager
│       ├── net/           # libp2p node, mDNS, relay, wire protocol
│       └── sync/          # CRDT LWW merge & delta exchange
├── app/                   # Flutter App (UI & Platform Integration)
│   ├── lib/
│   │   ├── ffi/           # Low-level Dart FFI bindings
│   │   ├── models/        # Data model (Note, Peer, FileTransfer, Backup)
│   │   ├── screens/       # Notes, Peers/Sync, Files, Backup/Cloud
│   │   ├── services/      # Service wrapper tingkat tinggi
│   │   └── widgets/       # Pairing dialog (QR & kode)
│   └── native/            # Binary libdrople_core hasil kompilasi
├── docs/
│   └── FASE/              # Laporan & roadmap fase 1 s.d. 7
└── scripts/
    └── build_core.sh      # Skrip kompilasi otomatis Rust core -> Flutter native
```

---

## Panduan Membangun (Build) & Menjalankan

### Prasyarat
- Rust Toolchain 1.85+ (`rustc`, `cargo`)
- Flutter SDK 3.12+ / Dart 3.12+
- `libsqlite3` (atau gunakan bawaan bundled)

### 1. Kompilasi Rust Core
Gunakan skrip yang disediakan untuk mengkompilasi library C-shared dan menempatkannya ke direktori native Flutter:

```bash
# Debug build
./scripts/build_core.sh debug

# Release build (direkomendasikan)
./scripts/build_core.sh release
```

Output binary:
- Linux: `app/native/libdrople_core.so`
- macOS: `app/native/libdrople_core.dylib`
- Windows: `app/native/drople_core.dll`

### 2. Menjalankan Unit Tests

**Rust Core:**
```bash
cd core
cargo test
```

**Flutter App:**
```bash
cd app
flutter test
flutter analyze
```

### 3. Menjalankan Aplikasi Flutter

```bash
cd app
flutter run -d linux # atau android / windows / macos
```

---

## Status Pengembangan (Fase 1–7)

- [x] **FASE 1:** Inisialisasi arsitektur, SQLite schema dasar, FFI awal, dan UI Catatan.
- [x] **FASE 2:** P2P Identity Ed25519, mDNS discovery, Swarm, dan Relay Client.
- [x] **FASE 3:** CRDT delta synchronization protocol dan status tracking per-catatan.
- [x] **FASE 4:** Chunking file 64 KiB, wire messaging libp2p, dan manajemen riwayat transfer file.
- [x] **FASE 5:** Pairing code autentik (`DRO1:`), visual fingerprint SHA-256, dan modul kriptografi XChaCha20-Poly1305.
- [x] **FASE 6:** Zero-knowledge Google Drive backup (`DRPL1`), 12 kata mnemonic recovery key, dan CRDT restore.
- [x] **FASE 7:** Integrasi final, UI polish (Files & Backup screen), bebas warning/error, dan sinkronisasi dokumentasi rilis.

---

## Lisensi
Proyek privat / mandiri oleh Virza.
