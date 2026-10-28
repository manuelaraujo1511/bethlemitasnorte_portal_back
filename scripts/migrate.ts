// Aplica las migraciones SQL pendientes y, con --seed, los datos de desarrollo.
// Uso: npm run db:migrate | npm run db:seed
import { existsSync } from 'node:fs';
import path from 'node:path';
import { createConnection } from 'mysql2/promise';
import { loadConfig } from '../src/config.js';
import { appliedVersions, listMigrations, runSqlFile } from './sql-runner.js';

const config = loadConfig();
const seed = process.argv.includes('--seed');
const migrationsDir = path.resolve(process.env.MIGRATIONS_DIR ?? 'db/migrations');
// Seeds en orden; cada uno depende de los anteriores.
const seedFiles = (process.env.SEED_FILES ?? 'db/seed_dev.sql,db/seed_dev_academic.sql')
  .split(',')
  .map((f) => f.trim())
  .filter((f) => f.length > 0)
  .map((f) => path.resolve(f));

if (seed && config.NODE_ENV === 'production') {
  console.error('El seed de desarrollo no se aplica en producción.');
  process.exit(1);
}

const conn = await createConnection({
  host: config.DB_HOST,
  port: config.DB_PORT,
  user: config.DB_USER,
  password: config.DB_PASSWORD,
  database: config.DB_NAME,
  charset: 'utf8mb4_0900_ai_ci',
  timezone: 'Z',
  multipleStatements: true,
  ssl: config.DB_SSL ? { rejectUnauthorized: true } : undefined,
});

try {
  await conn.query("SET time_zone = '+00:00'");
  const migrations = await listMigrations(migrationsDir);
  if (migrations.length === 0) {
    console.log(`No hay migraciones en ${migrationsDir}`);
  }
  const applied = await appliedVersions(conn);
  for (const m of migrations) {
    if (applied.has(m.version)) {
      console.log(`= ${m.version} (ya aplicada)`);
      continue;
    }
    await runSqlFile(conn, m.file);
    await conn.query('INSERT IGNORE INTO schema_migrations (version) VALUES (?)', [m.version]);
    console.log(`+ ${m.version}`);
  }
  if (seed) {
    for (const file of seedFiles) {
      if (!existsSync(file)) {
        console.log(`- seed ${path.basename(file)} (no existe, se omite)`);
        continue;
      }
      await runSqlFile(conn, file);
      console.log(`+ seed ${path.basename(file)}`);
    }
  }
} catch (err) {
  console.error('Falló la migración:', err instanceof Error ? err.message : err);
  process.exitCode = 1;
} finally {
  await conn.end();
}
