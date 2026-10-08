# Sistem ETL & Migrasi Data (SQL Server ➔ PostgreSQL)
## Apache Hop Orchestration & Metadata-Driven Architecture

Repository ini berisi implementasi sistem migrasi data otomatis, terstruktur, dan aman dari **Microsoft SQL Server** ke **PostgreSQL** menggunakan **Apache Hop** dan stored procedure/function PL/pgSQL.

---

## 🚀 Fitur Utama & 4 Core Workflows

1. **Flow 1: Landing Staging & Transformation (`workflows/wf_main.hwf`)**
   - Penarikan data dari SQL Server View (`dbo.v_migration_vendor`) ke PostgreSQL Staging (`stg_antam.stg_vendors_src`).
   - Otomatisasi pembentukan ID LPAD 8-digit (`00001031`).
   - Konversi kode master dinamis via `vw_convert_rule` & kamus lookup.
   - Deteksi delta data baru vs data eksisting.
   - Mencatat sesi baru di `etl_antam.migration_run` dengan status `SUCCESS` dan `is_posted = false`.

2. **Flow 2: Multi-Target Posting Engine (`workflows/wf_post.hwf`)**
   - Memposting data dari staging ke tabel-tabel target utama (`vendor.slave_vendors` dan `vendor.vendors`).
   - Wajib parameter: `RUN_ID`, `USE_BATCH` (`'Y'`/`'N'`), dan `BATCH_SIZE` (default `1000`).
   - Proteksi Guard: Menolak double posting (`ALREADY_POSTED`) dan menolak posting sesi rollback (`ALREADY_ROLLED_BACK`).
   - Mencatat mode di `post_type` (`BATCH (1000)` / `DIRECT`) dan menandai `is_posted = true`.

3. **Flow 3: Single-Record Safe Rollback Engine (`workflows/wf_rollback.hwf`)**
   - Pembatalan/penghapusan data target migrasi pada baris **`RUN_ID` yang sama** tanpa membuat record run baru.
   - Proteksi Guard: Menolak rollback jika belum diposting (`NOT_POSTED_YET`) dan menolak rollback berulang (`ALREADY_ROLLED_BACK`).
   - Memperbarui baris tersebut: `is_rolled_back = true`, `rolled_back_at = now()`, dan status tetap `SUCCESS`.

4. **Flow 4: Target Purge Engine (`workflows/wf_purge_target.hwf`)**
   - Menghapus data migrasi pada tabel target (single ID, multiple ID, atau all data).
   - **Dual-Guard Protection**: Memastikan data yang dihapus ber-flag `migration = '1'` dan ada di staging. Data produksi non-migrasi dijamin 100% aman (`NOT_MIGRATION_DATA`).

---

## 📁 Struktur Direktori

```text
├── AI/                     # Dokumentasi teknis & panduan lengkap
│   ├── 01_user_guide_installation.md     # Panduan Instalasi & Pengguna
│   ├── 02_technical_specification.md     # Spesifikasi Teknis & Arsitektur
│   ├── 03_prd_product_requirements.md    # Product Requirements Document (PRD)
│   ├── 04_uat_test_cases.md              # 11 Skenario Pengujian UAT
│   ├── 05_configuration_guide.md         # Panduan Master Konfigurasi Metadata
│   └── 06_presentation_guide.md          # Panduan & Naskah Presentasi 45 Menit
├── config/                 # Konfigurasi environment & variables
├── metadata/               # Konfigurasi RDBMS & Run Configuration Apache Hop
├── pipelines/              # Pipeline Hop (.hpl)
├── sql/                    # Skrip DDL, fungsi PL/pgSQL & initial seed
└── workflows/              # Workflow Hop (.hwf)
```

---

## 🛠️ Prasyarat & Menjalankan

- **Apache Hop**: 2.5.0+ / 2.8.0+
- **PostgreSQL**: 11+
- **SQL Server**: 2012+
- DDL & Database Setup: Jalankan `sql/01_ddl_and_functions.sql` pada database target PostgreSQL.
