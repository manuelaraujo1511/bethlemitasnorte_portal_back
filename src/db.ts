import { Kysely, MysqlDialect, sql, type Generated } from 'kysely';
import { createPool } from 'mysql2';
import type { Config } from './config.js';

// Solo las tablas y columnas que el código usa; se amplía por módulo.
export interface UsersTable {
  id: Generated<number>;
  public_id: Generated<string>;
  username: string;
  email: string | null;
  first_name: string;
  last_name: string;
  display_name: string;
  password_hash: string | null;
  must_change_password: number;
  failed_login_count: number;
  locked_until: Date | null;
  last_login_at: Date | null;
  status: 'invited' | 'active' | 'suspended' | 'archived';
  deleted_at: Date | null;
}

export interface SchoolsTable {
  id: Generated<number>;
  public_id: Generated<string>;
  code: string;
  name: string;
  timezone: string;
  status: 'active' | 'suspended' | 'archived';
}

export interface SchoolDomainsTable {
  id: Generated<number>;
  school_id: number;
  host: string;
  status: 'active' | 'disabled';
}

export type Role = 'platform_admin' | 'school_admin' | 'coordinator' | 'teacher' | 'student';
export type CoordinatorType = 'academica' | 'pastoral' | 'convivencia' | 'orientacion';

export interface UserRolesTable {
  id: Generated<number>;
  user_id: number;
  school_id: number | null;
  role: Role;
  coordinator_type: CoordinatorType | null;
  revoked_at: Date | null;
}

export interface StudentsTable {
  id: Generated<number>;
  school_id: number;
  user_id: number;
  student_code: string | null;
  status: 'active' | 'withdrawn' | 'graduated' | 'archived';
  deleted_at: Date | null;
}

export interface AuthSessionsTable {
  id: Generated<number>;
  user_id: number;
  school_id: number | null;
  token_hash: Buffer;
  created_at: Generated<Date>;
  last_used_at: Date | null;
  expires_at: Date;
  revoked_at: Date | null;
  user_agent: string | null;
}

export interface Database {
  users: UsersTable;
  schools: SchoolsTable;
  school_domains: SchoolDomainsTable;
  user_roles: UserRolesTable;
  students: StudentsTable;
  auth_sessions: AuthSessionsTable;
}

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
