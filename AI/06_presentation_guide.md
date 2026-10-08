# Panduan & Naskah Presentasi Proyek Migrasi Data
## Topik: Edukasi Konsep Migrasi, Arsitektur Apache Hop, Cara Menjalankan Flow, dan Konfigurasi Metadata
**Target Audiens**: Tim Proyek Lengkap (Project Manager, Solution Architect, Data Engineer, DB Admin, QA)

---

![Slide 0: Cover Presentation](/Users/macbookair/.gemini/antigravity-ide/brain/a1bf5770-a09b-43a7-8a72-699d715af417/slide0_cover_1791400611801.jpg)

### 📌 Poin Penyampaian Cover:
- **Judul Utama**: Sistem ETL & Migrasi Data (SQL Server ke PostgreSQL)
- **Subjudul**: Arsitektur Metadata-Driven & Apache Hop Orchestration
- **Tujuan Utama Presentasi**: 
  1. Mengedukasi tim proyek mengenai **Konsep & Strategi Migrasi Data** berbasis *Layered Staging*.
  2. Menjelaskan implementasi teknis menggunakan Apache Hop & PostgreSQL PL/pgSQL Engine.
  3. Menjelaskan skema metadata konfigurasi agar tim dapat menambah tabel baru secara mandiri tanpa mengubah kode.
  4. Memperagakan cara mengeksekusi 4 Flow Utama (`wf_main.hwf`, `wf_post.hwf`, `wf_rollback.hwf`, `wf_purge_target.hwf`).

> **🎨 Prompt Visual Slide Cover (Light Mode Premium)**:
> ```text
> Create a highly professional, widescreen 16:9 presentation title cover slide for an Enterprise Data Migration Project in a LIGHT MODE PREMIUM theme. Title: "DATA MIGRATION & ETL SYSTEM", Subtitle: "SQL Server to PostgreSQL Migration with Metadata-Driven Architecture & Apache Hop Orchestration". Visual Style: Ultra-clean light modern tech aesthetic, crisp light slate white background (#F8FAFC) with subtle geometric grid accent lines. Soft white elevated floating glassmorphism cards with smooth drop shadows. Central Diagram: Architectural data flow showing SQL Server source view (v_migration_vendor) on the left, passing through Apache Hop Orchestration nodes in the center, landing into PostgreSQL target (vendor.vendors) on the right. Floating cards highlight 4 core workflows: "Flow 1: Landing Staging", "Flow 2: Batch Posting", "Flow 3: Safe Rollback", and "Flow 4: Target Purge". Color Palette: Deep royal blue (#1E3A8A / #2563EB) headings, vibrant teal (#0D9488) process lines, emerald green (#059669) safety badges, and crisp dark navy text (#0F172A). Typography: Sharp, high-contrast bold modern sans-serif typography, highly legible for executives and architects. Ultra-high quality 8k resolution vector presentation slide design.
> ```

---

## 📋 Agenda Presentasi (Alokasi Waktu: 45 Menit)

![Slide 1: Agenda Presentasi 45 Menit](/Users/macbookair/.gemini/antigravity-ide/brain/a1bf5770-a09b-43a7-8a72-699d715af417/slide1_agenda_1791400637607.jpg)

| Waktu | Sesi Presentasi | Fokus Diskusi & Poin Penyampaian | Visual Slide |
|---|---|---|---|
| 00 - 05 min | **1. Konsep & Strategi Migrasi Data** | Konsep arsitektur 4-Flow, Metadata-Driven, Idempotency, dan perbandingan vs *direct migration*. | Slide 0 & 1 |
| 05 - 15 min | **2. Arsitektur Implementasi Apache Hop & Database** | Peran Hop sebagai Orchestrator vs PostgreSQL sebagai Engine, serta penyelesaian masalah JDBC. | Slide 2 |
| 15 - 22 min | **3. Fitur-Fitur Utama Sistem Migrasi Data** | Bedah 8 Fitur Utama yang dibangun (Landing Staging, LPAD ID, Master Code Conversion, Multi-Target Batch Posting, Rollback, Purge Guard, dsb). | Slide 3 |
| 22 - 30 min | **4. Penjelasan Master Konfigurasi Metadata** | Bedah 4 skema tabel metadata (`migration_config`, `target_config`, `lookup`, & `rules`). | Slide 4 |
| 30 - 38 min | **5. Cara Menjalankan 4 Flow Utama (Demo/Guide)** | Langkah eksekusi `wf_main.hwf`, `wf_post.hwf` (Batch vs Direct), `wf_rollback.hwf`, & `wf_purge_target.hwf`. | Slide 5 |
| 38 - 45 min | **6. Tanya Jawab (Q&A) & Penutup** | Antisipasi pertanyaan teknis & operasional dari tim proyek (PM, Arch, QA, DB Admin). | Slide 6 |

> **🎨 Prompt Visual Slide Agenda Presentasi (Light Mode Premium)**:
> ```text
> Create a highly professional, widescreen 16:9 presentation agenda slide for an Enterprise Data Migration Technical Education Session in a LIGHT MODE PREMIUM theme. Title: "PRESENTATION AGENDA (45 MINUTES)", Subtitle: "6 Core Technical & Strategic Sessions". Visual Style: Ultra-clean light modern tech aesthetic, crisp light slate white background (#F8FAFC) with subtle geometric accent grid lines. 6 elevated soft white rectangular cards arranged in a clean 2x3 grid or linear timeline flow with smooth drop shadows and thin borders (#E2E8F0). Card Contents with exact timings: Card 1: "01. Konsep & Strategi Migrasi (00-05 min) - Layered Staging vs Direct", Card 2: "02. Arsitektur Hop & PostgreSQL (05-15 min) - PL/pgSQL & CTE JDBC Fix", Card 3: "03. Fitur-Fitur Utama Sistem (15-22 min) - 8 Features & Out-of-Scope", Card 4: "04. Master Konfigurasi Metadata (22-30 min) - 4 SQL Config Tables", Card 5: "05. Cara Menjalankan 4 Flow (30-38 min) - Demo & Process Flows", Card 6: "06. Q&A & Diskusi Tim (38-45 min) - Technical Answers for PM/DBA/DE/QA/Security". Color Palette: Deep royal blue (#1E3A8A / #2563EB) headers, vibrant teal (#0D9488) timeline badges, dark navy (#0F172A) text. Typography: Bold modern sans-serif typography, crisp executive layout. Ultra-high quality 8k resolution vector presentation slide design.
> ```

---

## 🎯 BAGIAN 1: Konsep & Strategi Migrasi Data yang Dibangun (00 - 05 Min)

![Slide 1 Visual: Konsep & Strategi Migrasi Data](/Users/macbookair/.gemini/antigravity-ide/brain/a1bf5770-a09b-43a7-8a72-699d715af417/slide1_konsep_strategi_1791400660234.jpg)

> **🎨 Prompt Visual Slide Bagian 1 (Light Mode Premium)**:
> ```text
> Create a highly professional, widescreen 16:9 presentation slide for Data Migration Concept and Strategy in a LIGHT MODE PREMIUM theme. Title: "CONCEPT & MIGRATION STRATEGY", Subtitle: "Metadata-Driven Layered Staging Architecture". Visual Style: Ultra-clean light modern tech aesthetic, crisp light slate white background (#F8FAFC). Central Layout: 5 connected process blocks (1. Landing Staging Isolation in stg_vendors_src, 2. Cleansing & LPAD 8-Digit ID Format 00001032, 3. Delta Calculation via WHERE NOT EXISTS, 4. Multi-Target Batch Posting per 1000 rows, 5. Governance & Audit Logs in migration_run). On the right side, a comparative card box shows "Layered Staging Advantage (Zero Source Lock, Isolated Buffer, Controlled Batch Chunking)" versus "Direct Migration Disadvantage (Source Table Locking, Network Disruption Vulnerability, No Buffer Area)". Color Palette: Deep royal blue (#1E3A8A / #2563EB) headers, vibrant teal (#0D9488) connections, emerald green (#059669) safety badges, dark navy (#0F172A) text. Typography: Bold modern sans-serif typography, executive visual presentation. Ultra-high quality 8k resolution vector presentation slide design.
> ```

### 📌 Konsep & Strategi Migrasi Data Utama Saat Ini (To The Point)

Secara garis besar, strategi migrasi data yang kita bangun saat ini adalah **Metadata-Driven Layered Staging Migration System** berbasis **PostgreSQL Engine & Apache Hop Orchestration**.

Sistem ini tidak memindahkan data secara mentah (*direct script*), melainkan menggunakan strategi 5-tahap terstruktur:

1. **Penarikan & Isolasi Data (Staging Layer)**:
   - Data ditarik dari SQL Server View (`v_migration_vendor`) secara *read-only* (zero table locking pada sistem legacy) dan didaratkan di PostgreSQL staging (`stg_vendors_src`).
2. **Pembersihan & Penyesuaian Format Data (Data Cleansing & Standardizing)**:
   - Format ID Vendor disatukan menjadi **LPAD 8-Digit** (misal `1031` ➔ `00001031`, `1032` ➔ `00001032`).
   - Kode master/referensi legacy (tipe vendor, tipe perusahaan) dikonversi secara otomatis ke ID master target menggunakan aturan terpusat di `vw_convert_rule`.
3. **Kalkulasi Delta Data (Delta & New/Existing Separator)**:
   - Sistem secara otomatis menghitung mana data BARU (belum ada di target) dan mana data yang sudah ada, sehingga mencegah terjadinya duplikasi ID atau duplikasi transaksi.
4. **Pengiriman Terkontrol ke Banyak Tabel Target (Multi-Target Batch Posting)**:
   - Data staging yang bersih diposting ke tabel target utama (`vendor.slave_vendors` dan `vendor.vendors`) secara berurutan (*exec order*) dengan mode **Batch Chunking (1.000 baris per iterasi)** untuk mengeliminasi risiko database lock dan menjaga performa server target.
5. **Keamanan & Tata Kelola Lengkap (Audit, Safe Rollback & Purge Guard)**:
   - Setiap transaksi migrasi dicatat lengkap per `run_id` (`migration_run`, `migration_step_log`, `migration_error_log`).
   - Dilengkapi fitur pembatalan sesi (*Rollback*) dan fitur pembersihan (*Purge*) dengan **Dual-Guard Protection** (hanya data ber-flag `migration = '1'` dan ada di staging yang dapat dihapus; data produksi non-migrasi dijamin 100% aman).

---

### Poin-Poin Penyampaian Detail (Point per Point):

#### 1. Rincian Alur Strategi 4-Flow
Tunjukkan bagaimana 5 tahap di atas diimplementasikan secara teknis ke dalam **4 Flow Utama**:

- **Flow 1 (Landing, Transformation & Delta Check)**:
  Penarikan data dari SQL Server View (`v_migration_vendor`) mendarat di PostgreSQL Staging (`stg_vendors_src`). Di staging ini dilakukan penyesuaian ID vendor LPAD 8-digit (`00001032`), konversi kode master ke ID target, serta kalkulasi delta data baru vs eksisting.
- **Flow 2 (Multi-Target Posting Engine)**:
  Pemindahan data terkonversi dari staging ke tabel-tabel target utama (`vendor.slave_vendors` dan `vendor.vendors`) secara aman dengan pilihan mode **Batch (Chunked per 1.000 baris)** atau **Direct Insert**.
- **Flow 3 (Safe Rollback Engine)**:
  Mekanisme pembatalan data migrasi spesifik per `run_id` dengan proteksi *Single-Use Token Guard* untuk memastikan keamanan audit data.
- **Flow 4 (Purge Target Engine)**:
  Fitur pembersihan data migrasi pada tabel target secara presisi tanpa sedikit pun menyentuh atau merusak data produksi/non-migrasi.

#### 2. Tiga Pilar Utama Strategi Migrasi Data
Jelaskan 3 prinsip fundamental arsitektur kita:
- **Pilar 1: Metadata-Driven (Tanpa Hardcoding)**:  
  Seluruh aturan pemetaan, konversi kode, dan target query disimpan di tabel konfigurasi SQL (`migration_config`, `migration_target_config`, `migration_lookup`, `migration_convert_rule`). Jika ada tabel baru di kemudian hari, developer **cukup menambah baris SQL config tanpa perlu mengubah kode Apache Hop**.
- **Pilar 2: Idempotency (Aman Dijalankan Berulang)**:  
  Seluruh query posting dan penyiapan data dirancang *idempotent* (menggunakan `WHERE NOT EXISTS` dan `ON CONFLICT`). Jika proses migrasi terhenti di tengah jalan akibat masalah jaringan, rerun akan melanjutkan data sisa tanpa risiko duplikasi data.
- **Pilar 3: Complete Audit Trail & Visibility (Single-Record Lifecycle)**:  
  Setiap eksekusi memiliki pelacakan lengkap. Status sesi disederhanakan secara tegas (`RUNNING`, `SUCCESS`, `FAILED`), tipe posting dicatat di kolom `post_type` (`BATCH` / `DIRECT`), serta seluruh siklus (Staging -> Posting -> Rollback) tercatat dalam 1 data tunggal pada `migration_run`, `migration_step_log`, dan `migration_error_log`.

#### 3. Mengapa Strategi Ini Dipilih dibanding Direct Migration (Direct Source to Target)?
Setelah konsep dasar dipahami tim, bandingkan dengan pendekatan tradisional (*Direct Migration*):
- ❌ **Kelemahan Direct Migration**:
  - Penarikan langsung antar-database tanpa buffer staging rentan terputus di tengah jalan akibat jaringan.
  - Query ekstraksi berdurasi panjang mengunci (*lock*) tabel produksi SQL Server sehingga mengganggu operasional sistem legacy.
  - Tidak ada tempat penampungan sementara (*staging area*) untuk mengisolasi data yang rusak, serta menyulitkan debugging jika terjadi kesalahan di baris data ke-90.000.
- ✅ **Keunggulan Strategi Layered Staging yang Kita Buat**:
  - Penarikan data dari SQL Server berlangsung sangat cepat (*bulk read*) lalu koneksi langsung dilepas (*zero source locking*).
  - Seluruh manipulasi data (penyesuaian LPAD ID & konversi kode) dilakukan di PostgreSQL Staging yang terisolasi.
  - Posting ke tabel target produksi dilakukan secara terkontrol dan dapat diposting per batch kecil (*batch chunking*) sehingga tidak mengunci tabel produksi target.

---

## ⚙️ BAGIAN 2: Arsitektur Implementasi Apache Hop & Database (05 - 15 Min)

![Slide 2 Visual: Arsitektur Implementasi Apache Hop & PostgreSQL](/Users/macbookair/.gemini/antigravity-ide/brain/a1bf5770-a09b-43a7-8a72-699d715af417/slide2_arsitektur_hop_1791400681782.jpg)

> **🎨 Prompt Visual Slide Bagian 2 (Light Mode Premium)**:
> ```text
> Create a highly professional, widescreen 16:9 technical architecture slide for Apache Hop and Database Implementation in a LIGHT MODE PREMIUM theme. Title: "IMPLEMENTATION ARCHITECTURE", Subtitle: "Hybrid Orchestration & High-Performance Database Engine". Visual Style: Ultra-clean light modern tech aesthetic, crisp slate white background (#F8FAFC). Split Architecture Layout: Left Box "Apache Hop Orchestrator Layer" detailing wf_main.hwf, wf_post.hwf, pl_init_run.hpl, Bulk Streamer, and CTE Statement Wrapper (WITH ins AS (INSERT...) SELECT...). Right Box "PostgreSQL PL/pgSQL Database Engine Layer" detailing fn_init_migration_run, fn_convert_staging, fn_post_all_targets, fn_rollback_run, and fn_purge_target_data. Central connector displays "High-Speed JDBC Data Pipe & Control Signal Flow". Color Palette: Deep royal blue (#1E3A8A / #2563EB) box headers, vibrant teal (#0D9488) pipeline arrows, emerald green (#059669) function badges, dark navy (#0F172A) text. Typography: Clean bold technical sans-serif typography, highly legible for solution architects. Ultra-high quality 8k resolution vector presentation slide design.
> ```

### 📌 Arsitektur Implementasi Hop & Database Utama Saat Ini (To The Point)

Secara arsitektural, sistem migrasi yang kita bangun menggunakan pola **Hybrid Orchestration & Database Engine Architecture**:  
**Apache Hop bertindak sebagai Orchestrator & Fast Data Streamer**, sedangkan **PostgreSQL Database Engine bertindak sebagai Heavy Execution Layer (Transformasi, Konversi, Delta Calculation, & Multi-Target Posting)**.

Pembagian peran (*Separation of Concerns*) ini dirancang secara presisi agar setiap komponen menangani tugas yang paling optimal:

1. **Apache Hop Layer (Orchestrator & Transport Layer)**:
   - **Tugas**: Mengatur urutan eksekusi (*workflow orchestration*), melempar variabel/parameter (`CONFIG_ID`, `RUN_ID`, `USE_BATCH`, `BATCH_SIZE`), melakukan streaming ekstraksi cepat (*bulk read*) dari SQL Server ke PostgreSQL Staging, serta menangani error handling & logging UI.
   - **Alasan**: Apache Hop sangat efisien untuk streaming I/O antar-database dan orchestration alur kerja, namun **tidak dibebani logika transformasi rumit di memori Java Hop** agar eksekusi cepat dan tidak memicu *Out of Memory (OOM)*.

2. **PostgreSQL Database Engine Layer (Execution & Storage Layer)**:
   - **Tugas**: Menjalankan seluruh logika manipulasi data tingkat lanjut menggunakan Stored Functions (PL/pgSQL), yaitu penyesuaian format **LPAD 8-digit**, otomatisasi **lookup code conversion** berbasis `vw_convert_rule`, kalkulasi **delta data baru vs eksisting**, pencatatan **audit trail**, serta **multi-target batch posting**.
   - **Alasan**: Database PostgreSQL mampu memproses puluhan ribu baris data secara *set-based SQL* di dalam engine database itu sendiri dalam hitungan milidetik, jauh lebih cepat dibanding memproses baris per baris (*row-by-row*) di ETL tool.

3. **Inter-System Communication Protocol & CTE Wrapper (JDBC Handling)**:
   - Antara Apache Hop dan PostgreSQL dihubungkan melalui JDBC Connection standar.
   - Untuk memicu stored procedure/function yang mengembalikan ResultSet di pipeline inisialisasi (`pl_init_run.hpl`), kita menerapkan **CTE Statement Wrapping (`WITH ins AS (INSERT INTO ...) SELECT ... FROM ins`)**. Solusi ini mengeliminasi masalah bawaan PostgreSQL JDBC driver *PSQLException: No results were returned by the query*.

---

### Poin-Poin Penyampaian Detail (Point per Point):

#### 1. Rincian Komponen Apache Hop (Orchestration Components)
- **Workflows (`.hwf`)**: Sebagai pengontrol alur utama (`wf_main.hwf`, `wf_post.hwf`, `wf_rollback.hwf`, `wf_purge_target.hwf`). Menangani alur sukses/gagal, passing parameter, dan percabangan logika.
- **Pipelines (`.hpl`)**: Sebagai pelaksana tugas I/O spesifik (`pl_init_run.hpl`, `pl_extract_to_staging.hpl`). Mengalirkan data dari SQL Server View (`v_migration_vendor`) ke PostgreSQL staging (`stg_vendors_src`).

#### 2. Rincian Komponen Database PostgreSQL (Engine & Metadata Components)
- **Staging Schema (`stg_antam`)**: Penampung data mentah terisolasi (`stg_vendors_src`).
- **Core PL/pgSQL Engine (`sql/01_ddl_and_functions.sql`)**:
  - `fn_init_migration_run`: Membuat `run_id` baru dan mengosongkan staging.
  - `fn_convert_staging`: Eksekusi transformasi massal (LPAD ID, konversi lookup, kalkulasi delta).
  - `fn_post_all_targets` & `fn_post_target_dispatch`: Memposting data ke multi-target (`vendor.slave_vendors` & `vendor.vendors`) dengan opsi **Direct Mode** atau **Batch Chunking Mode (1.000 baris)**.
  - `fn_rollback_migration_run`: Menghapus data posting per `run_id` dengan proteksi *Single-Use Token Guard*.
  - `fn_purge_target_data`: Penghapusan data migrasi dengan proteksi *Dual-Guard Protection*.
- **Metadata & Log Schema (`etl_antam`)**:
  - 4 Tabel Konfigurasi (`migration_config`, `migration_target_config`, `migration_lookup`, `migration_convert_rule`).
  - 3 Tabel Log Audit (`migration_run`, `migration_step_log`, `migration_error_log`).

#### 3. Rantai Eksekusi Hibrida Hop-PostgreSQL (Bagaimana Keduanya Bekerja Sama)
1. **Hop Trigger**: `wf_main.hwf` memicu pipeline inisialisasi `pl_init_run.hpl`.
2. **Database Register**: PostgreSQL mencatat baris baru di `migration_run` dan mengembalikan `run_id` (misal `105`) ke Hop.
3. **Hop Stream Data**: Hop melakukan *bulk read* dari SQL Server View dan memasukkan data mentah ke `stg_vendors_src`.
4. **Database Heavy Processing**: Hop mengeksekusi `SELECT etl_antam.fn_convert_staging(105, 1)`. Engine PostgreSQL melakukan LPAD ID & konversi kode master secara instan.
5. **Database Multi-Target Posting**: Hop mengeksekusi `wf_post.hwf` yang memicu `fn_post_all_targets`. Engine PostgreSQL menyalurkan data ke `vendor.slave_vendors` dan `vendor.vendors` per batch 1.000 baris.
6. **Hop Log & Close**: Hop mencatat status `SUCCESS` di log audit dan menyelesaikan sesi.

---

## 🛠️ BAGIAN 3: Fitur-Fitur Utama Sistem Migrasi Data yang Dibangun (15 - 22 Min)

![Slide 3 Visual: 8 Fitur Utama Sistem Migrasi Data](/Users/macbookair/.gemini/antigravity-ide/brain/a1bf5770-a09b-43a7-8a72-699d715af417/slide3_fitur_utama_1791400705560.jpg)

> **🎨 Prompt Visual Slide Bagian 3 (Light Mode Premium)**:
> ```text
> Create a highly professional, widescreen 16:9 feature showcase slide for an Enterprise Data Migration System in a LIGHT MODE PREMIUM theme. Title: "CORE MIGRATION SYSTEM FEATURES", Subtitle: "8 Production-Ready Features & Scope Boundaries". Visual Style: Ultra-clean light modern tech aesthetic, crisp light slate white background (#F8FAFC). Left Section: 8 elevated soft white cards displaying built features (1. Landing Staging Isolation, 2. LPAD 8-Digit ID Auto Generator 00001032, 3. Dynamic Master Code Conversion via vw_convert_rule, 4. Delta Check & Idempotency Guard, 5. Multi-Target Batch Posting Engine USE_BATCH/BATCH_SIZE, 6. Transactional Safe Rollback with Single-Use Token, 7. Target Data Purge with Dual-Guard Protection, 8. Real-time Audit Trail & CTE Solution). Right Section: Alert Banner "Out-of-Scope Boundaries (Batch Focus, Pre-Defined Schemas, No Real-Time CDC, No Custom Web GUI)". Color Palette: Deep royal blue (#1E3A8A / #2563EB) headers, vibrant teal (#0D9488) icons, emerald green (#059669) checkmarks, dark navy (#0F172A) text. Typography: Sharp modern sans-serif typography, executive feature checklist layout. Ultra-high quality 8k resolution vector presentation slide design.
> ```

### 📌 Ringkasan 8 Fitur Utama yang Siap Dioperasikan (To The Point)

Sebelum kita membedah tabel konfigurasi metadata, jelaskan terlebih dahulu kepada tim proyek **8 Fitur Utama yang Sudah Berhasil Kita Bangun dan Siap Dioperasikan saat ini**:

1. **Fitur Automated Landing & Isolation Layer (`wf_main.hwf`)**:
   - Menarik data secara *bulk read* dari SQL Server View (`v_migration_vendor`) ke PostgreSQL Staging (`stg_vendors_src`) tanpa menyebabkan *table locking* pada sistem legacy sumber.
2. **Fitur Generator ID Otomatis LPAD Format**:
   - Otomatisasi penyesuaian ID Vendor berformat **LPAD 8-Digit** (misal `1031` ➔ `00001031`, `1032` ➔ `00001032`) berdasarkan nilai seed dan lebar digit di tabel konfigurasi.
3. **Fitur Dynamic Master Code Conversion Engine**:
   - Mengonversi kode legacy ke ID master target (seperti Tipe Vendor `V01` ➔ `1`, Tipe Perusahaan `PT` ➔ `2`) secara otomatis via `vw_convert_rule`.
   - Mendukung aturan pencocokan gabungan kolom (*composite keys*).
   - Penanganan otomatis jika kode tidak dikenal (`on_unmapped = 'FAIL'`) yang menghentikan migrasi dan mencatat baris bermasalah ke `migration_error_log` (`UNMAPPED_CODE`).
4. **Fitur Calculation Delta & Idempotency Guard**:
   - Memisahkan data BARU vs data yang sudah ada di target secara otomatis (`WHERE NOT EXISTS`), sehingga aman jika workflow di-rerun berulang kali tanpa membuat duplikasi.
5. **Fitur Multi-Target Batch Posting Engine (`wf_post.hwf`)**:
   - Memindahkan data staging ke 1 atau banyak tabel target utama (`vendor.slave_vendors` dan `vendor.vendors`) berdasarkan parameter wajib **`RUN_ID`**.
   - Menyediakan 2 Mode Posting: **Mode Batch Chunking (`USE_BATCH = 'Y'`, `BATCH_SIZE = 1000`)** per 1.000 baris untuk menjaga performa DB target vs **Mode Direct (`USE_BATCH = 'N'`)**.
   - Dilengkapi validasi parameter ketat (`INVALID_PARAMETER` & `INVALID_BATCH_SIZE`), serta proteksi anti-duplicate posting (`ALREADY_POSTED`) dan penolakan posting pada sesi rollback (`ALREADY_ROLLED_BACK`).
   - Menyimpan tipe posting di kolom **`post_type`** (`BATCH (1000)` / `DIRECT`) dan menandai `is_posted = true`.
6. **Fitur Single-Record Safe Rollback Engine (`wf_rollback.hwf`)**:
   - Menghapus data target yang diposting oleh sesi `RUN_ID` tertentu secara transaksional pada **baris data yang sama** (tanpa membuat baris run baru).
   - Memperbarui baris tersebut menjadi `is_rolled_back = true`, mengisi `rolled_back_at`, dan status tetap `SUCCESS`.
   - Dilengkapi proteksi guard: Menolak rollback jika data belum diposting (`NOT_POSTED_YET`) dan menolak rollback berulang (`ALREADY_ROLLED_BACK`).
7. **Fitur Presisi Target Data Purge dengan Dual-Guard Protection (`wf_purge_target.hwf`)**:
   - Pembersihan data migrasi pada tabel target secara terkontrol.
   - Proteksi **Dual-Guard**: Menolak penghapusan jika data tidak memiliki flag `migration = '1'` ATAU tidak tercatat di staging (`NOT_MIGRATION_DATA`). **Data produksi non-migrasi dijamin 100% aman**.
8. **Fitur Audit Trail & Logging Real-time**:
   - Pencatatan otomatis riwayat eksekusi, waktu, jumlah baris data, dan traceback error di `migration_run`, `migration_step_log`, dan `migration_error_log`.
   - Solusi JDBC **CTE Statement Wrapping (`WITH ins AS (INSERT INTO ...) SELECT ... FROM ins`)** pada `pl_init_run.hpl` untuk mencegah error *PSQLException*.

---

### 🚫 Fitur di luar Cakupan (Out of Scope / Belum Diakomodasi Saat Ini)

Jelaskan secara transparan kepada tim proyek mengenai batasan sistem pada rilis saat ini:

1. **Streaming Real-time CDC (Change Data Capture) / Bi-Directional Sync**:
   - Sistem dirancang khusus untuk **Batch Migration System (On-Demand / Scheduled Batch)**.
   - *Belum mendukung* sinkronisasi streaming 2-arah real-time berbasis *PostgreSQL Logical Replication* atau *Debezium CDC*.
2. **Automated Schema Evolution / Auto DDL Migration**:
   - DDL tabel staging dan tabel target produksi harus sudah disiapkan terlebih dahulu oleh DB Admin (`sql/01_ddl_and_functions.sql`).
   - Jika ada penambahan kolom baru di aplikasi target, DDL PostgreSQL harus dibuat manual lebih dulu sebelum didaftarkan ke `migration_convert_rule` / `mapping_sql`.
3. **Data Masking & PII Anonymization Automated Framework**:
   - *Belum menyediakan* fitur penyamaran/anonymization otomatis data sensitif PII (seperti NIK, No Rekening, Email) secara deklaratif di layer staging. Data yang ditarik diasumsikan sudah sesuai aturan privasi dari source view.
4. **Custom GUI / Web Dashboard Management Console**:
   - Pemantauan dan eksekusi dilakukan via Apache Hop GUI / CLI (`kitchen`/`pan`) serta query SQL langsung ke tabel audit `migration_run`. *Belum tersedia* web UI dashboard khusus untuk pengelolaan visual metadata.

---

## 🗂️ BAGIAN 4: Penjelasan Master Konfigurasi Metadata (22 - 30 Min)

![Slide 4 Visual: Master Konfigurasi Metadata](/Users/macbookair/.gemini/antigravity-ide/brain/a1bf5770-a09b-43a7-8a72-699d715af417/slide4_metadata_config_1791400734163.jpg)

> **🎨 Prompt Visual Slide Bagian 4 (Light Mode Premium)**:
> ```text
> Create a highly professional, widescreen 16:9 data model slide for Metadata Configuration Framework in a LIGHT MODE PREMIUM theme. Title: "METADATA CONFIGURATION FRAMEWORK", Subtitle: "Zero Code Changes via 4 SQL Configuration Tables". Visual Style: Ultra-clean light modern tech aesthetic, crisp slate white background (#F8FAFC). Architectural Flow: 4 connected soft white database schema cards showing 1. etl_antam.migration_config (src_view v_migration_vendor, stg_table stg_vendors_src, id_seed 1031, id_width 8, src_precheck_sql), 2. etl_antam.migration_lookup (Master Code Dictionary lkp_vendor_type, lkp_company_type), 3. etl_antam.migration_convert_rule & vw_convert_rule (Staging Column Rules, Composite Key master_tgt_col, on_unmapped FAIL), 4. etl_antam.migration_target_config (Multi-Target exec_order 1: slave_vendors, exec_order 2: vendors, Idempotent mapping_sql). Color Palette: Deep royal blue (#1E3A8A / #2563EB) table headers, vibrant teal (#0D9488) relational arrows, emerald green (#059669) SQL badges, dark navy (#0F172A) text. Typography: Crisp technical sans-serif typography, clean database schema presentation layout. Ultra-high quality 8k resolution vector presentation slide design.
> ```

### 📌 Konsep Master Konfigurasi Metadata Saat Ini (To The Point)

Secara arsitektural, sistem migrasi data yang kita bangun mengusung pendekatan **Metadata-Driven ETL Framework**.  
Artinya: **Seluruh perilaku migrasi (apa yang ditarik, bagaimana kode dikonversi, ke tabel mana diposting, dan bagaimana penanganan error-nya) diatur 100% oleh Tabel Konfigurasi SQL (`etl_antam`), BUKAN dengan me-hardcode query di dalam Apache Hop.**

**3 Keuntungan Utama Arsitektur Metadata-Driven Bagi Tim Proyek**:
1. **Zero Hop Code Changes (Tanpa Ubah Pipeline Hop)**: Jika di kemudian hari ada tabel/domain data baru (misal: Material, Customer, PO), developer **cukup menambahkan baris `INSERT` konfigurasi baru di database**, tanpa perlu membuka Apache Hop GUI atau mengubah 1 baris pun kode pipeline Hop.
2. **Kamus Konversi Terpusat (Centralized Rules)**: Aturan pemetaan kode legacy ke ID target (misal Tipe Vendor `V01` ➔ `1`, Tipe Perusahaan `PT` ➔ `2`) dikelola terpusat di database, mendukung pencocokan gabungan kolom (*composite keys*), serta aturan tindakan jika kode tidak dikenal (`on_unmapped`).
3. **Multi-Target Posting Deklaratif**: Satu tabel staging dapat menyalurkan postingan ke 1, 2, atau banyak tabel target produksi secara otomatis dan berurutan (*exec order*) melalui template SQL yang aman.

---

### Rantai Hubungan 4 Tabel Master Konfigurasi Metadata:

```
[1. etl_antam.migration_config]
 ├── Mengatur Source View SQL Server & Target Staging PostgreSQL
 ├── Mengatur Generator LPAD ID Width & Seed (misal width=8, seed=1031 -> 00001032)
 └── Menjalankan Query Pre-Check SQL
        │
        ▼ (Relasi via config_id)
[2. etl_antam.migration_lookup & migration_convert_rule]
 ├── Menghubungkan kolom staging (column_name) ke Kamus Master Lookup
 ├── Mendukung Aturan Composite Key & Penanganan Kode Tidak Dikenal (on_unmapped = FAIL/WARN/DEFAULT)
 └── Diabstraksikan oleh Dynamic View: etl_antam.vw_convert_rule
        │
        ▼ (Relasi via config_id)
[3. etl_antam.migration_target_config]
 ├── Mengatur Multi-Target Posting (exec_order: 1 -> vendor.slave_vendors, 2 -> vendor.vendors)
 └── Menyimpan SQL Template Posting Idempotent (INSERT ... SELECT ... WHERE NOT EXISTS ...)
```

---

### Poin-Poin Penyampaian Detail per Tabel Konfigurasi (Point per Point):

1. **`etl_antam.migration_config` (Konfigurasi Utama Sumber & Staging)**:
   - **Fungsi**: Mendaftarkan pasangan tabel sumber legacy dan tabel staging target.
   - `config_id`: Identifier unik tabel migrasi (contoh: `1` untuk Vendor).
   - `src_view`: View sumber T-SQL di SQL Server (`v_migration_vendor`).
   - `stg_table`: Tabel penampungan sementara di PostgreSQL (`stg_vendors_src`).
   - `id_seed` (`1031`) & `id_width` (`8`): Parameter generator otomatis ID vendor berformat LPAD 8-digit (contoh: `00001032`).
   - `src_precheck_sql`: Query T-SQL pra-pemeriksaan di SQL Server sebelum ekstraksi dimulai.

2. **`etl_antam.migration_lookup` (Kamus Master Referensi Target)**:
   - **Fungsi**: Menyimpan daftar pasangan kode legacy (`src_code`) ke ID master target (`tgt_id`) yang dikelompokkan per `lookup_group`.
   - **Contoh Data**: 
     - Group `lkp_vendor_type`: `V01` ➔ `1` (Vendor Lokal), `V02` ➔ `2` (Vendor Impor).
     - Group `lkp_company_type`: `PT` ➔ `1` (Perseroan Terbatas), `CV` ➔ `2`.

3. **`etl_antam.migration_convert_rule` & `vw_convert_rule` (Aturan Transformasi Staging)**:
   - **Fungsi**: Menghubungkan setiap kolom staging (`column_name`) dengan kamus `lookup_group`.
   - `master_tgt_col`: Kolom acuan master. Bisa berupa 1 kolom atau gabungan beberapa kolom (*composite columns*) yang di-concatenation untuk mencari nilai lookup.
   - `on_unmapped`: Tindakan jika kode legacy tidak terdaftar di master:
     - `'FAIL'`: Migrasi dihentikan dan kode invalid dicatat ke `migration_error_log` (`UNMAPPED_CODE`).
     - `'WARN'`: Tetap diproses dengan log peringatan.
     - `'DEFAULT'`: Menggunakan nilai fallback default.
   - `vw_convert_rule`: View efisien yang menggabungkan tabel aturan dan kamus lookup untuk dieksekusi oleh `fn_convert_staging`.

4. **`etl_antam.migration_target_config` (Konfigurasi Multi-Target Posting)**:
   - **Fungsi**: Menentukan bagaimana data staging yang sudah terkonversi disalurkan ke tabel-tabel target utama aplikasi.
   - `exec_order`: Urutan eksekusi posting (Order 1: `vendor.slave_vendors` untuk tabel relasi detail, Order 2: `vendor.vendors` untuk tabel header utama).
   - `mapping_sql`: Template SQL DML yang dieksekusi PostgreSQL Engine menggunakan klausa `WHERE NOT EXISTS` untuk menjamin sifat posting yang *Idempotent* (aman di-rerun tanpa duplikasi).

---

## 🚀 BAGIAN 5: Cara Menjalankan 4 Flow Utama (30 - 38 Min)

![Slide 5 Visual: 4 Core Execution Workflows di Apache Hop](/Users/macbookair/.gemini/antigravity-ide/brain/a1bf5770-a09b-43a7-8a72-699d715af417/slide5_flow_utama_1791400765031.jpg)

> **🎨 Prompt Visual Slide Bagian 5 (Light Mode Premium)**:
> ```text
> Create a highly professional, widescreen 16:9 workflow guide slide for 4 Core Migration Workflows in a LIGHT MODE PREMIUM theme. Title: "4 CORE WORKFLOW EXECUTION GUIDE", Subtitle: "Step-by-Step Execution & Process Flow Diagrams". Visual Style: Ultra-clean light modern tech aesthetic, crisp light slate white background (#F8FAFC). 4 Horizontal Workflow Process Cards: 1. Flow 1: wf_main.hwf (CONFIG_ID, pl_init_run, Bulk Stream, fn_convert_staging LPAD & Delta Check), 2. Flow 2: wf_post.hwf (RUN_ID=146, USE_BATCH=Y/N, BATCH_SIZE=1000, fn_post_target_dispatch, ALREADY_POSTED Guard), 3. Flow 3: wf_rollback.hwf (RUN_ID=146, Single-Record Lifecycle, ALREADY_ROLLED_BACK Guard), 4. Flow 4: wf_purge_target.hwf (CONFIG_ID, DELETE_IDS, Dual-Guard Protection migration=1 & staging check, NOT_MIGRATION_DATA error). Each card features a mini process flow diagram. Color Palette: Deep royal blue (#1E3A8A / #2563EB) workflow titles, vibrant teal (#0D9488) action buttons, emerald green (#059669) status badges, dark navy (#0F172A) text. Typography: Sharp modern sans-serif typography, executive workflow demo guide layout. Ultra-high quality 8k resolution vector presentation slide design.
> ```

### 📌 Ringkasan Cara Menjalankan 4 Flow Utama & Diagram Alur Proses (To The Point)

Sistem migrasi kita menyediakan **4 Workflow Utama di Apache Hop** yang dapat dijalankan secara mandiri atau berurutan. Masing-masing workflow memiliki fungsi spesifik, parameter wajib, dan diagram alur eksekusi internal (*process flow*):

```
┌───────────────────────────┐      ┌───────────────────────────┐
│  Flow 1: Landing Staging  │ ───► │   Flow 2: Posting Target  │
│     (wf_main.hwf)         │      │     (wf_post.hwf)         │
└───────────────────────────┘      └───────────────────────────┘
              │                                  │
              ▼                                  ▼
┌───────────────────────────┐      ┌───────────────────────────┐
│   Flow 3: Rollback Run    │      │   Flow 4: Purge Target    │
│     (wf_rollback.hwf)     │      │   (wf_purge_target.hwf)   │
└───────────────────────────┘      └───────────────────────────┘
```

---

### Poin-Poin Detail & Diagram Alur per Flow:

#### 1. Flow 1: Ekstraksi, Landing Staging & Konversi Kode (`workflows/wf_main.hwf`)
- **Tujuan Utama**: Menarik data mentah dari SQL Server View (`v_migration_vendor`), mendaratkan ke PostgreSQL Staging (`stg_vendors_src`), melakukan format **LPAD 8-Digit ID** & **lookup code conversion**, serta menghitung delta data baru vs eksisting.
- **Diagram Alur Proses (Process Flow)**:
```
[Start wf_main.hwf]
       │
       ▼
[Execute pl_init_run.hpl] ──► (Create run_id & Truncate Staging)
       │
       ▼
[Check Source SQL Server] ──► (Run src_precheck_sql)
       │
       ▼
[Bulk Extract & Stream]  ──► (SQL Server View ➔ PostgreSQL Staging stg_vendors_src)
       │
       ▼
[Execute fn_convert_staging] ──► (LPAD ID Format + Lookup Code Conversion + Delta Check)
       │
       ▼
[Finish & Log SUCCESS]   ──► (Record Audit Trail in migration_run, is_posted = false)
```
- **Cara Menjalankan**:
  1. Buka Apache Hop GUI ➔ Open `workflows/wf_main.hwf`.
  2. Klik ikon **Run ▶** (atau via CLI: `kitchen.sh /file:workflows/wf_main.hwf`).
  3. **Parameter**: `CONFIG_ID` (opsional: `0` = semua tabel aktif, atau `1` = hanya tabel Vendor).
  4. **Hasil Eksekusi**: Data staging `stg_vendors_src` siap diposting, status `SUCCESS` dicatat di `migration_run`. Catat nomor `run_id` (misal `#146`).

---

#### 2. Flow 2: Multi-Target Posting Engine (`workflows/wf_post.hwf`)
- **Tujuan Utama**: Memindahkan data staging yang terkonversi dan bersih ke satu atau beberapa tabel target utama (`vendor.slave_vendors` dan `vendor.vendors`) berdasarkan parameter `RUN_ID`.
- **Diagram Alur Proses (Process Flow)**:
```
[Start wf_post.hwf]
       │
       ▼
[Validate RUN_ID & Guard] ───► (Is RUN_ID Valid?)
       │                                ├─ If ALREADY_ROLLED_BACK ➔ Throw Error
       │                                └─ If ALREADY_POSTED      ➔ Throw Error
       ▼
[Validate Batch Parameters] ──► (Is USE_BATCH & BATCH_SIZE Valid?)
       │                                └─ If Invalid ➔ Throw INVALID_BATCH_SIZE
       ├─ Mode Batch (USE_BATCH='Y')
       │  └─ Loop Chunking per BATCH_SIZE (e.g. 1000 rows)
       │
       └─ Mode Direct (USE_BATCH='N')
          └─ Direct Single Transaction Insert
       │
       ▼
[Execute fn_post_target_dispatch] ──► (INSERT Target Order 1: slave_vendors)
       │                              (INSERT Target Order 2: vendors)
       ▼
[pr_finish_run(RUN_ID)]       ──► (Set is_posted = true, post_type = 'BATCH (1000)' / 'DIRECT', status = SUCCESS)
```
- **Cara Menjalankan**:
  1. Buka Apache Hop GUI ➔ Open `workflows/wf_post.hwf`.
  2. Masukkan Parameter Wajib:
     - `RUN_ID`: Masukkan `run_id` dari hasil Flow 1 (contoh: `'146'`).
     - `USE_BATCH`: `'Y'` (Mode Batch bertahap) atau `'N'` (Mode Direct 1 transaksi).
     - `BATCH_SIZE`: `'1000'` (Jumlah baris per batch chunk saat `USE_BATCH = 'Y'`).
  3. Klik **Run ▶**.
  4. **Aturan Validasi Guard**:
     - Jika `RUN_ID` sudah pernah diposting ➔ Ditolak dengan error `ALREADY_POSTED`.
     - Jika `RUN_ID` sudah pernah di-rollback ➔ Ditolak dengan error `ALREADY_ROLLED_BACK`.
     - Jika `USE_BATCH = 'Y'` dan `BATCH_SIZE` kosong/0 ➔ Error `INVALID_BATCH_SIZE`.
  5. **Hasil Eksekusi**: Kolom `is_posted` bernilai `true`, `post_type` terisi, dan status tetap `SUCCESS`.

---

#### 3. Flow 3: Single-Record Safe Rollback Engine (`workflows/wf_rollback.hwf`)
- **Tujuan Utama**: Membatalkan dan menghapus data target yang pernah diposting oleh sesi `RUN_ID` tertentu secara transaksional pada **baris data yang sama** (tanpa membuat baris run baru).
- **Diagram Alur Proses (Process Flow)**:
```
[Start wf_rollback.hwf]
       │
       ▼
[Validate RUN_ID & Guard] ───► (Is RUN_ID exists in migration_run?)
       │                                ├─ If is_posted = false     ➔ Error NOT_POSTED_YET
       │                                └─ If is_rolled_back = true ➔ Error ALREADY_ROLLED_BACK
       ▼
[Execute fn_rollback_run] ───► (DELETE FROM Target Tables WHERE run_id = RUN_ID)
       │
       ▼
[pr_finish_rollback_run]  ───► (Update Record RUN_ID yang Sama: is_rolled_back = true, rolled_back_at = now(), status = SUCCESS)
```
- **Cara Menjalankan**:
  1. Buka Apache Hop GUI ➔ Open `workflows/wf_rollback.hwf`.
  2. Masukkan Parameter Wajib: `RUN_ID` (contoh: `'146'`).
  3. Klik **Run ▶**.
  4. **Keamanan Audit & Single-Record**:
     - Jika sesi belum pernah diposting ➔ Ditolak dengan error `NOT_POSTED_YET`.
     - Jika sesi sudah pernah di-rollback ➔ Ditolak dengan error `ALREADY_ROLLED_BACK`.
     - Baris `RUN_ID` yang sama di `migration_run` diperbarui (`is_rolled_back = true`, `status = SUCCESS`). **Tidak ada record run baru yang dibuat**.

---

#### 4. Flow 4: Presisi Target Data Purge dengan Dual-Guard Protection (`workflows/wf_purge_target.hwf`)
- **Tujuan Utama**: Menghapus data migrasi pada tabel target secara aman tanpa risiko menyentuh data produksi non-migrasi.
- **Diagram Alur Proses (Process Flow)**:
```
[Start wf_purge_target.hwf]
       │
       ▼
[Input CONFIG_ID & DELETE_IDS] ──► (Target IDs e.g. '1031,1032' or NULL for All)
       │
       ▼
[Dual-Guard Protection Check] ──► (Check: Target.migration = '1' AND Exists in Staging?)
       │                                 │ (If Non-Migration Data ➔ Error NOT_MIGRATION_DATA)
       ▼
[Execute fn_purge_target_data] ──► (DELETE FROM Target Tables WHERE ID IN (DELETE_IDS))
       │
       ▼
[Log Purge Audit Trail]       ──► (Record deleted count in migration_step_log)
```
- **Cara Menjalankan**:
  1. Buka Apache Hop GUI ➔ Open `workflows/wf_purge_target.hwf`.
  2. Masukkan Parameter:
     - `CONFIG_ID`: `'1'` (Tabel Vendor).
     - `DELETE_IDS`: `'1031'` (atau kosongkan untuk menghapus seluruh data migrasi tabel vendor).
  3. Klik **Run ▶**.
  4. **Proteksi Data Produksi**: Jika ID vendor yang dimasukkan adalah data buatan user produksi (`migration <> '1'` atau tidak ada di staging), sistem menolak penghapusan dengan error `NOT_MIGRATION_DATA`. **Data produksi non-migrasi dijamin 100% aman**.

---

## ❓ BAGIAN 6: Antisipasi Pertanyaan (Q&A) & Jawaban Tangguh (38 - 45 Min)

![Slide 6 Visual: Tanya Jawab (Q&A) & Penutup](/Users/macbookair/.gemini/antigravity-ide/brain/a1bf5770-a09b-43a7-8a72-699d715af417/slide6_qa_penutup_1791400796294.jpg)

> **🎨 Prompt Visual Slide Bagian 6 (Light Mode Premium)**:
> ```text
> Create a highly professional, widescreen 16:9 Q&A summary slide for an Enterprise Data Migration Project in a LIGHT MODE PREMIUM theme. Title: "TECHNICAL Q&A & EXECUTIVE SUMMARY", Subtitle: "Anticipated Questions & Key Technical Answers for Stakeholders". Visual Style: Ultra-clean light modern tech aesthetic, crisp light slate white background (#F8FAFC). Layout: 5 soft white elevated Q&A cards covering key stakeholder concerns: 1. PM/BA (Power Failure Safety via Idempotent WHERE NOT EXISTS), 2. DBA/Architect (Zero DB Lock via Batch Chunking per 1000 rows), 3. Data Engineer (Zero Hop Code Changes for New Tables via Metadata SQL), 4. QA (Unmapped Code Auto-Catching via on_unmapped=FAIL & migration_error_log), 5. Security Officer (Dual-Guard Production Data Safety checking migration=1 & staging record). Color Palette: Deep royal blue (#1E3A8A / #2563EB) role badges, vibrant teal (#0D9488) question markers, emerald green (#059669) answer highlights, dark navy (#0F172A) text. Typography: Sharp, legible modern sans-serif typography, executive summary layout. Ultra-high quality 8k resolution vector presentation slide design.
> ```

Berikut adalah daftar pertanyaan yang kemungkinan besar akan ditanyakan oleh tim proyek beserta jawaban yang perlu Anda berikan:

#### **Q1 (Dari Project Manager / Business Analyst):**
> *"Bagaimana jika di tengah jalan proses migrasi mati listrik atau server Hop crash?"*
- **Jawaban**:  
  "Sistem kita **Idempotent**. Karena query posting menggunakan `WHERE NOT EXISTS`, saat Hop dinyalakan kembali, data yang sudah masuk ke target tidak akan diduplikasi, dan proses akan melanjutkan data yang belum terposting."

#### **Q2 (Dari Database Administrator / Lead Architect):**
> *"Apakah posting puluhan ribu data ke tabel target vendor.vendors tidak mengunci (lock) tabel produksi?"*
- **Jawaban**:  
  "Tidak, karena pada `wf_post.hwf` kita mengimplementasikan **Mode Batch Chunking (`USE_BATCH = 'Y'`, `BATCH_SIZE = 1000`)**. Data diposting bertahap per 1.000 baris, sehingga kunci tabel di PostgreSQL hanya berlangsung hitungan milidetik per batch dan WAL log tetap terkontrol."

#### **Q3 (Dari Data Engineer / Developer):**
> *"Jika nanti ada tabel baru (misalnya tabel Material/Customer), apakah kita harus buat pipeline Hop baru dari awal?"*
- **Jawaban**:  
  "Sama sekali tidak. Sistem ini bersifat **Metadata-Driven**. Developer cukup memasukkan 3 baris query `INSERT` pada tabel `migration_config` dan `migration_target_config`. Workflow Hop yang ada secara otomatis akan mendeteksi dan memproses tabel baru tersebut."

#### **Q4 (Dari QA / Quality Assurance):**
> *"Bagaimana cara kita mengetahui jika ada kode legacy di SQL Server yang tidak dikenal di master PostgreSQL?"*
- **Jawaban**:  
  "Pada Flow 1 (`fn_convert_staging`), jika ada kode yang tidak cocok di master dan `on_unmapped = 'FAIL'`, migrasi langsung berhenti. Seluruh kode yang bermasalah beserta jumlah barisnya langsung dicatat secara transparan di tabel `etl_antam.migration_error_log` dengan kode `UNMAPPED_CODE`."

#### **Q5 (Dari Security / Compliance Officer):**
> *"Apakah fitur purge (`wf_purge_target.hwf`) tidak berisiko menghapus data vendor yang dibuat langsung oleh user di aplikasi produksi?"*
- **Jawaban**:  
  "Sangat aman. Fungsi `fn_purge_target_data` memiliki **Dual-Guard Protection**. Fungsi secara ketat memeriksa bahwa data target memiliki flag `migration = '1'` DAN secara fisik tercatat di staging `stg_vendors_src`. Jika ID produksi dimasukkan, sistem menolak penghapusan dengan error `NOT_MIGRATION_DATA`."

#### **Q6 (Dari Data Governance / DB Administrator):**
> *"Bagaimana pelacakan status satu siklus migrasi jika terjadi rollback, apakah membuat ID run baru?"*
- **Jawaban**:  
  "Kita menerapkan arsitektur **Single-Record Lifecycle**. Satu siklus penuh (Staging ➔ Posting ➔ Rollback) tercatat dalam **1 baris data tunggal** di `migration_run`. Ketika rollback dijalankan, sistem tidak membuat record run baru, melainkan memperbarui baris `RUN_ID` yang sama: menandai `is_rolled_back = true`, mengisi `rolled_back_at`, dan status tetap `SUCCESS`. Status di tabel ini distandarisasi hanya ada 3 nilai (`RUNNING`, `SUCCESS`, `FAILED`), sementara jenis posting disimpan di kolom `post_type` (`BATCH (1000)` atau `DIRECT`). Seluruh guard proteksi (`ALREADY_POSTED`, `NOT_POSTED_YET`, `ALREADY_ROLLED_BACK`) aktif secara otomatis."

---

