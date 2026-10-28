import { Kysely, MysqlDialect, sql } from 'kysely';
import { createPool } from 'mysql2';
import type { Config } from './config.js';

// Las tablas se tipan a medida que los módulos las usen (B1.x).
// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export interface Database {}

export type Db = Kysely<Database>;

export function createDb(config: Config): Db {
  const pool = createPool({
    host: config.DB_HOST,
    port: config.DB_PORT,
    user: config.DB_USER,
    password: config.DB_PASSWORD,
    database: config.DB_NAME,
    connectionLimit: config.DB_POOL_SIZE,
    charset: 'utf8mb4_0900_ai_ci',
    // Fechas en UTC de punta a punta; se convierten a America/Bogota al mostrar.
    timezone: 'Z',
    ssl: config.DB_SSL ? { rejectUnauthorized: true } : undefined,
  });
  pool.on('connection', (conn) => {
    conn.query("SET time_zone = '+00:00'");
  });
  return new Kysely<Database>({ dialect: new MysqlDialect({ pool }) });
}

export async function pingDb(db: Db): Promise<void> {
  await sql`SELECT 1`.execute(db);
}
