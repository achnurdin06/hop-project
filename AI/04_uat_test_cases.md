# Dokumen UAT (User Acceptance Testing & Test Cases)
## Sistem ETL & Migrasi Data (SQL Server → PostgreSQL) | Apache Hop

---

## 1. Lembar Persetujuan UAT (UAT Sign-Off Sheet)

- **Nama Proyek**: Sistem ETL & Migrasi Data Vendor (SQL Server ke PostgreSQL)
- **Modul**: Ekstraksi Staging, Multi-Target Post Batch/Direct, Safe Rollback, dan Purge Data Target
- **Tanggal Pengujian**: 7 Oktober 2026
- **Lingkungan Pengujian**: Staging / UAT Environment (`PG_TGT` PostgreSQL 11+)

---

## 2. Matriks Skenario Pengujian (Test Case Matrix)

| Test Case ID | Nama Skenario Pengujian | Target Komponen | Ekspektasi Hasil | Status |
|---|---|---|---|---|
| **TC-01** | Ekstraksi, Landing Staging & Code Conversion | `wf_main.hwf` | Data mendarat di staging, kode terkonversi, LPAD ID terbentuk (`00001031`), delta dihitung. Status `SUCCESS`, `is_posted = false`. | PASSED |
| **TC-02** | Target Posting Mode Batch (`USE_BATCH = 'Y'`) | `wf_post.hwf` | Data diposting bertahap per batch (misal 100 baris/batch). `is_posted = true`, `post_type = 'BATCH (100)'`, status `SUCCESS`. | PASSED |
| **TC-03** | Target Posting Mode Direct (`USE_BATCH = 'N'`) | `wf_post.hwf` | Data diposting sekaligus 1 transaksi. `is_posted = true`, `post_type = 'DIRECT'`, status `SUCCESS`. | PASSED |
| **TC-04** | Validasi Error Batch Size Kosong | `wf_post.hwf` | Parameter `USE_BATCH = 'Y'` dan `BATCH_SIZE = ''` memicu error `INVALID_BATCH_SIZE`. Sesi ditandai `FAILED`. | PASSED |
| **TC-05** | Proteksi Anti Double Posting | `wf_post.hwf` | Menjalankan posting kedua kali pada `RUN_ID` yang sama ditolak dengan error `ALREADY_POSTED`. | PASSED |
| **TC-06** | Purge Target Data ID Spesifik Migrasi | `wf_purge_target.hwf` | Menghapus ID migrasi `'1031'` dari `vendor.slave_vendors` & `vendor.vendors`. | PASSED |
| **TC-07** | Ditolaknya Purge Data Non-Migrasi / Produksi | `wf_purge_target.hwf` | ID non-migrasi ditolak. Menghasilkan error `NOT_MIGRATION_DATA` di `migration_error_log`. Data produksi utuh. | PASSED |
| **TC-08** | Rollback Sesi Migrasi Sukses (Single-Record) | `wf_rollback.hwf` | Menghapus data target pada baris `RUN_ID` yang sama. Record di-update `is_rolled_back = true`, status tetap `SUCCESS`, tanpa baris run baru. | PASSED |
| **TC-09** | Proteksi Rollback Berulang (Token Guard) | `wf_rollback.hwf` | Pengulangan rollback pada `RUN_ID` yang sudah di-rollback ditolak dengan error `ALREADY_ROLLED_BACK`. | PASSED |
| **TC-10** | Proteksi Rollback Sesi Belum Diposting | `wf_rollback.hwf` | Mencoba rollback pada sesi yang masih staging (`is_posted = false`) ditolak dengan error `NOT_POSTED_YET`. | PASSED |
| **TC-11** | Proteksi Posting Sesi yang Telah Di-Rollback | `wf_post.hwf` | Mencoba posting pada sesi yang sudah di-rollback ditolak dengan error `ALREADY_ROLLED_BACK`. | PASSED |

---

## 3. Detail Rincian Skenario & Langkah Pengujian

### TC-01: Ekstraksi & Landing Staging (`wf_main.hwf`)
- **Langkah**:
  1. Eksekusi `wf_main.hwf` dengan parameter `CONFIG_ID = 1`.
  2. Buka pgAdmin / psql, jalankan query verifikasi:
     ```sql
     SELECT count(*), min(id), max(id) FROM stg_antam.stg_vendors_src;
     SELECT run_id, status, is_posted, post_type, is_rolled_back, note 
       FROM etl_antam.migration_run ORDER BY run_id DESC LIMIT 1;
     ```
- **Kriteria Keberhasilan**: Status `migration_run` = `SUCCESS`, `is_posted = false`, `post_type IS NULL`, data staging terisi lengkap. Catat `run_id` (misal `#146`).

---

### TC-02: Target Posting Mode Batch (`wf_post.hwf`, `RUN_ID = 146`, `USE_BATCH = 'Y'`, `BATCH_SIZE = '100'`)
- **Langkah**:
  1. Jalankan `wf_post.hwf` dengan parameter `RUN_ID = 146`, `USE_BATCH = 'Y'`, dan `BATCH_SIZE = '100'`.
  2. Periksa entri log pada `migration_step_log` dan `migration_run`:
     ```sql
     SELECT step_name, status, rows_before, rows_after, rows_new, message 
       FROM etl_antam.migration_step_log 
      WHERE run_id = 146 AND step_name = 'POST_TARGET' 
      ORDER BY log_id DESC;

     SELECT run_id, status, is_posted, posted_at, post_type, note 
       FROM etl_antam.migration_run WHERE run_id = 146;
     ```
- **Kriteria Keberhasilan**: 
  - Data masuk sempurna ke `vendor.slave_vendors` dan `vendor.vendors`. 
  - Kolom `is_posted` bernilai `true`, `post_type` bernilai `'BATCH (100)'`, dan status tetap `SUCCESS`.
  - Pada `migration_step_log`: Kolom `rows_before` dan `rows_after` terisi angka count aktual, `rows_new` = `rows_after - rows_before`, serta pesan berformat `Sebelum=X, Sesudah=Y, Selisih=+Z baris`.
  - Pada `migration_run.note`: Merangkum total baris yang bertambah beserta rincian per target table (`total +... baris diposting [...]`).

---

### TC-03: Target Posting Mode Direct (`wf_post.hwf`, `RUN_ID = 146`, `USE_BATCH = 'N'`)
- **Langkah**:
  1. Jalankan `wf_post.hwf` dengan parameter `RUN_ID = 146` dan `USE_BATCH = 'N'`.
  2. Periksa entri log pada `migration_step_log`:
     ```sql
     SELECT step_name, status, rows_before, rows_after, rows_new, message 
       FROM etl_antam.migration_step_log 
      WHERE run_id = 146 AND step_name = 'POST_TARGET' 
      ORDER BY log_id DESC;
     ```
- **Kriteria Keberhasilan**: Workflow berjalan sukses tanpa error validasi parameter. Kolom `is_posted` bernilai `true`, `post_type` bernilai `'DIRECT'`, status tetap `SUCCESS`. Kolom `rows_before`, `rows_after`, dan `rows_new` terisi audit count yang akurat.

---

### TC-04: Validasi Parameter Error (`USE_BATCH = 'Y'`, `BATCH_SIZE = ''`)
- **Langkah**:
  1. Jalankan `wf_post.hwf` dengan parameter `RUN_ID = 146`, `USE_BATCH = 'Y'`, dan `BATCH_SIZE` sengaja dikosongkan.
- **Kriteria Keberhasilan**: Workflow berhenti pada Hop error path (`Mark run failed` → `Abort`). Query `migration_error_log` memuat:
  - `error_code` = `'INVALID_BATCH_SIZE'`
  - `error_message` = `'Untuk mode batch (USE_BATCH = Y), parameter BATCH_SIZE wajib diisi dengan angka > 0'`.

---

### TC-05: Proteksi Anti Double Posting (`wf_post.hwf`)
- **Langkah**:
  1. Jalankan kembali `wf_post.hwf` dengan `RUN_ID = 146` yang sebelumnya sudah berstatus `is_posted = true`.
- **Kriteria Keberhasilan**: Workflow memicu validasi guard `fn_validate_post_trigger`. Proses berhenti dengan error `ALREADY_POSTED` (*"Run ID #146 sudah pernah diposting sebelumnya"*). Data target tidak terduplikasi.

---

### TC-06: Purge Data Target Single ID (`wf_purge_target.hwf`, `DELETE_IDS = '1031'`)
- **Langkah**:
  1. Masukkan parameter `CONFIG_ID = 1` dan `DELETE_IDS = '1031'` pada `wf_purge_target.hwf`.
  2. Jalankan workflow.
- **Kriteria Keberhasilan**: Data vendor dengan ID `'1031'` terhapus dari `vendor.slave_vendors` dan `vendor.vendors`. Entri `migration_step_log` mencatat `PURGE_TARGET` `OK`.

---

### TC-07: Proteksi Data Non-Migrasi saat Purge (`wf_purge_target.hwf`, `DELETE_IDS = '<PROD_ID>'`)
- **Langkah**:
  1. Masukkan ID data produksi/non-migrasi (misal ID dengan `migration = '0'` atau tidak ada di staging).
  2. Jalankan `wf_purge_target.hwf`.
- **Kriteria Keberhasilan**: Penghapusan dibatalkan. Data produksi tetap utuh di database target. Tabel `migration_error_log` mencatat error `NOT_MIGRATION_DATA`.

---

### TC-08: Rollback Sesi Migrasi Sukses (Single-Record Lifecycle) (`wf_rollback.hwf`)
- **Langkah**:
  1. Eksekusi `wf_rollback.hwf` dengan parameter `RUN_ID = 146`.
  2. Buka database target dan periksa `migration_run` serta `migration_step_log`:
     ```sql
     SELECT run_id, status, is_posted, is_rolled_back, rolled_back_at, note 
       FROM etl_antam.migration_run WHERE run_id = 146;

     SELECT step_name, status, rows_before, rows_after, rows_deleted, message 
       FROM etl_antam.migration_step_log 
      WHERE run_id = 146 AND step_name = 'ROLLBACK_TARGET' 
      ORDER BY log_id DESC;
     ```
- **Kriteria Keberhasilan**: 
  - Data hasil posting `RUN_ID = 146` terhapus dari `vendor.slave_vendors` dan `vendor.vendors`.
  - Record `RUN_ID = 146` yang sama diperbarui: `is_rolled_back = true`, `rolled_back_at` terisi timestamp terkini, dan status tetap `SUCCESS`.
  - Pada `migration_step_log`: Kolom `rows_before` dan `rows_after` terisi count aktual sebelum & sesudah rollback, `rows_deleted` = `rows_before - rows_after`, dan pesan memuat `Sebelum=X, Sesudah=Y, Selisih=-Z baris terhapus`.
  - Pada `migration_run.note`: Merangkum total baris yang dihapus (`Total -... baris dihapus dari ... target table`).
  - **Tidak ada baris baru** yang dibuat di `etl_antam.migration_run`.

---

### TC-09: Proteksi Rollback Berulang (Token Guard) (`wf_rollback.hwf`)
- **Langkah**:
  1. Eksekusi kembali `wf_rollback.hwf` dengan parameter `RUN_ID = 146` yang sudah di-rollback pada TC-08.
- **Kriteria Keberhasilan**: Eksekusi gagal seketika pada tahap validasi guard. Query `migration_error_log` mencatat `error_code` = `'ALREADY_ROLLED_BACK'` (*"Rollback dibatalkan: run_id #146 sudah pernah di-rollback"*).

---

### TC-10: Proteksi Rollback Sesi Belum Diposting (`wf_rollback.hwf`)
- **Langkah**:
  1. Jalankan `wf_main.hwf` untuk menghasilkan sesi baru (misal `RUN_ID = 147`), namun JANGAN jalankan `wf_post.hwf` (`is_posted = false`).
  2. Coba jalankan `wf_rollback.hwf` dengan `RUN_ID = 147`.
- **Kriteria Keberhasilan**: Validasi guard menolak eksekusi dengan pesan error `NOT_POSTED_YET` (*"Rollback dibatalkan: run_id #147 belum pernah diposting ke target"*).

---

### TC-11: Proteksi Posting Sesi yang Telah Di-Rollback (`wf_post.hwf`)
- **Langkah**:
  1. Coba jalankan `wf_post.hwf` dengan parameter `RUN_ID = 146` (sesi yang sudah di-rollback).
- **Kriteria Keberhasilan**: Validasi guard menolak eksekusi dengan pesan error `ALREADY_ROLLED_BACK` (*"Posting dibatalkan: run_id #146 sudah pernah di-rollback, silakan mulai siklus migrasi baru dari wf_main"*).

---

## 4. Query Verifikasi Akhir Pengujian

```sql
-- 1. Verifikasi Status Single-Record Lifecycle di migration_run
SELECT run_id, run_ts, main_workflow, status, 
       is_posted, posted_at, post_type, 
       is_rolled_back, rolled_back_at, note 
  FROM etl_antam.migration_run 
 ORDER BY run_id DESC LIMIT 10;

-- 2. Verifikasi Ringkasan Log Error & Diagnostic
SELECT error_id, run_id, step_name, error_code, error_message, error_time 
  FROM etl_antam.migration_error_log 
 ORDER BY error_id DESC LIMIT 10;

-- 3. Verifikasi Keberadaan Data Migrasi di Target Main
SELECT count(*) FROM vendor.slave_vendors WHERE migration = '1';
SELECT count(*) FROM vendor.vendors WHERE migration = '1';
```

---

