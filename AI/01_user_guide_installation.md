# Dokumen User Guide & Panduan Instalasi (User & Installation Guide)
## Sistem ETL & Migrasi Data (SQL Server → PostgreSQL) | Apache Hop

---

## 1. Pendahuluan & Gambaran Umum

Sistem ETL & Migrasi Data ini dirancang untuk melakukan migrasi data secara otomatis, terstruktur, dan aman dari database sumber **Microsoft SQL Server** ke database target **PostgreSQL**.

Sistem ini mendukung:
- **Flow 1 (Extraction & Staging)**: Penarikan data dari SQL Server View (`dbo.v_migration_vendor`), pendaratan data ke Staging PostgreSQL (`stg_antam.stg_vendors_src`), otomatisasi pembuatan ID LPAD 8-digit (`00001031`), konversi kode master, dan penghitungan delta data baru vs eksisting. Menghasilkan sesi baru di `migration_run` dengan status `SUCCESS` dan flag `is_posted = false`.
- **Flow 2 (Multi-Target Post)**: Posting data hasil konversi dari staging ke tabel-tabel target utama (`vendor.slave_vendors` dan `vendor.vendors`) secara **Direct** atau **Batch (Chunked)** berdasarkan parameter wajib **`RUN_ID`**. Mencatat mode di kolom **`post_type`** (`BATCH (1000)` / `DIRECT`) dan menandai `is_posted = true` pada baris yang sama.
- **Flow 3 (Single-Record Safe Rollback Engine)**: Pembatalan/penghapusan data migrasi spesifik pada baris **`RUN_ID` yang sama** tanpa membuat record run baru. Melindungi integritas data dengan guard anti-duplicate dan menandai `is_rolled_back = true`.
- **Flow 4 (Purge Target Engine)**: Penghapusan data hasil migrasi pada tabel target (baik single/multiple ID maupun batch all tables) secara otomatis tanpa menghapus data non-migrasi / produksi.
- **Audit & Diagnostics (Single-Record Lifecycle)**: Seluruh siklus hidup migrasi (Staging -> Posting -> Rollback) tercatat dalam **1 baris data tunggal** di `migration_run`. Status distandarisasi hanya ada 3 nilai: **`RUNNING`**, **`SUCCESS`**, dan **`FAILED`**. Log granular dicatat di `migration_step_log`, dan log kesalahan diagnostik di `migration_error_log`.

---

## 2. Prasyarat Sistem (Prerequisites)

### 2.1 Software & Infrastructure Requirement
- **Apache Hop Client / Server**: Versi 2.5.0+ / 2.8.0+
- **Java Runtime Environment (JRE/JDK)**: Java 11 atau Java 17 (64-bit)
- **Database Sumber (MSSQL)**: Microsoft SQL Server 2012+ dengan JDBC Driver (`mssql-jdbc-12.x.x.jre11.jar`)
- **Database Target (PostgreSQL)**: PostgreSQL 11+ dengan extension `uuid-ossp` dan JDBC Driver (`postgresql-42.x.x.jar`)

### 2.2 Koneksi Database Required
- **`MSSQL_SRC`**: Database SQL Server (Schema `dbo`, Access Read-Only ke view `v_migration_vendor`)
- **`PG_TGT`**: Database PostgreSQL Target (Schema `etl_antam`, `stg_antam`, `vendor`)

---

## 3. Panduan Instalasi & Konfigurasi

### Langkah 1: Setup Database PostgreSQL Target
1. Buka tool query PostgreSQL (pgAdmin, DBeaver, psql).
2. Sambungkan ke database target (contoh DB: `db_procsi`).
3. Jalankan script SQL gabungan idempotent:
   ```bash
   psql -h <host> -U <user> -d <dbname> -f sql/01_ddl_and_functions.sql
   ```
4. Pastikan skema `etl_antam`, `stg_antam`, tabel `migration_run`, dan tabel `vendor.slave_vendors`, `vendor.vendors` berhasil dibuat.

### Langkah 2: Konfigurasi Project Apache Hop
1. Buka **Apache Hop GUI** (`hop-gui.sh` / `hop-gui.bat`).
2. Open Project: Pilih direktori folder proyek `hop-project` dengan lifecycle environment terkait (misal: `ETL-ANTAM-V1-development`).
3. Buka menu **Metadata** -> **Relational Database Connection**:
   - Edit koneksi **`MSSQL_SRC`**: Sesuaikan Hostname, Port (`1433`), DB Name, Username, dan Password.
   - Edit koneksi **`PG_TGT`**: Sesuaikan Hostname, Port (`5433` / `5432`), DB Name, Username, dan Password.
4. Tes kedua koneksi dengan mengklik tombol **Test Connection** hingga bernilai *OK Success*.

---

## 4. Petunjuk Penggunaan Workflow (User Guide)

### 4.1 Menjalankan Migrasi Utama (`workflows/wf_main.hwf`)
Workflow ini mengeksekusi **Flow 1** (Ekstraksi, Staging, Konversi Kode, dan Delta Check).

1. Buka workflow `workflows/wf_main.hwf`.
2. Klik tombol **Run Workflow** (▶).
3. Parameter:
   - **`CONFIG_ID`** (Wajib): Masukkan ID konfigurasi yang akan diproses (contoh: `1` atau `1,2`).
4. Hasil eksekusi akan membuat baris baru di `etl_antam.migration_run` dengan status `SUCCESS`, `is_posted = false`, `post_type = NULL`, dan `is_rolled_back = false`. Catat nilai **`run_id`** yang dihasilkan (misal `#146`) untuk tahapan posting.

---

### 4.2 Menjalankan Posting Data Target (`workflows/wf_post.hwf`)
Workflow ini mengeksekusi **Flow 2** (Memindahkan data dari Staging ke Tabel Main Target berdasarkan `RUN_ID`).

1. Buka workflow `workflows/wf_post.hwf`.
2. Isi Parameter Workflow:
   - **`RUN_ID`** (Wajib): Masukkan ID sesi migrasi dari hasil `wf_main` (contoh: `146`).
   - **`USE_BATCH`**: 
     - `'Y'` (Default) = Mode Batch (Posting bertahap per chunk).
     - `'N'` = Mode Direct (Posting langsung 1 transaksi).
   - **`BATCH_SIZE`**: 
     - `'1000'` (Default) = Jumlah baris per batch saat `USE_BATCH = 'Y'`.
3. Klik **Run Workflow**.
4. Sistem menjalankan validasi ketat (*Guard Protection*):
   - Jika `RUN_ID` belum pernah dibuat / kosong -> **Error**.
   - Jika sesi `RUN_ID` sudah pernah di-rollback -> **Error** (`ALREADY_ROLLED_BACK`).
   - Jika sesi `RUN_ID` sudah pernah diposting sebelumnya -> **Error** (`ALREADY_POSTED`) untuk mencegah data duplikat.
   - Jika lolos validasi -> Data diposting, kolom `is_posted` menjadi `true`, `post_type` terisi (`BATCH (1000)` atau `DIRECT`), dan status tetap `SUCCESS`.

---

### 4.3 Menjalankan Rollback Sesi (`workflows/wf_rollback.hwf`)
Workflow ini digunakan untuk membatalkan/menghapus data target yang sudah ter-post pada baris **`RUN_ID` yang sama**.

1. Buka workflow `workflows/wf_rollback.hwf`.
2. Isi Parameter:
   - **`RUN_ID`** (Wajib): Masukkan `run_id` sesi migrasi yang ingin di-rollback (contoh: `146`).
3. Klik **Run Workflow**.
4. Sistem memverifikasi kondisi data (*Guard Protection*):
   - Jika sesi `RUN_ID` belum pernah diposting (`is_posted = false`) -> **Ditolak** (`NOT_POSTED_YET`).
   - Jika sesi `RUN_ID` sudah pernah di-rollback (`is_rolled_back = true`) -> **Ditolak** (`ALREADY_ROLLED_BACK`).
   - Jika lolos validasi -> Menghapus baris data migrasi di tabel target, memperbarui record `RUN_ID` yang sama menjadi `is_rolled_back = true`, mengisi `rolled_back_at`, dan status tetap `SUCCESS`. **Tidak ada baris run baru yang dibuat**.

---

### 4.4 Menjalankan Purge Data Target (`workflows/wf_purge_target.hwf`)
Workflow ini digunakan untuk menghapus data target hasil migrasi tanpa menghapus data produksi/non-migrasi.

1. Buka workflow `workflows/wf_purge_target.hwf`.
2. Isi Parameter:
   - **`CONFIG_ID`**: ID Konfigurasi tabel (misal: `1`).
   - **`DELETE_IDS`**: 
     - Kosongkan = Menghapus seluruh data migrasi di tabel target.
     - Single / Multiple ID = Contoh `'1031'` atau `'1031,1032'`.
3. Klik **Run Workflow**.
4. Proteksi Keamanan Data:
   - Jika ID yang di-input memiliki flag `migration <> 1` atau tidak ada di staging -> **Dibatalkan & Error** (`NOT_MIGRATION_DATA`). Data non-migrasi tetap aman.

---

## 5. Troubleshooting & Maintenance

| Pertanyaan / Error | Diagnosis | Solusi |
|---|---|---|
| `PSQLException: No results were returned by the query` pada pipeline init | JDBC `executeQuery()` menerima statement DML tanpa CTE | Pastikan query di `pl_init_run.hpl` menggunakan `WITH ins AS (INSERT INTO ...) SELECT ... FROM ins`. |
| Error `ALREADY_POSTED` saat posting target | `RUN_ID` tersebut sudah pernah diposting sebelumnya | Posting ulang ditolak demi mencegah duplikasi. Jika data ingin diisi ulang, lakukan rollback terlebih dahulu lalu mulai siklus baru dari `wf_main.hwf`. |
| Error `NOT_POSTED_YET` saat rollback | `RUN_ID` tersebut baru tahap staging dan belum diposting ke target | Rollback hanya berlaku untuk data yang sudah ter-post (`is_posted = true`). |
| Error `ALREADY_ROLLED_BACK` saat posting atau rollback | `RUN_ID` tersebut sudah pernah di-rollback | 1 siklus migrasi telah selesai. Silakan buat sesi migrasi baru dengan menjalankan `wf_main.hwf`. |
| Error `INVALID_BATCH_SIZE` saat posting target | Parameter `USE_BATCH = 'Y'` tetapi `BATCH_SIZE` kosong | Isi `BATCH_SIZE` dengan angka > 0 (contoh: `1000`). |
| Error `NOT_MIGRATION_DATA` saat purge data | Terdeteksi ID yang akan dihapus bukan data migrasi | Pastikan ID yang hendak dihapus merupakan data hasil migrasi (`migration = '1'`). |

---
