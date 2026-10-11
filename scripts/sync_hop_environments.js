#!/usr/bin/env node

/**
 * Script Sinkronisasi Konfigurasi Environment ke Apache Hop Docker
 * Membaca seluruh file `config/*-config.json` di host dan:
 * 1. Mendaftarkan Lifecycle Environment ke metadata `hop-config.json` di Docker container `apache-hop`.
 * 2. Menyalin file config ke project directory di dalam container.
 * 3. Menyetel hak akses file ke user `hop:hop`.
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PROJECT_DIR = path.resolve(__dirname, '..');
const CONFIG_DIR = path.join(PROJECT_DIR, 'config');
const CONTAINER_NAME = 'apache-hop';

function main() {
  console.log('🔄 Memulai Sinkronisasi Environment ke Apache Hop Docker...');

  // 1. Cek apakah container running
  try {
    const running = execSync(`docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Names}}"`, { encoding: 'utf8' }).trim();
    if (!running) {
      console.error(`❌ Container '${CONTAINER_NAME}' tidak aktif.`);
      process.exit(1);
    }
  } catch (err) {
    console.error('❌ Gagal memeriksa container docker:', err.message);
    process.exit(1);
  }

  // 2. Ambil hop-config.json dari container
  const tmpConfigFile = '/tmp/hop-config-sync.json';
  execSync(`docker exec ${CONTAINER_NAME} cat /usr/local/tomcat/webapps/ROOT/config/hop-config.json > ${tmpConfigFile}`);
  const hopConfig = JSON.parse(fs.readFileSync(tmpConfigFile, 'utf8'));

  if (!hopConfig.projectsConfig || !hopConfig.projectsConfig.lifecycleEnvironments) {
    console.error('❌ Format hop-config.json tidak valid.');
    process.exit(1);
  }

  // 3. Pindai file konfigurasi
  const allConfigFiles = fs.readdirSync(CONFIG_DIR).filter(f => f.endsWith('.json') && f !== 'template-config.json');
  console.log(`📁 Ditemukan ${allConfigFiles.length} file konfigurasi di folder config/:`, allConfigFiles);

  let modified = false;

  for (const file of allConfigFiles) {
    if (file === 'dev-config.json') continue;

    // e.g. ANTAM_DEV-config.json -> ANTAM_DEV
    const envBaseName = file.replace('-config.json', '').toUpperCase();

    // Daftarkan ke project MIgrasi_ANTAM
    const existsProject1 = hopConfig.projectsConfig.lifecycleEnvironments.some(
      e => e.name === envBaseName && e.projectName === 'MIgrasi_ANTAM'
    );
    if (!existsProject1) {
      hopConfig.projectsConfig.lifecycleEnvironments.push({
        name: envBaseName,
        purpose: 'Development',
        projectName: 'MIgrasi_ANTAM',
        canvasText: '',
        configurationFiles: ['${PROJECT_HOME}/config/' + file],
        attributesMap: {
          marketplace: { strict: 'false', autoApply: 'false', onEnable: 'off' },
          resources: { onEnable: 'off' }
        }
      });
      console.log(`  ➕ Daftarkan Environment '${envBaseName}' untuk Project 'MIgrasi_ANTAM'`);
      modified = true;
    }

    // Daftarkan ke project ETL-ANTAM-V1
    const envNameV1 = `ETL-${envBaseName}`;
    const existsProject2 = hopConfig.projectsConfig.lifecycleEnvironments.some(
      e => e.name === envNameV1 && e.projectName === 'ETL-ANTAM-V1'
    );
    if (!existsProject2) {
      hopConfig.projectsConfig.lifecycleEnvironments.push({
        name: envNameV1,
        purpose: 'Development',
        projectName: 'ETL-ANTAM-V1',
        canvasText: '',
        configurationFiles: ['${PROJECT_HOME}/config/' + file],
        attributesMap: {
          marketplace: { strict: 'false', autoApply: 'false', onEnable: 'off' },
          resources: { onEnable: 'off' }
        }
      });
      console.log(`  ➕ Daftarkan Environment '${envNameV1}' untuk Project 'ETL-ANTAM-V1'`);
      modified = true;
    }
  }

  // 4. Update hop-config.json jika ada perubahan
  if (modified) {
    fs.writeFileSync(tmpConfigFile, JSON.stringify(hopConfig, null, 2), 'utf8');
    execSync(`docker cp ${tmpConfigFile} ${CONTAINER_NAME}:/usr/local/tomcat/webapps/ROOT/config/hop-config.json`);
    console.log('✅ Metadata hop-config.json berhasil diperbarui di Docker container.');
  } else {
    console.log('ℹ️ Seluruh environment sudah terdaftar di hop-config.json.');
  }

  // 5. Salin file config ke container projects
  for (const file of allConfigFiles) {
    execSync(`docker cp "${path.join(CONFIG_DIR, file)}" ${CONTAINER_NAME}:/usr/local/tomcat/webapps/ROOT/config/projects/hop-project/config/${file}`);
    execSync(`docker cp "${path.join(CONFIG_DIR, file)}" ${CONTAINER_NAME}:/usr/local/tomcat/webapps/ROOT/config/projects/antam/config/${file}`);
  }
  console.log('✅ File konfigurasi berhasil disalin ke direktori proyek di container.');

  // 6. Set hak akses hop:hop
  execSync(`docker exec -u 0 ${CONTAINER_NAME} chown -R hop:hop /usr/local/tomcat/webapps/ROOT/config`);
  console.log('✅ Hak akses user hop:hop berhasil disesuaikan.');
  console.log('🎉 Selesai! Environment siap dipilih di Apache Hop GUI.');
}

main();
