import { sql } from 'kysely';
import type { CoordinatorType, Db, Role } from '../../db.js';

export interface School {
  id: number;
  publicId: string;
  code: string;
  name: string;
  timezone: string;
}

export interface LoginCandidate {
  userId: number;
  passwordHash: string | null;
  active: boolean;
  lockedUntil: Date | null;
}

export interface SessionRecord {
  id: number;
  userId: number;
  tokenHash: Buffer;
  createdAt: Date;
  lastUsedAt: Date | null;
  expiresAt: Date;
  mustChangePassword: boolean;
}

export interface MeRecord {
  id: string;
  username: string;
  displayName: string;
  firstName: string;
  lastName: string;
  email: string | null;
  mustChangePassword: boolean;
  roles: { role: Role; coordinatorType: CoordinatorType | null }[];
}

/** Acceso a datos de autenticación; la implementación real es Kysely, las pruebas usan otra. */
export interface AuthStore {
  schoolByHost(host: string): Promise<School | null>;
  /** Estudiante por código en el colegio, o personal por usuario con un rol activo ahí (o platform_admin). */
  findLoginCandidate(schoolId: number | null, username: string): Promise<LoginCandidate | null>;
  recordLoginFailure(userId: number): Promise<void>;
  recordLoginSuccess(userId: number, now: Date): Promise<void>;
  createSession(s: { userId: number; tokenHash: Buffer; expiresAt: Date; userAgent: string | null; now: Date }): Promise<void>;
  /** Sesión no revocada con ese hash (vencida o no: lo decide quien llama). */
  findSession(tokenHash: Buffer): Promise<SessionRecord | null>;
  touchSession(id: number, now: Date): Promise<void>;
  revokeSession(id: number, now: Date): Promise<void>;
  /** null si la cuenta no está activa o no tiene roles en ese colegio. */
  getMe(userId: number, schoolId: number | null): Promise<MeRecord | null>;
}

const activeUser = { status: 'active', deleted_at: null } as const;

export function createKyselyAuthStore(db: Db): AuthStore {
  const rolesQuery = (userId: number, schoolId: number | null) =>
    db
      .selectFrom('user_roles')
      .select(['role', 'coordinator_type'])
      .where('user_id', '=', userId)
      .where('revoked_at', 'is', null)
      .where((eb) =>
        eb.or([
          eb('role', '=', 'platform_admin'),
          ...(schoolId === null ? [] : [eb('school_id', '=', schoolId)]),
        ]),
      )
      .orderBy('id');

  return {
    async schoolByHost(host) {
      const row = await db
        .selectFrom('school_domains as d')
        .innerJoin('schools as s', 's.id', 'd.school_id')
        .select(['s.id', 's.public_id', 's.code', 's.name', 's.timezone'])
        .where('d.host', '=', host)
        .where('d.status', '=', 'active')
        .where('s.status', '=', 'active')
        .executeTakeFirst();
      return row ? { id: row.id, publicId: row.public_id, code: row.code, name: row.name, timezone: row.timezone } : null;
    },

    async findLoginCandidate(schoolId, username) {
      const base = db
        .selectFrom('users as u')
        .select(['u.id', 'u.password_hash', 'u.status', 'u.deleted_at', 'u.locked_until']);

      let row =
        schoolId === null
          ? undefined
          : await base
              .innerJoin('students as st', 'st.user_id', 'u.id')
              .where('st.school_id', '=', schoolId)
              .where('st.student_code', '=', username)
              .where('st.status', '=', 'active')
              .where('st.deleted_at', 'is', null)
              .executeTakeFirst();

      row ??= await base
        .where('u.username', '=', username)
        .where((eb) =>
          eb.exists(
            eb
              .selectFrom('user_roles as r')
              .select(sql`1`.as('one'))
              .whereRef('r.user_id', '=', 'u.id')
              .where('r.revoked_at', 'is', null)
              .where('r.role', '<>', 'student')
              .where((e) =>
                e.or([
                  e('r.role', '=', 'platform_admin'),
                  ...(schoolId === null ? [] : [e('r.school_id', '=', schoolId)]),
                ]),
              ),
          ),
        )
        .executeTakeFirst();

      if (!row) return null;
      return {
        userId: row.id,
        passwordHash: row.password_hash,
        active: row.status === 'active' && row.deleted_at === null,
        lockedUntil: row.locked_until,
      };
    },

    async recordLoginFailure(userId) {
      await db
        .updateTable('users')
        .set((eb) => ({ failed_login_count: eb('failed_login_count', '+', 1) }))
        .where('id', '=', userId)
        .execute();
    },

    async recordLoginSuccess(userId, now) {
      await db
        .updateTable('users')
        .set({ failed_login_count: 0, locked_until: null, last_login_at: now })
        .where('id', '=', userId)
        .execute();
    },

    async createSession({ userId, tokenHash, expiresAt, userAgent, now }) {
      await db
        .insertInto('auth_sessions')
        .values({ user_id: userId, token_hash: tokenHash, expires_at: expiresAt, last_used_at: now, user_agent: userAgent?.slice(0, 255) ?? null })
        .execute();
    },

    async findSession(tokenHash) {
      const row = await db
        .selectFrom('auth_sessions as s')
        .innerJoin('users as u', 'u.id', 's.user_id')
        .select(['s.id', 's.user_id', 's.token_hash', 's.created_at', 's.last_used_at', 's.expires_at', 'u.must_change_password'])
        .where('s.token_hash', '=', tokenHash)
        .where('s.revoked_at', 'is', null)
        .where('u.status', '=', activeUser.status)
        .where('u.deleted_at', 'is', null)
        .executeTakeFirst();
      return row
        ? {
            id: row.id,
            userId: row.user_id,
            tokenHash: row.token_hash,
            createdAt: row.created_at,
            lastUsedAt: row.last_used_at,
            expiresAt: row.expires_at,
            mustChangePassword: row.must_change_password === 1,
          }
        : null;
    },

    async touchSession(id, now) {
      await db.updateTable('auth_sessions').set({ last_used_at: now }).where('id', '=', id).execute();
    },

    async revokeSession(id, now) {
      await db
        .updateTable('auth_sessions')
        .set({ revoked_at: now })
        .where('id', '=', id)
        .where('revoked_at', 'is', null)
        .execute();
    },

    async getMe(userId, schoolId) {
      const user = await db
        .selectFrom('users')
        .select(['public_id', 'username', 'display_name', 'first_name', 'last_name', 'email', 'must_change_password'])
        .where('id', '=', userId)
        .where('status', '=', activeUser.status)
        .where('deleted_at', 'is', null)
        .executeTakeFirst();
      if (!user) return null;
      const roles = await rolesQuery(userId, schoolId).execute();
      if (roles.length === 0) return null;
      return {
        id: user.public_id,
        username: user.username,
        displayName: user.display_name,
        firstName: user.first_name,
        lastName: user.last_name,
        email: user.email,
        mustChangePassword: user.must_change_password === 1,
        roles: roles.map((r) => ({ role: r.role, coordinatorType: r.coordinator_type })),
      };
    },
  };
}
