import type { AuthStore, MeRecord, School, SessionRecord } from '../../src/modules/auth/store.js';

export interface MemoryUser {
  id: number;
  code?: string;
  username: string;
  passwordHash: string | null;
  active?: boolean;
  lockedUntil?: Date | null;
  mustChangePassword?: boolean;
  me: Omit<MeRecord, 'mustChangePassword'>;
}

/** AuthStore en memoria para probar rutas sin MySQL. */
export function memoryAuthStore(school: School & { host: string }, users: MemoryUser[]) {
  const sessions: (SessionRecord & { revokedAt: Date | null })[] = [];
  const failures = new Map<number, number>();
  const byId = (id: number) => users.find((u) => u.id === id);

  const store: AuthStore = {
    async schoolByHost(host) {
      return host === school.host ? school : null;
    },
    async findLoginCandidate(schoolId, username) {
      if (schoolId !== school.id) return null;
      const u = users.find((x) => x.code === username || x.username === username);
      return u ? { userId: u.id, passwordHash: u.passwordHash, active: u.active ?? true, lockedUntil: u.lockedUntil ?? null } : null;
    },
    async recordLoginFailure(userId) {
      failures.set(userId, (failures.get(userId) ?? 0) + 1);
    },
    async recordLoginSuccess(userId) {
      failures.set(userId, 0);
    },
    async createSession({ userId, tokenHash, expiresAt, now }) {
      sessions.push({
        id: sessions.length + 1,
        userId,
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
    async getMe(userId) {
      const u = byId(userId);
      return u && (u.active ?? true) ? { ...u.me, mustChangePassword: u.mustChangePassword ?? false } : null;
    },
  };
  return { store, sessions, failures };
}
