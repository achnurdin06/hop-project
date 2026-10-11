# Dokumen Panduan Konfigurasi (Metadata Configuration Guide)
## Sistem ETL & Migrasi Data (SQL Server → PostgreSQL) | Apache Hop

---

## 1. Pendahuluan & Arsitektur Metadata

Sistem ETL ini digerakkan secara dinamis oleh skema metadata **`etl_antam`**. Dengan pendekatan berbasis konfigurasi (*Metadata-Driven Architecture*), penambahan tabel migrasi baru, pemetaan kolom, konversi kode master, hingga posting multi-target dapat dilakukan **tanpa perlu mengubah kode pipeline Hop atau fungsi PL/pgSQL database**.

Panduan ini mencakup rincian 4 tabel konfigurasi utama:
1. **`etl_antam.migration_config`**: Konfigurasi tabel sumber & staging utama.
2. **`etl_antam.migration_target_config`**: Konfigurasi posting & rollback multi-tabel target.
3. **`etl_antam.migration_lookup`**: Kamus pemetaan konversi kode master.
4. **`etl_antam.migration_convert_rule`**: Aturan konversi kode per-kolom target.

---

## 2. Tabel `etl_antam.migration_config` (Main Config)

Tabel ini menyimpan daftar view sumber di SQL Server (`dbo.v_migration_vendor`) dan pemetaannya ke tabel staging PostgreSQL (`stg_vendors_src`).

### 2.1 Struktur & Definisi Kolom

| Nama Kolom | Tipe Data | Constraint / Default | Deskripsi & Fungsi |
|---|---|---|---|
| `config_id` | `serial` | PRIMARY KEY | ID unik konfigurasi (auto-increment). |
| `exec_order` | `int` | `NOT NULL DEFAULT 1` | Urutan prioritas eksekusi antar tabel/view. |
| `src_schema` | `varchar(100)`| `NOT NULL DEFAULT 'dbo'`| Nama schema sumber di SQL Server. |
| `src_view` | `varchar(200)`| `NOT NULL` | Nama View sumber di SQL Server (contoh: `v_migration_vendor`). |
| `tgt_schema` | `varchar(100)`| `NOT NULL DEFAULT 'public'`| Schema target utama di PostgreSQL (contoh: `vendor`). |
| `tgt_table` | `varchar(200)`| `NOT NULL` | Tabel target utama di PostgreSQL (contoh: `slave_vendors`). |
| `stg_table` | `varchar(200)`| `NOT NULL` | Nama tabel staging di PostgreSQL (contoh: `stg_vendors_src`). |
| `pk_columns` | `varchar(500)`| `NOT NULL` | Business Key / Primary Key sumber (pisah koma jika komposit). |
| `compare_columns` | `text` | `NOT NULL` | Kolom-kolom pembanding untuk deteksi delta data. |
| `id_column` | `varchar(100)`| `NULL` | Kolom ID auto-sequence target (contoh: `id`). |
| `id_width` | `int` | `DEFAULT 8` | Lebar digit LPAD ID target (contoh: `8` untuk `'00001032'`). |
| `id_seed` | `bigint` | `DEFAULT 0` | Seed nilai ID awal jika tabel target masih kosong (contoh: `1031`). |
| `src_precheck_sql`| `text` | `DEFAULT 'SELECT 0 AS n'`| Query validasi pra-ekstraksi T-SQL di SQL Server (mengembalikan jumlah pelanggaran `n`). |
| `is_active` | `boolean` | `NOT NULL DEFAULT true`| Status keaktifan konfigurasi (`true` = diproses, `false` = lewati). |

### 2.2 Contoh Script SQL Seeding (Idempotent)

```sql
INSERT INTO etl_antam.migration_config
 (exec_order, src_schema, src_view, tgt_schema, tgt_table, stg_table, pk_columns, compare_columns,
  id_column, id_width, id_seed, src_precheck_sql)
VALUES (
  1, 'dbo', 'v_migration_vendor', 'vendor', 'slave_vendors', 'stg_vendors_src', 'id',
  'vendor_reference_id,uuid,name,vendor_type_id,purchasing_org_id,email,website,company_type_id,status,created_at,sap_code,tipe_verifikasi,last_tipe_verifikasi,migration,status_inactive,tipe_vendor,created_by_role',
  'id', 8, 1031,
  $sql$SELECT
  (SELECT COUNT(*) FROM (SELECT vh.vendor_id
                         FROM vnd_header vh
                         LEFT JOIN vnd_address va ON vh.vendor_id = va.vendor_id
                         GROUP BY vh.vendor_id HAVING COUNT(*) > 1) d)
+ (SELECT COUNT(*) FROM vnd_header
    WHERE email_address IS NULL OR CHARINDEX('@', email_address) = 0) AS n$sql$
)
ON CONFLICT (src_schema, src_view) DO UPDATE
  SET exec_order       = EXCLUDED.exec_order,
      tgt_schema       = EXCLUDED.tgt_schema,
      tgt_table        = EXCLUDED.tgt_table,
      stg_table        = EXCLUDED.stg_table,
      pk_columns       = EXCLUDED.pk_columns,
      compare_columns  = EXCLUDED.compare_columns,
      id_column        = EXCLUDED.id_column,
      id_width         = EXCLUDED.id_width,
      id_seed          = EXCLUDED.id_seed,
      src_precheck_sql = EXCLUDED.src_precheck_sql,
      is_active        = EXCLUDED.is_active;
```

---

## 3. Tabel `etl_antam.migration_target_config` (Multi-Target Post Config)

Tabel ini mengatur dispatch posting data hasil migrasi dari staging ke satu atau beberapa tabel target (contoh: posting ke tabel master `vendor.slave_vendors` lalu ke tabel cabang `vendor.vendors`).

### 3.1 Struktur & Definisi Kolom

| Nama Kolom | Tipe Data | Constraint / Default | Deskripsi & Fungsi |
|---|---|---|---|
| `target_config_id` | `serial` | PRIMARY KEY | ID unik target config. |
| `config_id` | `int` | FK `migration_config` | ID konfigurasi utama yang dirujuk. |
| `exec_order` | `int` | `NOT NULL DEFAULT 1` | Urutan posting (1 = Slave/Master utama, 2 = Main/Tabel turunan). |
| `tgt_schema` | `varchar(100)`| `NOT NULL DEFAULT 'public'`| Schema target di PostgreSQL (contoh: `vendor`). |
| `tgt_table` | `varchar(200)`| `NOT NULL` | Nama tabel target di PostgreSQL (contoh: `slave_vendors`). |
| `pk_columns` | `varchar(500)`| `NOT NULL` | Kolom Primary Key / Unique Key pada tabel target. |
| `mapping_sql` | `text` | `NOT NULL` | Query Template `INSERT INTO target SELECT ... FROM staging WHERE NOT EXISTS ...`. Dukung klausa batch `LIMIT`. |
| `rollback_sql` | `text` | `NULL` | Query Template `DELETE FROM target WHERE EXISTS ...` untuk proses pembatalan aman. |
| `precheck_sql` | `text` | `NULL` | Query SQL validasi awal sebelum insert ke target (mengembalikan `count`). |
| `postcheck_sql` | `text` | `NULL` | Query SQL validasi setelah insert ke target. |
| `is_active` | `boolean` | `NOT NULL DEFAULT true`| Status keaktifan target config. |

### 3.2 Contoh Script SQL Seeding Multi-Target (Idempotent)

```sql
-- Target 1: vendor.slave_vendors (Order 1 - Master Slave Table)
INSERT INTO etl_antam.migration_target_config
 (config_id, exec_order, tgt_schema, tgt_table, pk_columns, mapping_sql, rollback_sql)
VALUES (
  1, 1, 'vendor', 'slave_vendors', 'id',
  $sql$INSERT INTO vendor.slave_vendors (id, vendor_reference_id, uuid, name, vendor_type_id, purchasing_org_id, email, website, company_type_id, status, created_at, sap_code, tipe_verifikasi, last_tipe_verifikasi, migration, status_inactive, tipe_vendor, created_by_role)
SELECT id, vendor_reference_id, uuid, name, vendor_type_id, purchasing_org_id, email, website, company_type_id, status, created_at, sap_code, tipe_verifikasi, last_tipe_verifikasi, migration, status_inactive, tipe_vendor, created_by_role
FROM stg_antam.stg_vendors_src s
WHERE NOT EXISTS (SELECT 1 FROM vendor.slave_vendors t WHERE t.id = s.id OR (s.vendor_reference_id IS NOT NULL AND t.vendor_reference_id = s.vendor_reference_id))$sql$,
  $sql$DELETE FROM vendor.slave_vendors t
WHERE EXISTS (
  SELECT 1 FROM stg_antam.stg_vendors_src s
  WHERE t.id = s.id OR (s.vendor_reference_id IS NOT NULL AND t.vendor_reference_id = s.vendor_reference_id)
)$sql$
) ON CONFLICT (config_id, tgt_schema, tgt_table) DO UPDATE
  SET exec_order   = EXCLUDED.exec_order,
      pk_columns   = EXCLUDED.pk_columns,
      mapping_sql  = EXCLUDED.mapping_sql,
      rollback_sql = EXCLUDED.rollback_sql,
      is_active    = EXCLUDED.is_active;

-- Target 2: vendor.vendors (Order 2 - Main Vendors Table)
INSERT INTO etl_antam.migration_target_config
 (config_id, exec_order, tgt_schema, tgt_table, pk_columns, mapping_sql, rollback_sql)
VALUES (
  1, 2, 'vendor', 'vendors', 'id',
  $sql$INSERT INTO vendor.vendors (id, vendor_reference_id, uuid, name, vendor_type_id, purchasing_org_id, email, website, company_type_id, status, created_at, sap_code, migration, status_inactive)
SELECT id, vendor_reference_id, uuid, name, vendor_type_id, purchasing_org_id, email, website, company_type_id, status, created_at, sap_code, migration, status_inactive
FROM stg_antam.stg_vendors_src s
WHERE NOT EXISTS (SELECT 1 FROM vendor.vendors t WHERE t.id = s.id OR (s.vendor_reference_id IS NOT NULL AND t.vendor_reference_id = s.vendor_reference_id))$sql$,
  $sql$DELETE FROM vendor.vendors t
WHERE EXISTS (
  SELECT 1 FROM stg_antam.stg_vendors_src s
  WHERE t.id = s.id OR (s.vendor_reference_id IS NOT NULL AND t.vendor_reference_id = s.vendor_reference_id)
)$sql$
) ON CONFLICT (config_id, tgt_schema, tgt_table) DO UPDATE
  SET exec_order   = EXCLUDED.exec_order,
      pk_columns   = EXCLUDED.pk_columns,
      mapping_sql  = EXCLUDED.mapping_sql,
      rollback_sql = EXCLUDED.rollback_sql,
      is_active    = EXCLUDED.is_active;
```

---

## 4. Tabel `etl_antam.migration_lookup` (Kamus Konversi Master)

Tabel ini menyimpan referensi kamus konversi untuk memetakan nilai/kode dari sistem legacy SQL Server ke ID master PostgreSQL target.

### 4.1 Struktur & Definisi Kolom

| Nama Kolom | Tipe Data | Constraint / Default | Deskripsi & Fungsi |
|---|---|---|---|
| `lookup_name` | `text` | PRIMARY KEY | Nama unik kamus lookup (contoh: `lkp_vendor_type`, `lkp_company_type`). |
| `master_schema`| `text` | `DEFAULT 'public'` | Schema tabel master referensi di PostgreSQL. |
| `master_table` | `text` | `NOT NULL` | Nama tabel master referensi (contoh: `vendor_types`). |
| `master_src_col`| `text` | `NOT NULL` | Kolom pencocokan kode sumber di tabel master (contoh: `code` / `name`). |
| `master_tgt_col`| `text` | `NOT NULL` | Kolom nilai ID yang diambil dari tabel master (contoh: `id`). |
| `master_filter` | `text` | `NULL` | Filter tambahan SQL untuk tabel master (contoh: `'is_active = true'`). |
| `on_unmapped` | `text` | `DEFAULT 'FAIL'` | Tindakan jika kode tidak cocok: `'FAIL'` (Error), `'NULL'`, `'DEFAULT'`. |
| `default_value` | `text` | `NULL` | Nilai default jika `on_unmapped = 'DEFAULT'`. |
| `normalize` | `boolean` | `DEFAULT true` | Jika `true`, pencocokan kode dilakukan secara `UPPER(TRIM(...))`. |

### 4.2 Contoh Script SQL Seeding Lookup

```sql
INSERT INTO etl_antam.migration_lookup
 (lookup_name, master_schema, master_table, master_src_col, master_tgt_col, on_unmapped, default_value, normalize)
VALUES
 ('lkp_vendor_type',  'public', 'vendor_types',  'code', 'id', 'FAIL', NULL, true),
 ('lkp_company_type', 'public', 'company_types', 'code', 'id', 'NULL', NULL, true)
ON CONFLICT (lookup_name) DO UPDATE
  SET master_schema  = EXCLUDED.master_schema,
      master_table   = EXCLUDED.master_table,
      master_src_col = EXCLUDED.master_src_col,
      master_tgt_col = EXCLUDED.master_tgt_col,
      on_unmapped    = EXCLUDED.on_unmapped,
      default_value  = EXCLUDED.default_value,
      normalize      = EXCLUDED.normalize;
```

---

## 5. Tabel `etl_antam.migration_convert_rule` (Aturan Konversi Kolom)

Tabel ini mendaftarkan kolom-kolom staging mana saja yang wajib dikonversi nilainya sebelum diposting ke tabel target.

### 5.1 Struktur & Definisi Kolom

| Nama Kolom | Tipe Data | Constraint / Default | Deskripsi & Fungsi |
|---|---|---|---|
| `rule_id` | `serial` | PRIMARY KEY | ID unik aturan konversi. |
| `config_id` | `int` | FK `migration_config` | ID konfigurasi utama yang dirujuk. |
| `column_name` | `text` | `NOT NULL` | Kolom pada staging/target yang dikonversi (contoh: `vendor_type_id`). |
| `source_column`| `text` | `NULL` | Kolom sumber di staging jika namanya berbeda dari `column_name`. |
| `lookup_name` | `text` | FK `migration_lookup` | Nama kamus lookup yang digunakan. |
| `on_unmapped` | `text` | `NULL` | Meng-override aturan `on_unmapped` dari lookup jika diisi. |
| `default_value`| `text` | `NULL` | Meng-override `default_value` dari lookup jika diisi. |
| `is_active` | `boolean` | `DEFAULT true` | Status aktif aturan konversi. |

### 5.2 View Efektif `etl_antam.vw_convert_rule`
Prosedur konversi kode (`fn_convert_codes`) membaca view `vw_convert_rule` yang secara otomatis menggabungkan nilai dari `migration_convert_rule` dengan fallback default dari `migration_lookup`:

```sql
CREATE OR REPLACE VIEW etl_antam.vw_convert_rule AS
SELECT r.rule_id, r.config_id, r.column_name, r.source_column, r.lookup_name,
       COALESCE(r.master_schema,  l.master_schema, 'public') AS master_schema,
       COALESCE(r.master_table,   l.master_table)            AS master_table,
       COALESCE(r.master_src_col, l.master_src_col)          AS master_src_col,
       COALESCE(r.master_tgt_col, l.master_tgt_col)          AS master_tgt_col,
       COALESCE(r.master_filter,  l.master_filter)           AS master_filter,
       COALESCE(r.on_unmapped,    l.on_unmapped, 'FAIL')     AS on_unmapped,
       COALESCE(r.default_value,  l.default_value)           AS default_value,
       COALESCE(r.normalize,      l.normalize, true)         AS normalize
  FROM etl_antam.migration_convert_rule r
  LEFT JOIN etl_antam.migration_lookup l ON l.lookup_name = r.lookup_name
 WHERE r.is_active;
```

---

## 6. Cheat Sheet: Cara Menambahkan Tabel Migrasi Baru

Jika ingin menambahkan tabel baru (misal: `tabel_material`) ke dalam sistem ETL:

1. **Langkah 1**: Daftarkan view sumber & staging ke `migration_config`:
   ```sql
   INSERT INTO etl_antam.migration_config (exec_order, src_schema, src_view, tgt_schema, tgt_table, stg_table, pk_columns, compare_columns)
   VALUES (2, 'dbo', 'v_migration_material', 'public', 'materials', 'stg_materials_src', 'code', 'name,unit,price');
   ```
2. **Langkah 2**: Jika ada konversi kode master, daftarkan di `migration_lookup` & `migration_convert_rule`.
3. **Langkah 3**: Daftarkan query posting target di `migration_target_config`:
   ```sql
   INSERT INTO etl_antam.migration_target_config (config_id, exec_order, tgt_schema, tgt_table, pk_columns, mapping_sql, rollback_sql)
   VALUES (2, 1, 'public', 'materials', 'code',
     $sql$INSERT INTO public.materials (code, name, unit, price) SELECT code, name, unit, price FROM stg_antam.stg_materials_src s WHERE NOT EXISTS (SELECT 1 FROM public.materials t WHERE t.code = s.code)$sql$,
     $sql$DELETE FROM public.materials t WHERE EXISTS (SELECT 1 FROM stg_antam.stg_materials_src s WHERE s.code = t.code)$sql$
   );
   ```

Setelah 3 langkah SQL sederhana di atas, tabel baru otomatis langsung didukung dan dapat dijalankan oleh `wf_main.hwf`, `wf_post.hwf`, `wf_rollback.hwf`, maupun `wf_purge_target.hwf`!

---

## 7. Model Data Runtime & Audit Lifecycle

Selain tabel-tabel konfigurasi metadata, sistem migrasi mengelola status eksekusi menggunakan 3 tabel audit runtime di skema `etl_antam`:

### 7.1 Tabel `etl_antam.migration_run` (Single-Record Lifecycle)

Setiap siklus migrasi (mulai dari ekstraksi/staging, posting target, hingga rollback jika diperlukan) dicatat dalam **1 baris data tunggal**:

| Nama Kolom | Tipe Data | Constraint / Default | Deskripsi & Fungsi |
|---|---|---|---|
| `run_id` | `bigserial` | PRIMARY KEY | Identifier unik sesi migrasi. |
| `run_ts` | `timestamptz` | `DEFAULT now()` | Timestamp dimulainya sesi migrasi. |
| `start_time` | `timestamptz` | `NULL` | Waktu mulai eksekusi workflow utama. |
| `end_time` | `timestamptz` | `NULL` | Waktu selesai eksekusi workflow utama. |
| `status` | `varchar(20)` | `CHECK IN ('RUNNING','SUCCESS','FAILED')` | Status sesi (hanya 3 nilai baku). |
| `hop_host` | `varchar(100)`| `NULL` | Hostname / environment mesin Apache Hop. |
| `note` | `text` | `NULL` | Catatan ringkasan eksekusi. |
| `main_workflow`| `varchar(100)`| `NULL` | Nama workflow utama pembuat sesi (`wf_main.hwf`, `wf_purge_target.hwf`). |
| `config_id` | `text` | `NULL` | ID atau daftar ID konfigurasi tabel yang diproses. |
| `client_id` | `int` | FK `master_client` | ID unik Klien/Tenant yang terkait dengan sesi migrasi. |
| `env_id` | `int` | FK `master_environment` | ID unik Environment yang terkait dengan sesi migrasi. |
| `client` | `varchar(100)`| `NULL` | Nama resmi Klien (misal: `PT ANTAM Tbk`). |
| `environment` | `varchar(50)` | `NULL` | Nama Environment eksekusi (misal: `Development`). |
| `is_posted` | `boolean` | `DEFAULT false` | Flag apakah data sudah diposting ke tabel target (`wf_post.hwf`). |
| `posted_at` | `timestamp` | `NULL` | Waktu eksekusi posting ke tabel target. |
| `post_type` | `varchar(30)` | `NULL` | Mode posting yang digunakan (`BATCH (1000)` atau `DIRECT`). |
| `is_rolled_back`| `boolean` | `DEFAULT false` | Flag apakah sesi sudah di-rollback (`wf_rollback.hwf`). |
| `rolled_back_at`| `timestamp` | `NULL` | Waktu eksekusi rollback sesi. |

> **Catatan Arsitektur**: Kolom lama `rollback_of_run_id` telah dihapus. Ketika `wf_rollback.hwf` dieksekusi dengan parameter `RUN_ID`, sistem langsung memperbarui baris `RUN_ID` yang sama menjadi `is_rolled_back = true` dan `rolled_back_at = now()`, tanpa membuat baris sesi baru.

### 7.2 Tabel `etl_antam.migration_step_log` & `migration_error_log`

1. **`migration_step_log`**: Mencatat tahapan granular (`PRECHECK`, `STAGING`, `CONVERT`, `DELTA`, `POST_TARGET`, `ROLLBACK`, `PURGE_TARGET`), durasi waktu, serta jumlah baris data yang diproses (`rows_read`, `rows_written`, `rows_error`).
2. **`migration_error_log`**: Mencatat diagnostik error teknis (`error_code`, `error_message`, `error_detail`, `pipeline_name`, `error_time`).

---
