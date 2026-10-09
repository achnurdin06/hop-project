-- =====================================================================
-- SYSTEM ETL & MIGRASI DATA (SQL Server -> PostgreSQL) | APACHE HOP
-- Master Database Script (Unified Single File)
-- 
-- Petunjuk Penggunaan:
--  - Jalankan script ini pada database PostgreSQL target (PostgreSQL 11+).
--  - Script ini bersifat Idempotent (Aman dijalankan berulang kali).
--  - Semua konfigurasi dibuat dengan mode REPLACE ON CONFLICT.
-- =====================================================================

-- Inisialisasi Schema
CREATE SCHEMA IF NOT EXISTS etl_antam;
CREATE SCHEMA IF NOT EXISTS stg_antam;

-- =====================================================================
-- [SECTION 1] TABEL METADATA, KONFIGURASI & LOGGING
-- =====================================================================

-- 1.1 Tabel Konfigurasi Utama Migrasi
CREATE TABLE IF NOT EXISTS etl_antam.migration_config (
  config_id        serial CONSTRAINT pk_migration_config PRIMARY KEY,
  exec_order       int          NOT NULL DEFAULT 1,
  src_schema       varchar(100) NOT NULL DEFAULT 'dbo',
  src_view         varchar(200) NOT NULL,
  tgt_schema       varchar(100) NOT NULL DEFAULT 'public',
  tgt_table        varchar(200) NOT NULL,
  stg_table        varchar(200) NOT NULL,
  pk_columns       varchar(500) NOT NULL,   -- Business Key / Primary Key (pisah koma)
  compare_columns  text         NOT NULL,   -- Kolom pembanding data
  id_column        varchar(100),            -- Kolom ID auto-sequence (opsional)
  id_width         int          DEFAULT 8,  -- Lebar LPAD ID (default: 8 digit, misal '00001032')
  id_seed          bigint       DEFAULT 0,  -- Nilai awal jika target kosong
  src_precheck_sql text         NOT NULL DEFAULT 'SELECT 0 AS n', -- Query pra-pemeriksaan T-SQL
  is_active        boolean      NOT NULL DEFAULT true,
  CONSTRAINT uq_migration_config_src_view UNIQUE (src_schema, src_view)
);

-- 1.2 Tabel Log Sesi Eksekusi Migrasi & Rollback (Single-Record Lifecycle)
CREATE TABLE IF NOT EXISTS etl_antam.migration_run (
  run_id              bigserial CONSTRAINT pk_migration_run PRIMARY KEY,
  run_ts              varchar(15) NOT NULL,          -- Format Timestamp YYYYMMDD_HH24MI
  main_workflow       varchar(50),                   -- Nama workflow utama (cth: wf_main.hwf, wf_post.hwf, wf_rollback.hwf)
  start_time          timestamp NOT NULL DEFAULT now(),
  end_time            timestamp,
  status              varchar(20) DEFAULT 'RUNNING' CONSTRAINT chk_migration_run_status CHECK (status IN ('RUNNING', 'SUCCESS', 'FAILED')),
  hop_host            varchar(100),                  -- Host/IP pengirim eksekusi
  note                text,                          -- Catatan detail eksekusi
  config_id           text,                          -- ID atau daftar ID konfigurasi yang diproses (contoh: 1 atau 1,2,3)
  is_posted           boolean DEFAULT false,         -- True jika data staging telah berhasil diposting ke tabel utama
  posted_at           timestamp,                     -- Waktu posting berhasil diselesaikan
  post_type           varchar(30),                   -- Tipe posting: BATCH (1000), DIRECT, NULL jika baru staging
  is_rolled_back      boolean DEFAULT false,         -- True jika sesi ini telah berhasil di-rollback
  rolled_back_at      timestamp                      -- Waktu rollback berhasil diselesaikan
);
ALTER TABLE etl_antam.migration_run ADD COLUMN IF NOT EXISTS main_workflow varchar(50);
ALTER TABLE etl_antam.migration_run ADD COLUMN IF NOT EXISTS config_id text;
ALTER TABLE etl_antam.migration_run ADD COLUMN IF NOT EXISTS is_posted boolean DEFAULT false;
ALTER TABLE etl_antam.migration_run ADD COLUMN IF NOT EXISTS posted_at timestamp;
ALTER TABLE etl_antam.migration_run ADD COLUMN IF NOT EXISTS post_type varchar(30);
ALTER TABLE etl_antam.migration_run ADD COLUMN IF NOT EXISTS is_rolled_back boolean DEFAULT false;
ALTER TABLE etl_antam.migration_run ADD COLUMN IF NOT EXISTS rolled_back_at timestamp;

-- 1.3 Tabel Log Langkah Granular (Step Log)
CREATE TABLE IF NOT EXISTS etl_antam.migration_step_log (
  log_id        bigserial CONSTRAINT pk_migration_step_log PRIMARY KEY,
  run_id        bigint CONSTRAINT fk_migration_step_log_run REFERENCES etl_antam.migration_run,
  config_id     int    CONSTRAINT fk_migration_step_log_config REFERENCES etl_antam.migration_config,
  step_name     varchar(30),                -- PRECHECK / STAGING / CONVERT / DELTA / POST_TARGET / ROLLBACK
  status        varchar(10),                -- START / OK / SKIP / FAILED
  rows_src      bigint, rows_stg bigint, rows_new bigint, rows_changed bigint, rows_deleted bigint,
  start_time    timestamp DEFAULT now(),
  end_time      timestamp,
  message       text
);

-- 1.4 Tabel Log Error Diagnostic
CREATE TABLE IF NOT EXISTS etl_antam.migration_error_log (
  error_id       bigserial CONSTRAINT pk_migration_error_log PRIMARY KEY,
  run_id         bigint,
  config_id      int,
  step_name      varchar(30),
  pipeline_name  varchar(200),
  transform_name varchar(200),
  error_time     timestamp DEFAULT now(),
  error_code     varchar(100),
  error_message  text,
  error_detail   text,
  error_field    varchar(500),
  row_data       text
);
CREATE INDEX IF NOT EXISTS ix_migration_error_log_run_cfg ON etl_antam.migration_error_log (run_id, config_id);

-- 1.5 Tabel Konfigurasi Multi-Target Post & Rollback (Flow 2)
CREATE TABLE IF NOT EXISTS etl_antam.migration_target_config (
  target_config_id serial CONSTRAINT pk_migration_target_config PRIMARY KEY,
  config_id        int NOT NULL CONSTRAINT fk_migration_target_config_main REFERENCES etl_antam.migration_config,
  exec_order       int NOT NULL DEFAULT 1,     -- Urutan posting (1 = Slave, 2 = Master)
  tgt_schema       varchar(100) NOT NULL DEFAULT 'public',
  tgt_table        varchar(200) NOT NULL,
  pk_columns       varchar(500) NOT NULL,
  mapping_sql      text,                       -- SQL Template INSERT INTO target (otomatis di-generate/refresh)
  rollback_sql     text,                       -- SQL Template DELETE presisi untuk rollback (otomatis)
  precheck_sql     text,
  postcheck_sql    text,
  is_active        boolean NOT NULL DEFAULT true,
  CONSTRAINT uq_migration_target_config_table UNIQUE (config_id, tgt_schema, tgt_table)
);
ALTER TABLE etl_antam.migration_target_config ADD COLUMN IF NOT EXISTS rollback_sql text;
ALTER TABLE etl_antam.migration_target_config ALTER COLUMN mapping_sql DROP NOT NULL;
ALTER TABLE etl_antam.migration_target_config ALTER COLUMN rollback_sql DROP NOT NULL;

-- 1.6 Tabel Kamus Lookup Konversi Kode
CREATE TABLE IF NOT EXISTS etl_antam.migration_lookup (
  lookup_name    text CONSTRAINT pk_migration_lookup PRIMARY KEY,
  master_schema  text NOT NULL DEFAULT 'public',
  master_table   text NOT NULL,
  master_src_col text NOT NULL,                    -- Kolom pencocokan kode sumber
  master_tgt_col text NOT NULL,                    -- Kolom yang diambil (misal: ID)
  master_filter  text,                             -- Filter tambahan master (misal: 'm.is_active = true')
  on_unmapped    text NOT NULL DEFAULT 'FAIL' CONSTRAINT ck_migration_lookup_on_unmapped CHECK (on_unmapped IN ('FAIL','NULL','DEFAULT')),
  default_value  text,
  normalize      boolean NOT NULL DEFAULT true,    -- Upper & trim perbandingan
  description    text
);

-- 1.7 Tabel Aturan Konversi Kode per Kolom Target
CREATE TABLE IF NOT EXISTS etl_antam.migration_convert_rule (
  rule_id        serial CONSTRAINT pk_migration_convert_rule PRIMARY KEY,
  config_id      int  NOT NULL CONSTRAINT fk_migration_convert_rule_config REFERENCES etl_antam.migration_config,
  column_name    text NOT NULL,                    -- Kolom target yang diisi
  source_column  text,                             -- Kolom sumber (jika berbeda dari column_name)
  lookup_name    text CONSTRAINT fk_migration_convert_rule_lookup REFERENCES etl_antam.migration_lookup,
  master_schema  text,
  master_table   text,
  master_src_col text,
  master_tgt_col text,
  master_filter  text,
  on_unmapped    text CONSTRAINT ck_migration_convert_rule_on_unmapped CHECK (on_unmapped IN ('FAIL','NULL','DEFAULT')),
  default_value  text,
  normalize      boolean,
  is_active      boolean NOT NULL DEFAULT true,
  CONSTRAINT uq_migration_convert_rule_column UNIQUE (config_id, column_name)
);

-- 1.8 View Aturan Konversi Efektif
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

-- =====================================================================
-- [SECTION 2] PROSEDUR UTILITY & LOGGING
-- =====================================================================

CREATE OR REPLACE PROCEDURE etl_antam.pr_log_step(
  p_run bigint, p_cfg int, p_step text, p_status text, p_msg text DEFAULT NULL,
  p_rows_src bigint DEFAULT NULL, p_rows_stg bigint DEFAULT NULL,
  p_rows_new bigint DEFAULT NULL, p_rows_chg bigint DEFAULT NULL, p_rows_del bigint DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO etl_antam.migration_step_log
    (run_id, config_id, step_name, status, message,
     rows_src, rows_stg, rows_new, rows_changed, rows_deleted, end_time)
  VALUES (p_run, p_cfg, p_step, p_status, p_msg,
     p_rows_src, p_rows_stg, p_rows_new, p_rows_chg, p_rows_del, now());
END $$;

CREATE OR REPLACE PROCEDURE etl_antam.pr_log_error(
  p_run bigint, p_cfg int, p_step text, p_code text, p_msg text,
  p_detail text DEFAULT NULL, p_pipeline text DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO etl_antam.migration_error_log
    (run_id, config_id, step_name, pipeline_name, error_code, error_message, error_detail)
  VALUES (p_run, p_cfg, p_step, p_pipeline, p_code, p_msg, p_detail);
END $$;

CREATE OR REPLACE PROCEDURE etl_antam.pr_fail(
  p_run bigint, p_cfg int, p_step text, p_code text, p_msg text, p_detail text DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
  CALL etl_antam.pr_log_error(p_run, p_cfg, p_step, p_code, p_msg, p_detail);
  CALL etl_antam.pr_log_step(p_run, p_cfg, p_step, 'FAILED', left(p_code || ': ' || p_msg, 1000));
END $$;

-- =====================================================================
-- [SECTION 3] FLOW 1: LANDING STAGING & CODE CONVERSION
-- =====================================================================

-- 3.1 Precheck Target Table & Columns
CREATE OR REPLACE FUNCTION etl_antam.fn_precheck_target(p_run bigint, p_cfg int)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  c etl_antam.migration_config%ROWTYPE;
  v_rel regclass; v_n int; v_miss text; v_det text; v_id_col text;
BEGIN
  CALL etl_antam.pr_log_step(p_run, p_cfg, 'PRECHECK', 'START', 'pengecekan awal target');
  SELECT * INTO c FROM etl_antam.migration_config WHERE config_id = p_cfg;
  IF NOT FOUND OR NOT c.is_active THEN
    CALL etl_antam.pr_log_step(p_run, p_cfg, 'PRECHECK', 'SKIP', 'konfigurasi tidak aktif');
    RETURN 0;
  END IF;

  v_rel := to_regclass(format('%I.%I', c.tgt_schema, c.tgt_table));
  IF v_rel IS NULL THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'PRECHECK', 'TARGET_TABLE_NOT_FOUND',
         format('tabel target %s.%s belum ada di PostgreSQL', c.tgt_schema, c.tgt_table));
    RETURN 1;
  END IF;

  v_id_col := NULLIF(btrim(c.id_column), '');
  SELECT string_agg(k, ', ') INTO v_miss
    FROM unnest(string_to_array(c.pk_columns || ',' || c.compare_columns, ',')) k
   WHERE btrim(k) <> ''
     AND (v_id_col IS NULL OR btrim(k) <> v_id_col)
     AND NOT EXISTS (
       SELECT 1 FROM information_schema.columns ic
        WHERE ic.table_schema = c.tgt_schema AND ic.table_name = c.tgt_table
          AND ic.column_name = btrim(k)
     );

  IF v_miss IS NOT NULL THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'PRECHECK', 'COLUMN_MISMATCH', 'kolom tidak ada di target: ' || v_miss);
    RETURN 1;
  END IF;

  CALL etl_antam.pr_log_step(p_run, p_cfg, 'PRECHECK', 'OK', 'target siap');
  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
  CALL etl_antam.pr_fail(p_run, p_cfg, 'PRECHECK', 'SQL_ERROR', SQLSTATE || ' ' || SQLERRM, v_det);
  RETURN 1;
END $$;

-- 3.2 Check Conversion Config Rules
CREATE OR REPLACE FUNCTION etl_antam.fn_check_convert_config(p_cfg int)
RETURNS TABLE(problem text) LANGUAGE plpgsql AS $$
DECLARE c etl_antam.migration_config%ROWTYPE; r record;
BEGIN
  SELECT * INTO c FROM etl_antam.migration_config WHERE config_id = p_cfg;
  FOR r IN SELECT * FROM etl_antam.vw_convert_rule WHERE config_id = p_cfg ORDER BY rule_id LOOP
    IF r.master_table IS NULL OR r.master_src_col IS NULL OR r.master_tgt_col IS NULL THEN
      problem := format('kolom %s: master_table/master_src_col/master_tgt_col belum ditentukan', r.column_name);
      RETURN NEXT; CONTINUE;
    END IF;
    IF to_regclass(format('%I.%I', r.master_schema, r.master_table)) IS NULL THEN
      problem := format('kolom %s: master %s.%s tidak ada', r.column_name, r.master_schema, r.master_table);
      RETURN NEXT; CONTINUE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns ic WHERE ic.table_schema = r.master_schema
                    AND ic.table_name = r.master_table AND ic.column_name = r.master_src_col) THEN
      problem := format('kolom %s: master_src_col %s tidak ada di %s.%s', r.column_name, r.master_src_col, r.master_schema, r.master_table);
      RETURN NEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns ic WHERE ic.table_schema = r.master_schema
                    AND ic.table_name = r.master_table AND ic.column_name = r.master_tgt_col) THEN
      problem := format('kolom %s: master_tgt_col %s tidak ada di %s.%s', r.column_name, r.master_tgt_col, r.master_schema, r.master_table);
      RETURN NEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns ic WHERE ic.table_schema = c.tgt_schema
                    AND ic.table_name = c.tgt_table AND ic.column_name = r.column_name) THEN
      problem := format('kolom %s tidak ada di target %s.%s', r.column_name, c.tgt_schema, c.tgt_table);
      RETURN NEXT;
    END IF;
    IF r.on_unmapped = 'DEFAULT' AND r.default_value IS NULL THEN
      problem := format('kolom %s: on_unmapped=DEFAULT tetapi default_value kosong', r.column_name);
      RETURN NEXT;
    END IF;
  END LOOP;
END $$;

-- 3.2b Validasi Pilihan Config (Wajib diisi & valid di migration_config)
DROP FUNCTION IF EXISTS etl_antam.fn_validate_config_selection(text);
CREATE OR REPLACE FUNCTION etl_antam.fn_validate_config_selection(p_config_ids text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  v_raw text;
  v_arr int[];
  v_cnt int;
  v_active_cnt int;
BEGIN
  v_raw := btrim(COALESCE(p_config_ids, ''));
  IF v_raw = '' OR v_raw LIKE '${%' THEN
    RAISE EXCEPTION 'Parameter CONFIG_ID wajib diisi (contoh: 1 atau 1,2,3)';
  END IF;

  v_raw := regexp_replace(v_raw, '\s+', '', 'g');

  IF v_raw !~ '^[0-9]+(,[0-9]+)*$' THEN
    RAISE EXCEPTION 'Format CONFIG_ID tidak valid (%): harus berupa angka atau daftar angka dipisah koma (contoh: 1 atau 1,2)', p_config_ids;
  END IF;

  v_arr := string_to_array(v_raw, ',')::int[];
  v_cnt := cardinality(v_arr);

  SELECT count(*) INTO v_active_cnt
    FROM etl_antam.migration_config
   WHERE config_id = ANY(v_arr) AND is_active;

  IF v_active_cnt < v_cnt THEN
    RAISE EXCEPTION 'Satu atau lebih CONFIG_ID tidak ditemukan di migration_config atau tidak aktif (diminta: %, aktif: %)', v_cnt, v_active_cnt;
  END IF;

  RETURN v_active_cnt;
END $$;

-- 3.2c Validasi RUN_ID untuk Workflow Posting (wf_post.hwf)
CREATE OR REPLACE FUNCTION etl_antam.fn_validate_post_run(p_run_id text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_raw text;
  v_run_id bigint;
  v_config_id text;
  v_status text;
  v_is_posted boolean;
  v_posted_at timestamp;
  v_is_rolled_back boolean;
  v_post_type text;
  v_first_cfg int;
BEGIN
  v_raw := btrim(COALESCE(p_run_id, ''));
  IF v_raw = '' OR v_raw LIKE '$%' THEN
    RAISE EXCEPTION 'Parameter RUN_ID wajib diisi';
  END IF;
  IF v_raw !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'Format RUN_ID tidak valid (%): harus berupa angka integer positif', p_run_id;
  END IF;
  v_run_id := v_raw::bigint;

  SELECT config_id, status, is_posted, posted_at, is_rolled_back, post_type
    INTO v_config_id, v_status, v_is_posted, v_posted_at, v_is_rolled_back, v_post_type
    FROM etl_antam.migration_run WHERE run_id = v_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RUN_ID % tidak ditemukan di etl_antam.migration_run', v_run_id;
  END IF;
  IF v_config_id IS NULL OR btrim(v_config_id) = '' THEN
    RAISE EXCEPTION 'RUN_ID % tidak memiliki informasi config_id yang diproses', v_run_id;
  END IF;
  v_first_cfg := (string_to_array(regexp_replace(v_config_id, '\s+', '', 'g'), ','))[1]::int;

  -- 1. Guard Anti-Rollback (Cek apakah sesi sudah pernah di-rollback)
  IF v_is_rolled_back IS TRUE THEN
    CALL etl_antam.pr_fail(
      v_run_id, v_first_cfg, 'VALIDATE_POST_RUN', 'ALREADY_ROLLED_BACK',
      format('RUN_ID #%s sudah pernah di-rollback. Proses posting ditolak, silakan mulai ulang siklus baru dari wf_main.hwf.', v_run_id)
    );
    RAISE EXCEPTION 'RUN_ID #% sudah pernah di-rollback. Proses posting ditolak, silakan mulai ulang siklus migrasi dari wf_main.hwf.', v_run_id;
  END IF;

  -- 2. Guard Anti-Duplicate Post (Cek apakah sesi sudah pernah diposting)
  IF v_is_posted IS TRUE THEN
    CALL etl_antam.pr_fail(
      v_run_id, v_first_cfg, 'VALIDATE_POST_RUN', 'ALREADY_POSTED',
      format('RUN_ID #%s sudah pernah diposting sebelumnya pada %s (tipe: %s). Posting ulang ditolak untuk mencegah data duplikat.', v_run_id, to_char(v_posted_at, 'YYYY-MM-DD HH24:MI:SS'), COALESCE(v_post_type, 'DIRECT'))
    );
    RAISE EXCEPTION 'RUN_ID #% sudah pernah diposting pada % (tipe: %). Posting ulang ditolak untuk mencegah duplikasi data.', v_run_id, to_char(v_posted_at, 'YYYY-MM-DD HH24:MI:SS'), COALESCE(v_post_type, 'DIRECT');
  END IF;

  -- Set status kembali ke 'RUNNING' saat posting dimulai
  UPDATE etl_antam.migration_run
     SET status = 'RUNNING'
   WHERE run_id = v_run_id;

  RETURN v_config_id;
END $$;

-- 3.2d Validasi RUN_ID untuk Workflow Rollback (wf_rollback.hwf)
CREATE OR REPLACE FUNCTION etl_antam.fn_validate_rollback_run(p_run_id text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_raw text;
  v_run_id bigint;
  v_config_id text;
  v_status text;
  v_is_posted boolean;
  v_is_rolled_back boolean;
  v_rolled_back_at timestamp;
  v_first_cfg int;
BEGIN
  v_raw := btrim(COALESCE(p_run_id, ''));
  IF v_raw = '' OR v_raw LIKE '$%' THEN
    RAISE EXCEPTION 'Parameter RUN_ID wajib diisi';
  END IF;
  IF v_raw !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'Format RUN_ID tidak valid (%): harus berupa angka integer positif', p_run_id;
  END IF;

  v_run_id := v_raw::bigint;
  SELECT config_id, status, is_posted, is_rolled_back, rolled_back_at
    INTO v_config_id, v_status, v_is_posted, v_is_rolled_back, v_rolled_back_at
    FROM etl_antam.migration_run WHERE run_id = v_run_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'RUN_ID % tidak ditemukan di etl_antam.migration_run', v_run_id;
  END IF;

  IF v_config_id IS NULL OR btrim(v_config_id) = '' THEN
    RAISE EXCEPTION 'RUN_ID % tidak memiliki informasi config_id yang diproses', v_run_id;
  END IF;
  v_first_cfg := (string_to_array(regexp_replace(v_config_id, '\s+', '', 'g'), ','))[1]::int;

  -- 1. Guard Belum Diposting: Harus sudah diposting sebelum bisa di-rollback
  IF v_is_posted IS NOT TRUE THEN
    CALL etl_antam.pr_fail(
      v_run_id, v_first_cfg, 'VALIDATE_ROLLBACK_RUN', 'NOT_POSTED_YET',
      format('RUN_ID #%s belum pernah diposting ke tabel target (is_posted = false). Tidak ada data yang dapat di-rollback.', v_run_id)
    );
    RAISE EXCEPTION 'RUN_ID #% belum pernah diposting ke tabel target. Tidak ada data yang dapat di-rollback.', v_run_id;
  END IF;

  -- 2. Guard Anti-Duplicate Rollback: Tidak boleh rollback lebih dari 1 kali
  IF v_is_rolled_back IS TRUE THEN
    CALL etl_antam.pr_fail(
      v_run_id, v_first_cfg, 'VALIDATE_ROLLBACK_RUN', 'ALREADY_ROLLED_BACK',
      format('RUN_ID #%s sudah pernah di-rollback sebelumnya pada %s. Rollback ulang ditolak.', v_run_id, to_char(v_rolled_back_at, 'YYYY-MM-DD HH24:MI:SS'))
    );
    RAISE EXCEPTION 'RUN_ID #% sudah pernah di-rollback pada %. Rollback ulang ditolak.', v_run_id, to_char(v_rolled_back_at, 'YYYY-MM-DD HH24:MI:SS');
  END IF;

  -- Update status run menjadi 'RUNNING' untuk menandai proses rollback sedang berlangsung
  UPDATE etl_antam.migration_run
     SET status = 'RUNNING'
   WHERE run_id = v_run_id;

  RETURN v_config_id;
END $$;

-- 3.3 Prepare Staging Table (Single Source of Truth)
CREATE OR REPLACE FUNCTION etl_antam.fn_prepare_staging(p_run bigint, p_cfg int)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE c etl_antam.migration_config%ROWTYPE; r record; v_src text; v_prob text; v_stg_tbl text; v_id_col text; v_id_type text; v_seq_name text; v_max_id bigint; v_det text;
BEGIN
  CALL etl_antam.pr_log_step(p_run, p_cfg, 'STAGING', 'START', 'siapkan tabel staging');
  SELECT * INTO c FROM etl_antam.migration_config WHERE config_id = p_cfg;
  IF to_regclass(format('%I.%I', c.tgt_schema, c.tgt_table)) IS NULL THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'STAGING', 'TARGET_NOT_FOUND',
         format('tabel target %s.%s belum ada di database', c.tgt_schema, c.tgt_table));
    RETURN 1;
  END IF;
  v_stg_tbl := CASE WHEN c.stg_table LIKE '%_src' THEN c.stg_table ELSE c.stg_table || '_src' END;

  -- Validasi aturan konversi
  SELECT string_agg(problem, '; ') INTO v_prob FROM etl_antam.fn_check_convert_config(p_cfg);
  IF v_prob IS NOT NULL THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'STAGING', 'CONVERT_CONFIG_INVALID', v_prob);
    RETURN 1;
  END IF;

  EXECUTE format('DROP TABLE IF EXISTS stg_antam.%I CASCADE', v_stg_tbl);
  EXECUTE format('CREATE TABLE stg_antam.%I (LIKE %I.%I INCLUDING DEFAULTS)',
                 v_stg_tbl, c.tgt_schema, c.tgt_table);

  -- Lepaskan semua NOT NULL constraint agar landing data bersih dari constraint
  FOR r IN SELECT column_name FROM information_schema.columns 
            WHERE table_schema = 'stg_antam' AND table_name = v_stg_tbl AND is_nullable = 'NO' LOOP
    EXECUTE format('ALTER TABLE stg_antam.%I ALTER COLUMN %I DROP NOT NULL', v_stg_tbl, r.column_name);
  END LOOP;

  -- Auto-Sequence ID Generation (Mendukung ID tipe Integer maupun Text/LPAD)
  v_id_col := NULLIF(btrim(c.id_column), '');
  IF v_id_col IS NOT NULL THEN
    EXECUTE format($q$
      SELECT COALESCE(
        (SELECT max(NULLIF(regexp_replace(%1$I::text, '\D', '', 'g'), '')::bigint) 
           FROM %2$I.%3$I 
          WHERE %1$I IS NOT NULL AND %1$I::text ~ '\d+'),
        %4$s
      )
    $q$, v_id_col, c.tgt_schema, c.tgt_table, COALESCE(c.id_seed, 0)) INTO v_max_id;

    IF v_max_id IS NULL THEN
      v_max_id := COALESCE(c.id_seed, 0);
    END IF;

    SELECT data_type INTO v_id_type 
      FROM information_schema.columns 
     WHERE table_schema = c.tgt_schema AND table_name = c.tgt_table AND column_name = v_id_col;

    v_seq_name := 'seq_' || v_stg_tbl || '_' || v_id_col;
    EXECUTE format('DROP SEQUENCE IF EXISTS stg_antam.%I', v_seq_name);
    EXECUTE format('CREATE SEQUENCE stg_antam.%I START WITH %s', v_seq_name, v_max_id + 1);

    IF v_id_type IN ('integer', 'bigint', 'smallint') THEN
      EXECUTE format('ALTER TABLE stg_antam.%I ADD COLUMN IF NOT EXISTS %I %s', v_stg_tbl, v_id_col, v_id_type);
      EXECUTE format('ALTER TABLE stg_antam.%I ALTER COLUMN %I SET DEFAULT nextval(''stg_antam.%I'')::%s',
                     v_stg_tbl, v_id_col, v_seq_name, v_id_type);
    ELSE
      EXECUTE format('ALTER TABLE stg_antam.%I ADD COLUMN IF NOT EXISTS %I text', v_stg_tbl, v_id_col);
      EXECUTE format('ALTER TABLE stg_antam.%I ALTER COLUMN %I SET DEFAULT lpad(nextval(''stg_antam.%I'')::text, %s, ''0'')',
                     v_stg_tbl, v_id_col, v_seq_name, COALESCE(c.id_width, 8));
    END IF;
  END IF;

  FOR r IN SELECT * FROM etl_antam.vw_convert_rule WHERE config_id = p_cfg LOOP
    v_src := COALESCE(r.source_column, r.column_name);
    EXECUTE format('ALTER TABLE stg_antam.%I ALTER COLUMN %I DROP DEFAULT', v_stg_tbl, r.column_name);
    IF v_src = r.column_name THEN
      EXECUTE format('ALTER TABLE stg_antam.%I ALTER COLUMN %I TYPE text USING %I::text',
                     v_stg_tbl, r.column_name, r.column_name);
    ELSE
      EXECUTE format('ALTER TABLE stg_antam.%I ALTER COLUMN %I DROP NOT NULL', v_stg_tbl, r.column_name);
      EXECUTE format('ALTER TABLE stg_antam.%I ADD COLUMN IF NOT EXISTS %I text', v_stg_tbl, v_src);
    END IF;
  END LOOP;

  -- Refresh auto mapping SQL & rollback SQL untuk target-target dari config ini
  PERFORM etl_antam.fn_refresh_target_mapping_sql(p_cfg);

  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
  CALL etl_antam.pr_fail(p_run, p_cfg, 'STAGING', 'SQL_ERROR', SQLSTATE || ' ' || SQLERRM, v_det);
  RETURN 1;
END $$;

-- 3.4 Convert Staging Source Codes to Master IDs
CREATE OR REPLACE FUNCTION etl_antam.fn_convert_staging(p_run bigint, p_cfg int)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  c etl_antam.migration_config%ROWTYPE; r record;
  v_src text; v_ms text; v_ss text; v_ss2 text; v_mf text; v_from text; v_stg_tbl text;
  v_cnt bigint; v_fail boolean := false; v_n int := 0;
  v_type text; v_cast text; v_fb text; v_extra text; v_notnull boolean; v_det text;
BEGIN
  CALL etl_antam.pr_log_step(p_run, p_cfg, 'CONVERT', 'START');
  SELECT * INTO c FROM etl_antam.migration_config WHERE config_id = p_cfg;
  v_stg_tbl := CASE WHEN c.stg_table LIKE '%_src' THEN c.stg_table ELSE c.stg_table || '_src' END;

  FOR r IN SELECT * FROM etl_antam.vw_convert_rule WHERE config_id = p_cfg ORDER BY rule_id LOOP
    v_src := COALESCE(r.source_column, r.column_name);
    v_ms  := CASE WHEN r.normalize THEN format('upper(btrim(m.%I::text))', r.master_src_col) ELSE format('m.%I::text', r.master_src_col) END;
    v_ss  := CASE WHEN r.normalize THEN format('upper(btrim(s.%I::text))', v_src) ELSE format('s.%I::text', v_src) END;
    v_mf  := CASE WHEN r.master_filter IS NOT NULL THEN ' AND (' || r.master_filter || ')' ELSE '' END;

    EXECUTE format('SELECT count(*) FROM (SELECT 1 FROM %I.%I m WHERE true%s GROUP BY %s HAVING count(*) > 1) d',
                   r.master_schema, r.master_table, v_mf, v_ms) INTO v_cnt;
    IF v_cnt > 0 THEN
      CALL etl_antam.pr_fail(p_run, p_cfg, 'CONVERT', 'MASTER_DUPLICATE',
           format('master %s.%s punya %s kode ganda pada %s', r.master_schema, r.master_table, v_cnt, r.master_src_col));
      RETURN 1;
    END IF;

    IF r.on_unmapped = 'FAIL' THEN
      v_from := format('stg_antam.%I s LEFT JOIN %I.%I m ON %s = %s%s WHERE s.%I IS NOT NULL AND m.%I IS NULL',
                       v_stg_tbl, r.master_schema, r.master_table, v_ms, v_ss, v_mf, v_src, r.master_src_col);
      EXECUTE 'SELECT count(*) FROM ' || v_from INTO v_cnt;
      IF v_cnt > 0 THEN
        v_fail := true;
        EXECUTE format($q$
          INSERT INTO etl_antam.migration_error_log
            (run_id, config_id, step_name, error_code, error_message, error_field, row_data)
          SELECT %L, %L, 'CONVERT', 'UNMAPPED_CODE', %L, %L, s.%I::text || ' (' || count(*) || ' baris)'
            FROM %s GROUP BY s.%I ORDER BY count(*) DESC LIMIT 100
        $q$, p_run, p_cfg,
             format('kode tidak ada di master %s.%s', r.master_schema, r.master_table),
             v_src, v_src, v_from, v_src);
      END IF;
    END IF;
  END LOOP;

  IF v_fail THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'CONVERT', 'UNMAPPED_CODE',
         'ada kode sumber yang tidak ditemukan di master; lihat baris UNMAPPED_CODE di migration_error_log');
    RETURN 1;
  END IF;

  FOR r IN SELECT * FROM etl_antam.vw_convert_rule WHERE config_id = p_cfg ORDER BY rule_id LOOP
    v_src := COALESCE(r.source_column, r.column_name);
    v_ms  := CASE WHEN r.normalize THEN format('upper(btrim(m.%I::text))', r.master_src_col) ELSE format('m.%I::text', r.master_src_col) END;
    v_ss2 := CASE WHEN r.normalize THEN format('upper(btrim(s2.%I::text))', v_src) ELSE format('s2.%I::text', v_src) END;
    v_mf  := CASE WHEN r.master_filter IS NOT NULL THEN ' AND (' || r.master_filter || ')' ELSE '' END;
    v_fb  := CASE WHEN r.on_unmapped = 'DEFAULT' THEN quote_nullable(r.default_value) ELSE 'NULL' END;

    IF v_src = r.column_name THEN
      v_cast := '';  v_extra := format('AND s.%I IS NOT NULL', v_src);
    ELSE
      SELECT format_type(a.atttypid, a.atttypmod) INTO v_type FROM pg_attribute a
       WHERE a.attrelid = to_regclass(format('%I.%I', c.tgt_schema, c.tgt_table))
         AND a.attname = r.column_name AND NOT a.attisdropped;
      v_cast := '::' || v_type;  v_extra := '';
    END IF;

    EXECUTE format($q$
      UPDATE stg_antam.%1$I s SET %2$I = COALESCE(x.v, %3$s)%4$s
        FROM (SELECT s2.ctid AS rid, m.%5$I::text AS v
                FROM stg_antam.%1$I s2
                LEFT JOIN %6$I.%7$I m ON %8$s = %9$s%10$s) x
       WHERE s.ctid = x.rid %11$s
    $q$, v_stg_tbl, r.column_name, v_fb, v_cast, r.master_tgt_col,
         r.master_schema, r.master_table, v_ms, v_ss2, v_mf, v_extra);
    v_n := v_n + 1;

    IF v_src = r.column_name THEN
      SELECT format_type(a.atttypid, a.atttypmod) INTO v_type FROM pg_attribute a
       WHERE a.attrelid = to_regclass(format('%I.%I', c.tgt_schema, c.tgt_table))
         AND a.attname = r.column_name AND NOT a.attisdropped;
      EXECUTE format('ALTER TABLE stg_antam.%1$I ALTER COLUMN %2$I TYPE %3$s USING %2$I::%3$s',
                     v_stg_tbl, r.column_name, v_type);
    END IF;

    SELECT a.attnotnull INTO v_notnull FROM pg_attribute a
     WHERE a.attrelid = to_regclass(format('%I.%I', c.tgt_schema, c.tgt_table))
       AND a.attname = r.column_name AND NOT a.attisdropped;
    IF v_notnull THEN
      EXECUTE format('SELECT count(*) FROM stg_antam.%I WHERE %I IS NULL', v_stg_tbl, r.column_name) INTO v_cnt;
      IF v_cnt > 0 THEN
        v_fail := true;
        EXECUTE format($q$
          INSERT INTO etl_antam.migration_error_log
            (run_id, config_id, step_name, error_code, error_message, error_field, row_data)
          SELECT %L, %L, 'CONVERT', 'NULL_AFTER_CONVERT', %L, %L,
                 COALESCE(%I::text, '(NULL)') || ' (' || count(*) || ' baris)'
            FROM stg_antam.%I WHERE %I IS NULL GROUP BY %I ORDER BY count(*) DESC LIMIT 100
        $q$, p_run, p_cfg, 'kolom target NOT NULL tetapi hasil konversi kosong', r.column_name,
             v_src, v_stg_tbl, r.column_name, v_src);
      END IF;
    END IF;
  END LOOP;

  FOR r IN SELECT DISTINCT source_column AS col FROM etl_antam.vw_convert_rule
            WHERE config_id = p_cfg AND source_column IS NOT NULL
              AND source_column <> column_name LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns ic
                    WHERE ic.table_schema = c.tgt_schema AND ic.table_name = c.tgt_table AND ic.column_name = r.col) THEN
      EXECUTE format('ALTER TABLE stg_antam.%I DROP COLUMN IF EXISTS %I', v_stg_tbl, r.col);
    END IF;
  END LOOP;

  IF v_fail THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'CONVERT', 'NULL_AFTER_CONVERT',
         'ada kolom target NOT NULL yang kosong setelah konversi; lihat migration_error_log');
    RETURN 1;
  END IF;

  CALL etl_antam.pr_log_step(p_run, p_cfg, 'CONVERT', 'OK', format('%s aturan konversi diterapkan', v_n));
  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
  CALL etl_antam.pr_fail(p_run, p_cfg, 'CONVERT', 'SQL_ERROR', SQLSTATE || ' ' || SQLERRM, v_det);
  RETURN 1;
END $$;

-- 3.5 Check Staging Verification
CREATE OR REPLACE FUNCTION etl_antam.fn_check_staging(p_run bigint, p_cfg int, p_rows_src bigint)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  c etl_antam.migration_config%ROWTYPE;
  v_stg bigint; v_dup bigint; v_pk text; v_det text; v_stg_tbl text;
BEGIN
  SELECT * INTO c FROM etl_antam.migration_config WHERE config_id = p_cfg;
  v_stg_tbl := CASE WHEN c.stg_table LIKE '%_src' THEN c.stg_table ELSE c.stg_table || '_src' END;
  EXECUTE format('SELECT count(*) FROM stg_antam.%I', v_stg_tbl) INTO v_stg;

  IF v_stg <> p_rows_src THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'STAGING', 'COUNT_MISMATCH_SRC_STG',
         format('sumber=%s staging=%s (baris ditolak ada di migration_error_log)', p_rows_src, v_stg));
    RETURN 1;
  END IF;

  SELECT string_agg(quote_ident(btrim(k)), ',') INTO v_pk FROM unnest(string_to_array(c.pk_columns, ',')) k;
  IF v_pk IS NOT NULL AND v_pk <> '' THEN
    EXECUTE format($q$
      SELECT count(*) FROM (
        SELECT %1$s FROM stg_antam.%2$I GROUP BY %1$s HAVING count(*) > 1
      ) d
    $q$, v_pk, v_stg_tbl) INTO v_dup;

    IF v_dup > 0 THEN
      CALL etl_antam.pr_fail(p_run, p_cfg, 'STAGING', 'DUPLICATE_PK_STAGING',
           format('ada %s kombinasi key duplikat di staging', v_dup));
      RETURN 1;
    END IF;
  END IF;

  CALL etl_antam.pr_log_step(p_run, p_cfg, 'STAGING', 'OK',
       format('staging terverifikasi: %s baris', v_stg), p_rows_src, v_stg);
  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
  CALL etl_antam.pr_fail(p_run, p_cfg, 'STAGING', 'SQL_ERROR', SQLSTATE || ' ' || SQLERRM, v_det);
  RETURN 1;
END $$;

-- 3.6 Check Delta Detection
CREATE OR REPLACE FUNCTION etl_antam.fn_check_delta(p_run bigint, p_cfg int)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  c etl_antam.migration_config%ROWTYPE;
  v_stg_tbl text; v_join text; v_pk1 text; v_new bigint := 0; v_exist bigint := 0; v_det text;
BEGIN
  CALL etl_antam.pr_log_step(p_run, p_cfg, 'DELTA', 'START', 'hitung data delta baru vs eksisting');
  SELECT * INTO c FROM etl_antam.migration_config WHERE config_id = p_cfg;
  v_stg_tbl := CASE WHEN c.stg_table LIKE '%_src' THEN c.stg_table ELSE c.stg_table || '_src' END;
  v_pk1     := btrim((string_to_array(c.pk_columns, ','))[1]);

  SELECT string_agg(format('s.%1$I = t.%1$I', btrim(k)), ' AND ') INTO v_join
    FROM unnest(string_to_array(c.pk_columns, ',')) k;

  EXECUTE format($q$
    SELECT count(*) FILTER (WHERE t.%1$I IS NULL),
           count(*) FILTER (WHERE t.%1$I IS NOT NULL)
      FROM stg_antam.%2$I s
      LEFT JOIN %3$I.%4$I t ON %5$s
  $q$, v_pk1, v_stg_tbl, c.tgt_schema, c.tgt_table, v_join)
  INTO v_new, v_exist;

  CALL etl_antam.pr_log_step(p_run, p_cfg, 'DELTA', 'OK',
       format('delta dihitung: %s baris baru (delta), %s baris sudah ada di target', v_new, v_exist),
       NULL, NULL, v_new, 0, 0);
  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
  CALL etl_antam.pr_fail(p_run, p_cfg, 'DELTA', 'SQL_ERROR', SQLSTATE || ' ' || SQLERRM, v_det);
  RETURN 1;
END $$;

-- 3.7 Finish Flow 1 / Flow 2 Run
CREATE OR REPLACE PROCEDURE etl_antam.pr_finish_run(
  p_run bigint,
  p_note text DEFAULT NULL,
  p_post_type text DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE 
  v_total int; 
  v_fail int; 
  v_err int; 
  v_status text;
BEGIN
  IF p_post_type IS NOT NULL THEN
    SELECT count(DISTINCT config_id),
           count(DISTINCT config_id) FILTER (WHERE status = 'FAILED')
      INTO v_total, v_fail
      FROM etl_antam.migration_step_log 
     WHERE run_id = p_run AND step_name LIKE 'POST%';

    SELECT count(*) INTO v_err 
      FROM etl_antam.migration_error_log 
     WHERE run_id = p_run AND step_name LIKE 'POST%';

    IF (v_fail > 0 OR v_err > 0) THEN
      v_status := 'FAILED';
    ELSE
      v_status := 'SUCCESS';
    END IF;

    UPDATE etl_antam.migration_run
       SET end_time = now(),
           status = v_status,
           is_posted = (v_status = 'SUCCESS'),
           posted_at = CASE WHEN v_status = 'SUCCESS' THEN now() ELSE posted_at END,
           post_type = CASE WHEN v_status = 'SUCCESS' THEN p_post_type ELSE post_type END,
           note = COALESCE(p_note, 'wf_post selesai')
     WHERE run_id = p_run;

  ELSE
    SELECT count(DISTINCT config_id),
           count(DISTINCT config_id) FILTER (WHERE status = 'FAILED')
      INTO v_total, v_fail
      FROM etl_antam.migration_step_log 
     WHERE run_id = p_run AND step_name NOT LIKE 'POST%' AND step_name NOT LIKE 'ROLLBACK%';

    SELECT count(*) INTO v_err 
      FROM etl_antam.migration_error_log 
     WHERE run_id = p_run AND step_name NOT LIKE 'POST%' AND step_name NOT LIKE 'ROLLBACK%';

    IF (v_fail > 0 OR v_err > 0) THEN
      v_status := 'FAILED';
    ELSE
      v_status := 'SUCCESS';
    END IF;

    UPDATE etl_antam.migration_run
       SET end_time = now(),
           status = v_status,
           note = COALESCE(p_note, format('%s tabel diproses, %s gagal', COALESCE(v_total, 0), COALESCE(v_fail, 0) + CASE WHEN v_err > 0 AND v_fail = 0 THEN 1 ELSE 0 END))
     WHERE run_id = p_run;
  END IF;
END $$;

-- =====================================================================
-- [SECTION 4] FLOW 2: MULTI-TARGET POST & SAFE ROLLBACK ENGINE
-- =====================================================================

-- 4.0 Auto Generator & Trigger Mapping/Rollback SQL
CREATE OR REPLACE FUNCTION etl_antam.fn_build_target_mapping_sql(
  p_config_id int,
  p_tgt_schema varchar,
  p_tgt_table varchar,
  p_pk_columns varchar,
  OUT out_mapping_sql text,
  OUT out_rollback_sql text
)
RETURNS record
LANGUAGE plpgsql
AS $$
DECLARE
  v_cfg etl_antam.migration_config%ROWTYPE;
  v_stg_schema varchar := 'stg_antam';
  v_stg_table varchar;
  v_stg_ref_schema varchar;
  v_stg_ref_table varchar;
  v_cols text;
  v_pk_cond_tgt_stg text := '';
  v_pk_cond_exists text := '';
  v_pk_arr text[];
  v_pk text;
  v_has_stg boolean;
  v_has_vendor_ref boolean := false;
BEGIN
  SELECT * INTO v_cfg FROM etl_antam.migration_config WHERE config_id = p_config_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Config ID % tidak ditemukan di migration_config', p_config_id;
  END IF;

  v_stg_table := CASE WHEN v_cfg.stg_table LIKE '%_src' THEN v_cfg.stg_table ELSE v_cfg.stg_table || '_src' END;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = v_stg_schema AND table_name = v_stg_table
  ) INTO v_has_stg;

  IF v_has_stg THEN
    v_stg_ref_schema := v_stg_schema;
    v_stg_ref_table  := v_stg_table;
  ELSE
    v_stg_ref_schema := v_cfg.tgt_schema;
    v_stg_ref_table  := v_cfg.tgt_table;
  END IF;

  SELECT string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position)
    INTO v_cols
    FROM information_schema.columns c
   WHERE c.table_schema = p_tgt_schema 
     AND c.table_name   = p_tgt_table
     AND EXISTS (
       SELECT 1 FROM information_schema.columns s
        WHERE s.table_schema = v_stg_ref_schema
          AND s.table_name   = v_stg_ref_table
          AND s.column_name  = c.column_name
     );

  IF v_cols IS NULL OR v_cols = '' THEN
    RAISE EXCEPTION 'Tidak ada kolom yang cocok antara %.% dan %.%', 
      p_tgt_schema, p_tgt_table, v_stg_ref_schema, v_stg_ref_table;
  END IF;

  v_pk_arr := string_to_array(COALESCE(NULLIF(btrim(p_pk_columns), ''), 'id'), ',');
  FOR i IN 1..array_length(v_pk_arr, 1) LOOP
    v_pk := btrim(v_pk_arr[i]);
    IF i > 1 THEN
      v_pk_cond_tgt_stg := v_pk_cond_tgt_stg || ' AND ';
    END IF;
    v_pk_cond_tgt_stg := v_pk_cond_tgt_stg || format('t.%I = s.%I', v_pk, v_pk);
  END LOOP;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
     WHERE table_schema = p_tgt_schema AND table_name = p_tgt_table AND column_name = 'vendor_reference_id'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns 
     WHERE table_schema = v_stg_ref_schema AND table_name = v_stg_ref_table AND column_name = 'vendor_reference_id'
  ) INTO v_has_vendor_ref;

  IF v_has_vendor_ref THEN
    v_pk_cond_exists := format('(%s OR (s.vendor_reference_id IS NOT NULL AND t.vendor_reference_id = s.vendor_reference_id))', v_pk_cond_tgt_stg);
  ELSE
    v_pk_cond_exists := v_pk_cond_tgt_stg;
  END IF;

  out_mapping_sql := format(
$sql$INSERT INTO %I.%I (
  %s
)
SELECT 
  %s
FROM %I.%I s
WHERE NOT EXISTS (
  SELECT 1 FROM %I.%I t 
  WHERE %s
)$sql$,
    p_tgt_schema, p_tgt_table,
    v_cols,
    v_cols,
    v_stg_schema, v_stg_table,
    p_tgt_schema, p_tgt_table,
    v_pk_cond_exists
  );

  out_rollback_sql := format(
$sql$DELETE FROM %I.%I t
WHERE EXISTS (
  SELECT 1 FROM %I.%I s
  WHERE %s
)$sql$,
    p_tgt_schema, p_tgt_table,
    v_stg_schema, v_stg_table,
    v_pk_cond_exists
  );
END;
$$;

-- 4.0b Refresh Auto Mapping SQL & Rollback SQL per Config ID
CREATE OR REPLACE FUNCTION etl_antam.fn_refresh_target_mapping_sql(p_config_id int)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  r record;
  v_res record;
  v_count int := 0;
BEGIN
  FOR r IN 
    SELECT target_config_id, config_id, tgt_schema, tgt_table, pk_columns
      FROM etl_antam.migration_target_config
     WHERE config_id = p_config_id AND is_active = true
     ORDER BY exec_order
  LOOP
    SELECT * INTO v_res 
      FROM etl_antam.fn_build_target_mapping_sql(r.config_id, r.tgt_schema, r.tgt_table, r.pk_columns);

    UPDATE etl_antam.migration_target_config
       SET mapping_sql  = v_res.out_mapping_sql,
           rollback_sql = v_res.out_rollback_sql
     WHERE target_config_id = r.target_config_id;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

-- 4.0c Trigger Function untuk Auto-Populate mapping_sql dan rollback_sql
CREATE OR REPLACE FUNCTION etl_antam.trg_fn_auto_mapping_target_config()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_res record;
BEGIN
  IF NEW.mapping_sql IS NULL OR btrim(NEW.mapping_sql) IN ('', 'tes')
     OR NEW.rollback_sql IS NULL OR btrim(NEW.rollback_sql) IN ('', 'tes') THEN
      
    SELECT * INTO v_res 
      FROM etl_antam.fn_build_target_mapping_sql(NEW.config_id, NEW.tgt_schema, NEW.tgt_table, NEW.pk_columns);

    IF NEW.mapping_sql IS NULL OR btrim(NEW.mapping_sql) IN ('', 'tes') THEN
      NEW.mapping_sql := v_res.out_mapping_sql;
    END IF;

    IF NEW.rollback_sql IS NULL OR btrim(NEW.rollback_sql) IN ('', 'tes') THEN
      NEW.rollback_sql := v_res.out_rollback_sql;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_mapping_target_config ON etl_antam.migration_target_config;
CREATE TRIGGER trg_auto_mapping_target_config
BEFORE INSERT OR UPDATE ON etl_antam.migration_target_config
FOR EACH ROW
EXECUTE FUNCTION etl_antam.trg_fn_auto_mapping_target_config();

-- 4.1 Post Target Dispatcher (Per Target Config)
CREATE OR REPLACE FUNCTION etl_antam.fn_post_target_dispatch(
  p_run bigint, 
  p_target_cfg int,
  p_batch_size int DEFAULT NULL,
  p_use_batch text DEFAULT 'Y',
  p_cfg int DEFAULT NULL
) RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  tc etl_antam.migration_target_config%ROWTYPE;
  c  etl_antam.migration_config%ROWTYPE;
  v_stg_tbl text; v_n int; v_ins bigint := 0; v_total_ins bigint := 0; 
  v_batch_cnt int := 0; v_det text; v_use_batch text;
  v_mapping_sql text;
BEGIN
  SELECT * INTO tc 
    FROM etl_antam.migration_target_config 
   WHERE target_config_id = p_target_cfg
     AND (p_cfg IS NULL OR config_id = p_cfg);

  IF NOT FOUND THEN
    IF p_cfg IS NOT NULL THEN
      CALL etl_antam.pr_fail(p_run, p_cfg, 'POST_TARGET', 'TARGET_CONFIG_MISMATCH',
           format('Target config #%s tidak ditemukan atau tidak sesuai dengan config_id %s', p_target_cfg, p_cfg));
      RETURN 1;
    END IF;
    RETURN 0;
  END IF;

  IF NOT tc.is_active THEN
    RETURN 0;
  END IF;
  SELECT * INTO c FROM etl_antam.migration_config WHERE config_id = tc.config_id;
  v_stg_tbl := CASE WHEN c.stg_table LIKE '%_src' THEN c.stg_table ELSE c.stg_table || '_src' END;

  v_use_batch := upper(btrim(COALESCE(p_use_batch, '')));

  -- Aturan Validasi Parameter Ketat:
  -- 1. Jika p_use_batch dan p_batch_size dua-duanya kosong -> ERROR
  IF (v_use_batch = '') AND (p_batch_size IS NULL) THEN
    CALL etl_antam.pr_fail(p_run, tc.config_id, 'POST_TARGET', 'INVALID_PARAMETER',
         'Parameter USE_BATCH dan BATCH_SIZE tidak boleh kosong');
    RETURN 1;
  END IF;

  -- Format default jika p_use_batch kosong tetapi p_batch_size diisi
  IF v_use_batch = '' THEN
    v_use_batch := 'Y';
  END IF;

  -- 2. Cek keabsahan nilai flag USE_BATCH
  IF v_use_batch NOT IN ('Y', 'N') THEN
    CALL etl_antam.pr_fail(p_run, tc.config_id, 'POST_TARGET', 'INVALID_USE_BATCH_FLAG',
         format('Nilai USE_BATCH (%s) tidak valid, harus Y atau N', p_use_batch));
    RETURN 1;
  END IF;

  -- 3. Jika USE_BATCH = 'Y', BATCH_SIZE wajib diisi angka > 0
  IF v_use_batch = 'Y' AND (p_batch_size IS NULL OR p_batch_size <= 0) THEN
    CALL etl_antam.pr_fail(p_run, tc.config_id, 'POST_TARGET', 'INVALID_BATCH_SIZE',
         'Untuk mode batch (USE_BATCH = Y), parameter BATCH_SIZE wajib diisi dengan angka > 0');
    RETURN 1;
  END IF;

  CALL etl_antam.pr_log_step(p_run, tc.config_id, 'POST_TARGET', 'START',
       format('post data ke %s.%s (order %s, mode %s, batch_size %s)', tc.tgt_schema, tc.tgt_table, tc.exec_order, v_use_batch, COALESCE(p_batch_size::text, 'N/A')));

  IF tc.precheck_sql IS NOT NULL AND btrim(tc.precheck_sql) <> '' THEN
    EXECUTE tc.precheck_sql INTO v_n;
    IF v_n > 0 THEN
      CALL etl_antam.pr_fail(p_run, tc.config_id, 'POST_TARGET', 'PRECHECK_FAILED',
           format('precheck gagal untuk target %s.%s (pelanggaran=%s)', tc.tgt_schema, tc.tgt_table, v_n));
      RETURN 1;
    END IF;
  END IF;

  -- Bersihkan whitespace dan tanda semicolon ';' di akhir query mapping_sql agar aman saat ditambah LIMIT
  v_mapping_sql := regexp_replace(tc.mapping_sql, '[\s;]+$', '', 'g');

  IF v_use_batch = 'Y' THEN
    LOOP
      EXECUTE v_mapping_sql || format(' LIMIT %s', p_batch_size);
      GET DIAGNOSTICS v_ins = ROW_COUNT;
      EXIT WHEN v_ins = 0;

      v_total_ins := v_total_ins + v_ins;
      v_batch_cnt := v_batch_cnt + 1;

      CALL etl_antam.pr_log_step(p_run, tc.config_id, 'POST_TARGET', 'OK',
           format('tabel target %s.%s Batch %s: %s baris diposting', tc.tgt_schema, tc.tgt_table, v_batch_cnt, v_ins),
           NULL, NULL, v_ins);
    END LOOP;
  ELSE
    -- Mode Direct (Langsung)
    EXECUTE v_mapping_sql;
    GET DIAGNOSTICS v_total_ins = ROW_COUNT;
    CALL etl_antam.pr_log_step(p_run, tc.config_id, 'POST_TARGET', 'OK',
         format('tabel target %s.%s Direct: %s baris diposting', tc.tgt_schema, tc.tgt_table, v_total_ins),
         NULL, NULL, v_total_ins);
  END IF;

  IF tc.postcheck_sql IS NOT NULL AND btrim(tc.postcheck_sql) <> '' THEN
    EXECUTE tc.postcheck_sql INTO v_n;
    IF v_n > 0 THEN
      CALL etl_antam.pr_fail(p_run, tc.config_id, 'POST_TARGET', 'POSTCHECK_FAILED',
           format('postcheck gagal untuk target %s.%s', tc.tgt_schema, tc.tgt_table));
      RETURN 1;
    END IF;
  END IF;

  CALL etl_antam.pr_log_step(p_run, tc.config_id, 'POST_TARGET', 'OK',
       format('selesai post %s baris ke %s.%s (mode %s)', v_total_ins, tc.tgt_schema, tc.tgt_table, v_use_batch),
       NULL, NULL, v_total_ins);
  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
  CALL etl_antam.pr_fail(p_run, tc.config_id, 'POST_TARGET', 'SQL_ERROR', SQLSTATE || ' ' || SQLERRM, v_det);
  RETURN 1;
END $$;

-- 4.2 Post All Targets (With Auto-Rollback on Failure)
CREATE OR REPLACE FUNCTION etl_antam.fn_post_all_targets(
  p_run bigint, 
  p_cfg int,
  p_batch_size int DEFAULT NULL,
  p_use_batch text DEFAULT 'Y'
) RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  r record; v_res int; v_n int := 0; v_det text;
BEGIN
  CALL etl_antam.pr_log_step(p_run, p_cfg, 'POST_MULTI_TARGET', 'START', format('mulai dispatch data ke multi-target (mode=%s)', p_use_batch));

  FOR r IN 
    SELECT target_config_id, tgt_schema, tgt_table 
      FROM etl_antam.migration_target_config 
     WHERE config_id = p_cfg AND is_active 
     ORDER BY exec_order, target_config_id
  LOOP
    v_res := etl_antam.fn_post_target_dispatch(p_run, r.target_config_id, p_batch_size, p_use_batch, p_cfg);
    IF v_res <> 0 THEN
      PERFORM etl_antam.fn_rollback_all_targets(p_run, p_cfg, p_run);
      RETURN 1;
    END IF;
    v_n := v_n + 1;
  END LOOP;

  CALL etl_antam.pr_log_step(p_run, p_cfg, 'POST_MULTI_TARGET', 'OK', format('selesai dispatch data ke %s target table', v_n));
  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
  CALL etl_antam.pr_fail(p_run, p_cfg, 'POST_MULTI_TARGET', 'SQL_ERROR', SQLSTATE || ' ' || SQLERRM, v_det);
  PERFORM etl_antam.fn_rollback_all_targets(p_run, p_cfg, p_run);
  RETURN 1;
END $$;

-- 4.3 Validate Rollback Trigger & Single-Use Token Guard
CREATE OR REPLACE FUNCTION etl_antam.fn_validate_rollback_trigger(
  p_run bigint, p_cfg int, p_target_run bigint DEFAULT NULL
) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  v_target_run bigint := COALESCE(p_target_run, p_run);
  v_status text;
  v_is_rolled_back boolean;
  v_post_cnt int;
  v_stg_cnt bigint;
  c etl_antam.migration_config%ROWTYPE;
  v_stg_tbl text;
BEGIN
  SELECT status, is_rolled_back INTO v_status, v_is_rolled_back 
    FROM etl_antam.migration_run WHERE run_id = v_target_run;
  IF v_status IS NULL THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'VALIDATE_ROLLBACK', 'RUN_NOT_FOUND',
         format('Rollback dibatalkan: Sesi migrasi (run_id #%s) tidak ditemukan di migration_run', v_target_run));
    RETURN -1;
  END IF;

  IF v_is_rolled_back IS TRUE THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'VALIDATE_ROLLBACK', 'ALREADY_ROLLED_BACK',
         format('Rollback dibatalkan: run_id #%s sudah pernah di-rollback dan tidak dapat di-rollback lagi.', v_target_run));
    RETURN -1;
  END IF;

  SELECT count(*) INTO v_post_cnt
    FROM etl_antam.migration_step_log
   WHERE run_id = v_target_run
     AND step_name IN ('POST_TARGET', 'POST_MULTI_TARGET');

  IF v_post_cnt = 0 THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'VALIDATE_ROLLBACK', 'NO_POST_RECORD',
         format('Rollback dibatalkan: Sesi migrasi run_id #%s belum pernah mencatat aktivitas posting data', v_target_run));
    RETURN -1;
  END IF;

  SELECT * INTO c FROM etl_antam.migration_config WHERE config_id = p_cfg;
  v_stg_tbl := CASE WHEN c.stg_table LIKE '%_src' THEN c.stg_table ELSE c.stg_table || '_src' END;

  BEGIN
    EXECUTE format('SELECT count(*) FROM stg_antam.%1$I', v_stg_tbl) INTO v_stg_cnt;
  EXCEPTION WHEN OTHERS THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'VALIDATE_ROLLBACK', 'STAGING_MISSING',
         format('Rollback dibatalkan: Tabel staging stg_antam.%s tidak ditemukan', v_stg_tbl));
    RETURN -1;
  END;

  IF v_stg_cnt = 0 THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'VALIDATE_ROLLBACK', 'STAGING_EMPTY',
         format('Rollback dibatalkan: Tabel staging stg_antam.%s kosong (0 baris), rollback dihentikan demi keamanan', v_stg_tbl));
    RETURN -1;
  END IF;

  RETURN v_target_run;
END $$;

-- 4.4 Rollback Target Dispatcher
CREATE OR REPLACE FUNCTION etl_antam.fn_rollback_target_dispatch(
  p_run bigint, p_target_cfg int, p_target_run bigint DEFAULT NULL, p_cfg int DEFAULT NULL
) RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  tc etl_antam.migration_target_config%ROWTYPE;
  c  etl_antam.migration_config%ROWTYPE;
  v_stg_tbl text; v_del bigint := 0; v_id_col text; v_pk1 text; v_det text;
BEGIN
  SELECT * INTO tc 
    FROM etl_antam.migration_target_config 
   WHERE target_config_id = p_target_cfg
     AND (p_cfg IS NULL OR config_id = p_cfg);

  IF NOT FOUND THEN
    IF p_cfg IS NOT NULL THEN
      CALL etl_antam.pr_fail(p_run, p_cfg, 'ROLLBACK_TARGET', 'TARGET_CONFIG_MISMATCH',
           format('Target config #%s tidak ditemukan atau tidak sesuai dengan config_id %s', p_target_cfg, p_cfg));
      RETURN 1;
    END IF;
    RETURN 0;
  END IF;

  IF NOT tc.is_active THEN
    RETURN 0;
  END IF;
  SELECT * INTO c FROM etl_antam.migration_config WHERE config_id = tc.config_id;
  v_stg_tbl := CASE WHEN c.stg_table LIKE '%_src' THEN c.stg_table ELSE c.stg_table || '_src' END;
  v_id_col  := NULLIF(btrim(c.id_column), '');
  v_pk1     := btrim((string_to_array(tc.pk_columns, ','))[1]);

  CALL etl_antam.pr_log_step(p_run, tc.config_id, 'ROLLBACK_TARGET', 'START',
       format('rollback data dari %s.%s (order %s)', tc.tgt_schema, tc.tgt_table, tc.exec_order));

  IF tc.rollback_sql IS NOT NULL AND btrim(tc.rollback_sql) <> '' THEN
    EXECUTE tc.rollback_sql;
    GET DIAGNOSTICS v_del = ROW_COUNT;
  ELSE
    IF v_id_col IS NOT NULL THEN
      EXECUTE format($q$
        DELETE FROM %1$I.%2$I t
         WHERE t.%3$I IN (SELECT s.%3$I FROM stg_antam.%4$I s WHERE s.%3$I IS NOT NULL)
      $q$, tc.tgt_schema, tc.tgt_table, v_id_col, v_stg_tbl);
    ELSE
      EXECUTE format($q$
        DELETE FROM %1$I.%2$I t
         WHERE t.%3$I IN (SELECT s.%3$I FROM stg_antam.%4$I s WHERE s.%3$I IS NOT NULL)
      $q$, tc.tgt_schema, tc.tgt_table, v_pk1, v_stg_tbl);
    END IF;
    GET DIAGNOSTICS v_del = ROW_COUNT;
  END IF;

  CALL etl_antam.pr_log_step(p_run, tc.config_id, 'ROLLBACK_TARGET', 'OK',
       format('berhasil rollback %s baris dari %s.%s', v_del, tc.tgt_schema, tc.tgt_table),
       NULL, NULL, NULL, NULL, v_del);
  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
  CALL etl_antam.pr_fail(p_run, tc.config_id, 'ROLLBACK_TARGET', 'SQL_ERROR', SQLSTATE || ' ' || SQLERRM, v_det);
  RETURN 1;
END $$;

-- 4.5 Rollback All Targets (Reverse Order: Child -> Parent)
CREATE OR REPLACE FUNCTION etl_antam.fn_rollback_all_targets(
  p_run bigint, p_cfg int, p_target_run bigint DEFAULT NULL
) RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  r record; v_res int; v_n int := 0; v_det text;
  v_resolved_target_run bigint;
BEGIN
  v_resolved_target_run := etl_antam.fn_validate_rollback_trigger(p_run, p_cfg, p_target_run);
  IF v_resolved_target_run < 0 THEN
    RETURN 1;
  END IF;

  CALL etl_antam.pr_log_step(p_run, p_cfg, 'ROLLBACK_MULTI_TARGET', 'START',
       format('mulai rollback data multi-target (Run ID #%s)', v_resolved_target_run));

  FOR r IN 
    SELECT target_config_id, tgt_schema, tgt_table 
      FROM etl_antam.migration_target_config 
     WHERE config_id = p_cfg AND is_active 
     ORDER BY exec_order DESC, target_config_id DESC
  LOOP
    v_res := etl_antam.fn_rollback_target_dispatch(p_run, r.target_config_id, v_resolved_target_run, p_cfg);
    IF v_res <> 0 THEN
      RETURN 1;
    END IF;
    v_n := v_n + 1;
  END LOOP;

  CALL etl_antam.pr_log_step(p_run, p_cfg, 'ROLLBACK_MULTI_TARGET', 'OK',
       format('selesai rollback data dari %s target table untuk Run ID #%s', v_n, v_resolved_target_run));
  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
  CALL etl_antam.pr_fail(p_run, p_cfg, 'ROLLBACK_MULTI_TARGET', 'SQL_ERROR', SQLSTATE || ' ' || SQLERRM, v_det);
  RETURN 1;
END $$;

-- 4.6 Finish Rollback Run Procedure (Single-Record Lifecycle)
CREATE OR REPLACE PROCEDURE etl_antam.pr_finish_rollback_run(
  p_run bigint,
  p_target_run bigint DEFAULT NULL
) LANGUAGE plpgsql AS $$
DECLARE
  v_target bigint := COALESCE(p_target_run, p_run);
  v_del_total bigint := 0;
  v_fail_cnt int := 0;
  v_err_cnt int := 0;
BEGIN
  SELECT count(*) INTO v_fail_cnt
    FROM etl_antam.migration_step_log
   WHERE run_id = v_target AND status = 'FAILED' AND step_name LIKE 'ROLLBACK%';

  SELECT count(*) INTO v_err_cnt
    FROM etl_antam.migration_error_log
   WHERE run_id = v_target AND step_name LIKE 'ROLLBACK%';

  SELECT COALESCE(sum(rows_deleted), 0) INTO v_del_total
    FROM etl_antam.migration_step_log
   WHERE run_id = v_target AND step_name LIKE 'ROLLBACK%';

  IF v_fail_cnt > 0 OR v_err_cnt > 0 THEN
    UPDATE etl_antam.migration_run
       SET end_time = now(),
           status = 'FAILED',
           note = format('wf_rollback gagal untuk Run ID #%s. Lihat etl_antam.migration_error_log', v_target)
     WHERE run_id = v_target;
  ELSE
    UPDATE etl_antam.migration_run
       SET end_time = now(),
           status = 'SUCCESS',
           is_rolled_back = true,
           rolled_back_at = now(),
           note = format('wf_rollback selesai: data target berhasil di-rollback. Total %s baris dihapus.', v_del_total)
     WHERE run_id = v_target;
  END IF;
END $$;

-- 4.7 Purge Target Data Function (Single / Multiple ID or All Data - Migration Only Guard)
CREATE OR REPLACE FUNCTION etl_antam.fn_purge_target_data(
  p_run bigint, p_cfg int, p_ids text DEFAULT NULL
) RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  r record;
  v_del_cnt bigint := 0;
  v_n int := 0;
  v_stg_tbl text;
  v_pk_col text;
  v_id_arr text[];
  v_has_mig_col boolean := false;
  v_non_mig_ids text;
  v_det text;
  c etl_antam.migration_config%ROWTYPE;
BEGIN
  SELECT * INTO c FROM etl_antam.migration_config WHERE config_id = p_cfg;
  IF NOT FOUND THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'PURGE_TARGET', 'INVALID_CONFIG', format('Config ID %s tidak ditemukan di migration_config', p_cfg));
    RETURN 1;
  END IF;

  v_stg_tbl := CASE WHEN c.stg_table LIKE '%_src' THEN c.stg_table ELSE c.stg_table || '_src' END;

  CALL etl_antam.pr_log_step(p_run, p_cfg, 'PURGE_TARGET', 'START',
       format('mulai hapus data target migrasi (IDs: %s)', COALESCE(NULLIF(btrim(p_ids), ''), 'ALL')));

  -- Parse IDs parameter jika ada
  IF p_ids IS NOT NULL AND btrim(p_ids) <> '' THEN
    SELECT array_agg(btrim(x)) INTO v_id_arr 
      FROM unnest(string_to_array(p_ids, ',')) x 
     WHERE btrim(x) <> '';
  END IF;

  FOR r IN 
    SELECT target_config_id, tgt_schema, tgt_table, pk_columns, rollback_sql
      FROM etl_antam.migration_target_config 
     WHERE config_id = p_cfg AND is_active 
     ORDER BY exec_order DESC, target_config_id DESC
  LOOP
    BEGIN
      v_pk_col := COALESCE(NULLIF(r.pk_columns, ''), 'id');

      -- Cek apakah tabel target memiliki kolom 'migration'
      SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
         WHERE table_schema = r.tgt_schema 
           AND table_name = r.tgt_table 
           AND column_name = 'migration'
      ) INTO v_has_mig_col;

      IF v_id_arr IS NOT NULL AND array_length(v_id_arr, 1) > 0 THEN
        -- 1. Pengecekan KETAT: Cek apakah ada ID yang berada di target tetapi BUKAN data migrasi
        -- (yaitu flag migration <> 1/Y ATAU data tidak ditemukan di staging)
        IF v_has_mig_col THEN
          EXECUTE format(
            'SELECT string_agg(x, %L) FROM unnest(%L::varchar[]) x WHERE EXISTS (SELECT 1 FROM %I.%I t WHERE t.%I = x AND (t.migration IS NULL OR t.migration NOT IN (%L, %L) OR NOT EXISTS (SELECT 1 FROM stg_antam.%I s WHERE s.%I = t.%I)))',
            ', ', v_id_arr, r.tgt_schema, r.tgt_table, v_pk_col, '1', 'Y', v_stg_tbl, v_pk_col, v_pk_col
          ) INTO v_non_mig_ids;
        ELSE
          EXECUTE format(
            'SELECT string_agg(x, %L) FROM unnest(%L::varchar[]) x WHERE EXISTS (SELECT 1 FROM %I.%I t WHERE t.%I = x AND NOT EXISTS (SELECT 1 FROM stg_antam.%I s WHERE s.%I = t.%I))',
            ', ', v_id_arr, r.tgt_schema, r.tgt_table, v_pk_col, v_stg_tbl, v_pk_col, v_pk_col
          ) INTO v_non_mig_ids;
        END IF;

        IF v_non_mig_ids IS NOT NULL THEN
          CALL etl_antam.pr_fail(p_run, p_cfg, 'PURGE_TARGET', 'NOT_MIGRATION_DATA',
               format('Penghapusan dibatalkan untuk ID (%s): Data di %s.%s bukan berasal dari migrasi (migration flag <> 1/Y atau tidak ada di staging). Data non-migrasi tidak dapat dihapus.', v_non_mig_ids, r.tgt_schema, r.tgt_table));
          RETURN 1;
        END IF;

        -- 2. Hapus data migrasi
        IF v_has_mig_col THEN
          EXECUTE format('DELETE FROM %I.%I t WHERE t.%I = ANY(%L::varchar[]) AND (t.migration = %L OR t.migration = %L) AND EXISTS (SELECT 1 FROM stg_antam.%I s WHERE s.%I = t.%I)',
                         r.tgt_schema, r.tgt_table, v_pk_col, v_id_arr, '1', 'Y', v_stg_tbl, v_pk_col, v_pk_col);
        ELSE
          EXECUTE format('DELETE FROM %I.%I t WHERE t.%I = ANY(%L::varchar[]) AND EXISTS (SELECT 1 FROM stg_antam.%I s WHERE s.%I = t.%I)',
                         r.tgt_schema, r.tgt_table, v_pk_col, v_id_arr, v_stg_tbl, v_pk_col, v_pk_col);
        END IF;
        GET DIAGNOSTICS v_del_cnt = ROW_COUNT;

        IF v_del_cnt = 0 THEN
          CALL etl_antam.pr_log_error(p_run, p_cfg, 'PURGE_TARGET', 'ID_NOT_FOUND',
               format('Data dengan ID (%s) tidak ditemukan pada tabel target %s.%s', p_ids, r.tgt_schema, r.tgt_table));
        END IF;
      ELSE
        -- Mode All Data: Hapus seluruh data migrasi saja
        IF v_has_mig_col THEN
          EXECUTE format('DELETE FROM %I.%I t WHERE (t.migration = %L OR t.migration = %L) AND EXISTS (SELECT 1 FROM stg_antam.%I s WHERE s.%I = t.%I)',
                         r.tgt_schema, r.tgt_table, '1', 'Y', v_stg_tbl, v_pk_col, v_pk_col);
        ELSE
          IF r.rollback_sql IS NOT NULL AND btrim(r.rollback_sql) <> '' THEN
            EXECUTE r.rollback_sql;
          ELSE
            EXECUTE format('DELETE FROM %I.%I t WHERE EXISTS (SELECT 1 FROM stg_antam.%I s WHERE s.%I = t.%I)',
                           r.tgt_schema, r.tgt_table, v_stg_tbl, v_pk_col, v_pk_col);
          END IF;
        END IF;
        GET DIAGNOSTICS v_del_cnt = ROW_COUNT;
      END IF;

      CALL etl_antam.pr_log_step(p_run, p_cfg, 'PURGE_TARGET', 'OK',
           format('tabel target %s.%s: %s baris data migrasi dihapus', r.tgt_schema, r.tgt_table, v_del_cnt),
           NULL, NULL, NULL, NULL, v_del_cnt);
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
      CALL etl_antam.pr_fail(p_run, p_cfg, 'PURGE_TARGET', 'DELETE_ERROR',
           format('gagal hapus data dari %s.%s: %s', r.tgt_schema, r.tgt_table, SQLERRM), v_det);
      RETURN 1;
    END;
  END LOOP;

  IF v_n = 0 THEN
    CALL etl_antam.pr_fail(p_run, p_cfg, 'PURGE_TARGET', 'NO_TARGET_CONFIG',
         format('Tidak ada tabel target aktif di migration_target_config untuk config_id %s', p_cfg));
    RETURN 1;
  END IF;

  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_det = PG_EXCEPTION_DETAIL;
  CALL etl_antam.pr_fail(p_run, p_cfg, 'PURGE_TARGET', 'SQL_ERROR', SQLSTATE || ' ' || SQLERRM, v_det);
  RETURN 1;
END $$;

-- =====================================================================
-- [SECTION 5] KONFIGURASI AKTIF & TARGET DISPATCH SEEDING (REPLACE ON CONFLICT)
-- =====================================================================

-- 5.1 Main Config: v_migration_vendor -> stg_vendors_src
INSERT INTO etl_antam.migration_config
 (exec_order, src_schema, src_view, tgt_schema, tgt_table, stg_table, pk_columns, compare_columns,
  id_column, id_width, id_seed, src_precheck_sql)
VALUES (
  1, 
  'dbo', 
  'v_migration_vendor', 
  'vendor', 
  'slave_vendors', 
  'stg_vendors_src', 
  'id',
  'vendor_reference_id,uuid,name,vendor_type_id,purchasing_org_id,email,website,company_type_id,status,created_at,sap_code,tipe_verifikasi,last_tipe_verifikasi,migration,status_inactive,tipe_vendor,created_by_role',
  'id', 8, 1031,
  $sql$SELECT
  (SELECT COUNT(*) FROM (SELECT vh.vendor_id
                         FROM vnd_header vh
                         LEFT JOIN vnd_address va ON vh.vendor_id = va.vendor_id
                         GROUP BY vh.vendor_id HAVING COUNT(*) > 1) d)
+ (SELECT COUNT(*) FROM vnd_header
    WHERE email_address IS NULL OR CHARINDEX('@', email_address) = 0) AS n$sql$)
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

-- 5.2 Target 1: vendor.slave_vendors (exec_order = 1, rollback_order = 2)
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

-- 5.3 Target 2: vendor.vendors (exec_order = 2, rollback_order = 1)
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
