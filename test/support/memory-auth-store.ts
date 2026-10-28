import type { AuthStore, MeRecord, School, SessionRecord } from '../../src/modules/auth/store.js';

export interface MemoryUser {
  id: number;
  code?: string;
  username: string;
  passwordHash: string | null;
  active?: boolean;
  lockedUntil?: Date | null;
  mustChangePassword?: boolean;
  /** Colegio de sus roles (por defecto el primero); null = platform_admin, solo en el host de administración. */
  schoolId?: number | null;
  me: Omit<MeRecord, 'mustChangePassword'>;
}

/** AuthStore en memoria para probar rutas sin MySQL. */
export function memoryAuthStore(schools: (School & { host: string })[], users: MemoryUser[]) {
  const sessions: (SessionRecord & { revokedAt: Date | null })[] = [];
  const failures = new Map<number, number>();
  const byId = (id: number) => users.find((u) => u.id === id);
  const schoolOf = (u: MemoryUser) => (u.schoolId === undefined ? (schools[0]?.id ?? null) : u.schoolId);

  const store: AuthStore = {
    async schoolByHost(host) {
      return schools.find((x) => x.host === host) ?? null;
    },
    async findLoginCandidate(schoolId, username) {
      const u = users.find((x) => (x.code === username || x.username === username) && schoolOf(x) === schoolId);
      return u ? { userId: u.id, passwordHash: u.passwordHash, active: u.active ?? true, lockedUntil: u.lockedUntil ?? null } : null;
    },
    async recordLoginFailure(userId) {
      failures.set(userId, (failures.get(userId) ?? 0) + 1);
    },
    async recordLoginSuccess(userId) {
      failures.set(userId, 0);
    },
    async createSession({ userId, schoolId, tokenHash, expiresAt, now }) {
      sessions.push({
        id: sessions.length + 1,
        userId,
        schoolId,
        tokenHash,
        createdAt: now,
        lastUsedAt: now,
        expiresAt,
        mustChangePassword: byId(userId)?.mustChangePassword ?? false,
        revokedAt: null,
      });
    },
    async findSession(tokenHash) {
      const s = sessions.find((x) => x.tokenHash.equals(tokenHash) && x.revokedAt === null);
      return s ? { ...s, mustChangePassword: byId(s.userId)?.mustChangePassword ?? false } : null;
    },
    async touchSession(id, now) {
      const s = sessions.find((x) => x.id === id);
      if (s) s.lastUsedAt = now;
    },
    async revokeSession(id, now) {
      const s = sessions.find((x) => x.id === id);
      if (s && !s.revokedAt) s.revokedAt = now;
    },
    async getMe(userId, schoolId) {
      const u = byId(userId);
      return u && (u.active ?? true) && schoolOf(u) === schoolId ? { ...u.me, mustChangePassword: u.mustChangePassword ?? false } : null;
    },
  };
  return { store, sessions, failures };
}
