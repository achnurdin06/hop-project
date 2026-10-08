# Dokumen PRD (Product Requirements Document)
## Sistem ETL & Migrasi Data (SQL Server → PostgreSQL) | Apache Hop

---

## 1. Latar Belakang & Tujuan Produk

### 1.1 Latar Belakang
Organisasi melakukan migrasi data master dan transaksi dari legacy database **Microsoft SQL Server** ke database **PostgreSQL**. Diperlukan sebuah sistem ETL (*Extract, Transform, Load*) yang andal, efisien, memiliki fleksibilitas tinggi, serta dilengkapi dengan mekanisme pengawasan (*auditability*), keamanan data (*data safety*), dan pemulihan bencana (*rollback & purge capability*).

### 1.2 Tujuan Produk
1. **Otomatisasi Migrasi**: Mengotomatisasi penarikan, konversi kode master, penyesuaian penomoran ID (LPAD 8-digit), dan posting data ke multi-tabel target.
2. **Kinerja & Skalabilitas (Batching)**: Menyediakan pilihan eksekusi secara **Batch (Chunked)** untuk mencegah *OOM* dan *lock timeout* pada dataset besar.
3. **Auditability & Traceability**: Mencatat seluruh sesi eksekusi, langkah granular, dan diagnostik kesalahan secara lengkap.
4. **Data Safety & Integrity**: Mencegah penghapusan atau kerusakan pada data non-migrasi / produksi melalui guard validation yang ketat.

---

## 2. Ruang Lingkup Produk (Product Scope)

### In-Scope:
- Ekstraksi data dari SQL Server View `dbo.v_migration_vendor`.
- Pendaratan data ke Staging PostgreSQL `stg_antam.stg_vendors_src`.
- Otomatisasi pembentukan ID vendor LPAD 8-digit (melanjutkan seed `1031` → `00001032`).
- Konversi kode master berbasis tabel lookup `migration_lookup` & `migration_convert_rule`.
- Posting multi-target ke `vendor.slave_vendors` (18 kolom) dan `vendor.vendors` (14 kolom).
- Mode posting **Batch (`USE_BATCH = 'Y'`)** dan **Direct (`USE_BATCH = 'N'`)** dengan parameter wajib **`RUN_ID`**.
- Pencatatan mode posting pada kolom **`post_type`** (`BATCH (1000)` / `DIRECT`) di `migration_run`.
- **Single-Record Lifecycle**: Satu siklus hidup migrasi utuh (Staging -> Posting -> Rollback) tercatat dalam **1 baris data tunggal** di `migration_run`.
- **Penyederhanaan Status**: Status di `migration_run` distandarisasi hanya ada 3 nilai: **`RUNNING`**, **`SUCCESS`**, dan **`FAILED`**.
- Fitur Rollback berbasis **Guard Protection** yang mengupdate baris `RUN_ID` yang sama menjadi `is_rolled_back = true` tanpa membuat run baru.
- Guard Validasi: Menolak posting duplikat (`ALREADY_POSTED`), menolak posting sesi rollback (`ALREADY_ROLLED_BACK`), dan menolak rollback yang belum diposting (`NOT_POSTED_YET`).
- Fitur Purge Data Target khusus data migrasi (`migration = '1'`) tanpa menghapus data produksi.

### Out-of-Scope:
- Migrasi tabel di luar konfigurasi yang terdaftar pada `migration_config`.
- Real-time CDC (*Change Data Capture*) continuous streaming.

---

## 3. Kebutuhan Fungsional (Functional Requirements)

### FR-1: Penyiapan Staging & LPAD ID Generation
- **Deskripsi**: Sistem harus dapat membuat tabel staging `stg_antam.<stg_table>_src` secara otomatis, melepaskan constraint NOT NULL untuk pendaratan data awal, dan membentuk sequence ID LPAD 8-digit otomatis berdasarkan seed terbesar di target.
- **Kriteria Menerima**: ID terisi secara berurutan dengan format 8 digit (contoh: `00001032`).

### FR-2: Engine Konversi Kode Master (`fn_convert_codes`)
- **Deskripsi**: Sistem harus mengonversi kode master sumber ke ID target berbasis kamus `migration_lookup`.
- **Kriteria Menerima**: Jika kode tidak ditemukan dan aturan `on_unmapped = 'FAIL'`, sistem memicu error dan menghentikan proses.

### FR-3: Multi-Target Data Dispatch (`fn_post_all_targets`)
- **Deskripsi**: Data staging harus diposting ke beberapa tabel target sesuai urutan eksekusi (`exec_order`) pada `migration_target_config`.
- **Kriteria Menerima**: Data masuk ke `vendor.slave_vendors` (order 1) dan `vendor.vendors` (order 2) secara akurat.

### FR-4: Parameterisasi Batching & Direct Post (`wf_post.hwf`)
- **Deskripsi**: Parameter `RUN_ID` (wajib), `USE_BATCH` (`Y`/`N`), dan `BATCH_SIZE` (default `1000`) wajib terdefinisi pada `wf_post.hwf`.
- **Aturan Validasi & Guard**:
  - `RUN_ID` belum terisi / tidak valid -> Error.
  - Sesi `RUN_ID` sudah pernah di-rollback -> Error `ALREADY_ROLLED_BACK`.
  - Sesi `RUN_ID` sudah pernah diposting -> Error `ALREADY_POSTED`.
  - `p_use_batch` & `p_batch_size` keduanya kosong -> Error `INVALID_PARAMETER`.
  - `p_use_batch = 'N'` -> Direct Insert (tanpa error jika p_batch_size kosong).
  - `p_use_batch = 'Y'` -> Batch Insert (p_batch_size wajib > 0; jika kosong -> Error `INVALID_BATCH_SIZE`).
- **Kriteria Menerima**: Berhasil memposting data, menandai `is_posted = true`, `posted_at = now()`, mengisi `post_type` (`BATCH (1000)` / `DIRECT`), dan status tetap `SUCCESS`.

### FR-5: Audit Trail & Single-Record Lifecycle (`migration_run`)
- **Deskripsi**: Setiap siklus migrasi (Staging -> Posting -> Rollback) tercatat dalam 1 baris data tunggal pada `migration_run`.
- **Kriteria Menerima**: 
  - Status hanya menggunakan 3 nilai resmi: `RUNNING`, `SUCCESS`, atau `FAILED`.
  - Riwayat langkah granular dicatat di `migration_step_log`.
  - Detail diagnostik kesalahan dicatat di `migration_error_log`.
  - Seluruh kolom metadata status (`is_posted`, `post_type`, `is_rolled_back`, `rolled_back_at`) terkelola secara otomatis.

### FR-6: Single-Record Safe Rollback Engine (`wf_rollback.hwf`)
- **Deskripsi**: Sistem dapat membatalkan dan menghapus data target yang pernah diposting oleh sesi `RUN_ID` tertentu.
- **Kriteria Menerima**: 
  - Parameter wajib adalah `RUN_ID`.
  - Jika sesi belum pernah diposting -> Ditolak dengan error `NOT_POSTED_YET`.
  - Jika sesi sudah pernah di-rollback -> Ditolak dengan error `ALREADY_ROLLED_BACK`.
  - Menghapus data pada seluruh tabel target yang diposting oleh `RUN_ID` tersebut.
  - Mengupdate record `RUN_ID` yang sama menjadi `is_rolled_back = true`, `rolled_back_at = now()`, dan status tetap `SUCCESS` (tidak membuat baris run baru).

### FR-7: Purge Data Target Migrasi (`wf_purge_target.hwf`)
- **Deskripsi**: Sistem dapat menghapus data hasil migrasi pada tabel target (baik single/multiple ID maupun all tables).
- **Kriteria Menerima**: Jika ID yang di-input bukan data migrasi (`migration <> 1` atau tidak ada di staging), sistem membatalkan penghapusan dan mencatat error `NOT_MIGRATION_DATA`. Data produksi non-migrasi tetap utuh.

---

## 4. Kebutuhan Non-Fungsional (Non-Functional Requirements)

1. **Performance & Scalability**:
   - Mampu memproses puluhan ribu baris data tanpa memicu *Memory Exhaustion (OOM)* menggunakan mode batch (`USE_BATCH = 'Y'`, `BATCH_SIZE = 1000`).
2. **Reliability & Idempotency**:
   - Script SQL dan pipeline Hop dapat dijalankan berulang kali tanpa menyebabkan duplikasi data (menggunakan `REPLACE ON CONFLICT` dan `LEFT JOIN ... WHERE target.pk IS NULL`).
3. **Maintainability**:
   - Seluruh fungsi database terenkapsulasi di dalam skema `etl_antam` dan dikelola melalui script SQL terpadu `sql/01_ddl_and_functions.sql`.

---
