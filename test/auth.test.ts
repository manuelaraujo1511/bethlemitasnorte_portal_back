import type { FastifyPluginAsync, LightMyRequestResponse } from 'fastify';
import { beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { hashPassword, sha256 } from '../src/modules/auth/crypto.js';
import { CSRF_COOKIE, SESSION_COOKIE } from '../src/modules/auth/plugin.js';
import type { ActorStore } from '../src/modules/authz/actor.js';
import { requireActor } from '../src/modules/authz/policy.js';
import { memoryAuthStore, type MemoryUser } from './support/memory-auth-store.js';

const HOST = 'demo.campus.localhost';
const PASSWORD = 'una frase larga de prueba';
const school = { id: 1, publicId: '00000000-0000-4000-8000-000000000001', code: 'demo', name: 'Colegio Demo', timezone: 'America/Bogota', host: HOST };
const OTHER_HOST = 'otro.campus.localhost';
const ADMIN_HOST = 'admin.campus.localhost';
const otherSchool = { id: 2, publicId: '00000000-0000-4000-8000-000000000002', code: 'otro', name: 'Otro Colegio', timezone: 'America/Bogota', host: OTHER_HOST };
const IDLE = 30 * 60_000;
const MAX = 12 * 3_600_000;

let hash: string;
beforeAll(async () => {
  hash = await hashPassword(PASSWORD);
});

function student(over: Partial<MemoryUser> = {}): MemoryUser {
  return {
    id: 15,
    code: '900001',
    username: 'ana.torres',
    passwordHash: hash,
    me: {
      id: '00000000-0000-4000-8000-000000000015',
      username: 'ana.torres',
      displayName: 'Ana Torres Ruiz',
      firstName: 'Ana',
      lastName: 'Torres Ruiz',
      email: null,
      roles: [{ role: 'student', coordinatorType: null }],
    },
    ...over,
  };
}

function setup(users: MemoryUser[] = [student()], apiModules: FastifyPluginAsync[] = []) {
  const clock = { t: new Date('2026-10-28T15:00:00.000Z') };
  const mem = memoryAuthStore([school, otherSchool], users);
  const app = buildApp({
    config: { LOG_LEVEL: 'silent' },
    checkDb: async () => {},
    auth: { store: mem.store, secret: 'x'.repeat(40), idleMs: IDLE, maxMs: MAX, adminHost: ADMIN_HOST, now: () => clock.t },
    apiModules,
  });
  return { app, clock, ...mem };
}

/** Navegador mínimo: guarda cookies y manda el token CSRF como lo haría el front. */
function browser(app: ReturnType<typeof setup>['app'], host = HOST) {
  const jar = new Map<string, string>();
  const keep = (res: LightMyRequestResponse) => {
    for (const c of res.cookies as { name: string; value: string; maxAge?: number; expires?: Date }[]) {
      if (c.value === '' || c.maxAge === 0 || (c.expires && c.expires.getTime() <= 0)) jar.delete(c.name);
      else jar.set(c.name, c.value);
    }
    return res;
  };
  const cookieHeader = () => [...jar].map(([k, v]) => `${k}=${v}`).join('; ');
  return {
    jar,
    async get(url: string) {
      return keep(await app.inject({ method: 'GET', url, headers: { host, cookie: cookieHeader() } }));
    },
    async post(url: string, payload?: object, csrf: string | null = jar.get(CSRF_COOKIE) ?? null) {
      const headers: Record<string, string> = { host, cookie: cookieHeader() };
      if (csrf !== null) headers['x-csrf-token'] = csrf;
      return keep(await app.inject({ method: 'POST', url, headers, ...(payload ? { payload } : {}) }));
    },
    async login(username = '900001', password = PASSWORD) {
      await this.get('/api/v1/auth/csrf');
      return this.post('/api/v1/auth/login', { username, password });
    },
  };
}

describe('GET /auth/csrf', () => {
  it('entrega el token y lo fija en una cookie __Host- legible por el front', async () => {
    const { app } = setup();
    const res = await app.inject({ method: 'GET', url: '/api/v1/auth/csrf', headers: { host: HOST } });
    expect(res.statusCode).toBe(200);
    const cookie = res.cookies.find((c) => c.name === CSRF_COOKIE)!;
    expect(res.json()).toEqual({ csrfToken: cookie.value });
    expect(cookie).toMatchObject({ path: '/', secure: true, sameSite: 'Lax' });
    expect(cookie.httpOnly).toBeFalsy();
  });
});

describe('POST /auth/login', () => {
  it('sin token CSRF responde 403 csrf_invalid', async () => {
    const b = browser(setup().app);
    await b.get('/api/v1/auth/csrf');
    const res = await b.post('/api/v1/auth/login', { username: '900001', password: PASSWORD }, null);
    expect(res.statusCode).toBe(403);
    expect(res.json().code).toBe('csrf_invalid');
  });

  it('con un token que no coincide con la cookie responde 403', async () => {
    const b = browser(setup().app);
    await b.get('/api/v1/auth/csrf');
    const res = await b.post('/api/v1/auth/login', { username: '900001', password: PASSWORD }, 'a'.repeat(43));
    expect(res.statusCode).toBe(403);
  });

  it('entra con el código del estudiante y fija una sesión HttpOnly', async () => {
    const { app, sessions } = setup();
    const b = browser(app);
    const res = await b.login();
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      ...student().me,
      mustChangePassword: false,
      school: { id: school.publicId, code: 'demo', name: 'Colegio Demo', timezone: 'America/Bogota' },
    });
    const sessionCookie = res.cookies.find((c) => c.name === SESSION_COOKIE)!;
    expect(sessionCookie).toMatchObject({ path: '/', secure: true, httpOnly: true, sameSite: 'Lax', maxAge: MAX / 1000 });
    // En la base solo queda el hash del token.
    expect(sessions).toHaveLength(1);
    expect(sessions[0]!.tokenHash.equals(sha256(sessionCookie.value))).toBe(true);
  });

  it('también entra el personal con su usuario', async () => {
    const b = browser(setup([student({ id: 3, code: undefined, username: 'elena.vargas' })]).app);
    expect((await b.login('elena.vargas')).statusCode).toBe(200);
  });

  it('contraseña errada y cuenta inexistente responden igual', async () => {
    const { app, failures } = setup();
    const b = browser(app);
    const wrong = await b.login('900001', 'otra frase cualquiera');
    const missing = await b.login('999999', PASSWORD);
    for (const res of [wrong, missing]) {
      expect(res.statusCode).toBe(401);
      expect(res.headers['set-cookie'] ?? '').not.toContain(SESSION_COOKIE);
    }
    const strip = (r: LightMyRequestResponse) => ({ ...r.json(), requestId: undefined });
    expect(strip(wrong)).toEqual(strip(missing));
    expect(strip(wrong).code).toBe('invalid_credentials');
    expect(failures.get(15)).toBe(1);
  });

  it('una cuenta suspendida, bloqueada o con hash de marcador no entra', async () => {
    for (const over of [
      { active: false },
      { lockedUntil: new Date('2026-10-28T16:00:00.000Z') },
      { passwordHash: '$argon2id$DEV-PLACEHOLDER-NOT-A-REAL-HASH' },
    ]) {
      const b = browser(setup([student(over)]).app);
      const res = await b.login();
      expect(res.statusCode, JSON.stringify(over)).toBe(401);
      expect(res.json().code).toBe('invalid_credentials');
    }
  });

  it('un host que no es de ningún colegio ni del panel no tiene API', async () => {
    const { app } = setup();
    for (const [method, url] of [['POST', '/api/v1/auth/login'], ['GET', '/api/v1/auth/csrf'], ['GET', '/api/v1/me']] as const) {
      const res = await app.inject({
        method,
        url,
        headers: { host: 'cualquier.cosa', cookie: `${CSRF_COOKIE}=${'b'.repeat(43)}`, 'x-csrf-token': 'b'.repeat(43) },
        ...(method === 'POST' ? { payload: { username: '900001', password: PASSWORD } } : {}),
      });
      expect(res.statusCode, url).toBe(404);
      expect(res.json().code).toBe('not_found');
    }
  });

  it('en el colegio de otro no entra', async () => {
    const res = await browser(setup().app, OTHER_HOST).login();
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('invalid_credentials');
  });

  it('rechaza campos de más', async () => {
    const b = browser(setup().app);
    await b.get('/api/v1/auth/csrf');
    const res = await b.post('/api/v1/auth/login', { username: '900001', password: PASSWORD, admin: true });
    expect(res.statusCode).toBe(400);
  });

  it('rota la sesión: la anterior deja de valer', async () => {
    const { app, sessions } = setup();
    const b = browser(app);
    await b.login();
    const first = b.jar.get(SESSION_COOKIE)!;
    await b.post('/api/v1/auth/login', { username: '900001', password: PASSWORD });
    expect(b.jar.get(SESSION_COOKIE)).not.toBe(first);
    expect(sessions[0]!.revokedAt).not.toBeNull();
    expect(sessions[1]!.revokedAt).toBeNull();
  });
});

describe('CSRF ligado a la sesión', () => {
  it('tras entrar, el token anónimo anterior ya no sirve', async () => {
    const b = browser(setup().app);
    await b.get('/api/v1/auth/csrf');
    const anonymous = b.jar.get(CSRF_COOKIE)!;
    await b.post('/api/v1/auth/login', { username: '900001', password: PASSWORD });
    expect(b.jar.get(CSRF_COOKIE)).not.toBe(anonymous);
    // Aunque la cookie y la cabecera coincidan, deben ser el HMAC de la sesión.
    b.jar.set(CSRF_COOKIE, anonymous);
    const res = await b.post('/api/v1/auth/logout');
    expect(res.statusCode).toBe(403);
  });

  it('GET /auth/csrf con sesión devuelve el token de esa sesión', async () => {
    const b = browser(setup().app);
    await b.login();
    const bound = b.jar.get(CSRF_COOKIE);
    const res = await b.get('/api/v1/auth/csrf');
    expect(res.json().csrfToken).toBe(bound);
  });
});

describe('GET /me', () => {
  it('sin sesión responde 401 unauthenticated', async () => {
    const res = await browser(setup().app).get('/api/v1/me');
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('unauthenticated');
  });

  it('con sesión devuelve la persona', async () => {
    const b = browser(setup().app);
    await b.login();
    const res = await b.get('/api/v1/me');
    expect(res.statusCode).toBe(200);
    expect(res.json().displayName).toBe('Ana Torres Ruiz');
  });
});

describe('vencimiento y cierre', () => {
  it('vence por inactividad', async () => {
    const { app, clock, sessions } = setup();
    const b = browser(app);
    await b.login();
    clock.t = new Date(clock.t.getTime() + IDLE - 1000);
    expect((await b.get('/api/v1/me')).statusCode).toBe(200);
    clock.t = new Date(clock.t.getTime() + IDLE - 1000);
    expect((await b.get('/api/v1/me')).statusCode).toBe(200); // el uso anterior la renovó
    clock.t = new Date(clock.t.getTime() + IDLE);
    const res = await b.get('/api/v1/me');
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('session_expired');
    expect(sessions[0]!.revokedAt).not.toBeNull();
    expect(b.jar.has(SESSION_COOKIE)).toBe(false);
  });

  it('vence al cumplir la vida máxima aunque se use', async () => {
    const { app, clock } = setup();
    const b = browser(app);
    await b.login();
    const start = clock.t.getTime();
    const step = IDLE / 2;
    while (clock.t.getTime() + step < start + MAX) {
      clock.t = new Date(clock.t.getTime() + step);
      expect((await b.get('/api/v1/me')).statusCode).toBe(200);
    }
    clock.t = new Date(start + MAX + 1);
    expect((await b.get('/api/v1/me')).json().code).toBe('session_expired');
  });

  it('logout revoca la sesión y borra las cookies', async () => {
    const { app, sessions } = setup();
    const b = browser(app);
    await b.login();
    const token = b.jar.get(SESSION_COOKIE)!;
    const res = await b.post('/api/v1/auth/logout');
    expect(res.statusCode).toBe(204);
    expect(sessions[0]!.revokedAt).not.toBeNull();
    expect(b.jar.has(SESSION_COOKIE)).toBe(false);
    // Reusar la cookie robada no sirve.
    b.jar.set(SESSION_COOKIE, token);
    expect((await b.get('/api/v1/me')).statusCode).toBe(401);
  });
});

describe('mustChangePassword', () => {
  const probe: FastifyPluginAsync = async (api) => {
    api.get('/notas', async () => ({ ok: true }));
  };

  it('solo deja /me, /auth/csrf, logout y cambio de contraseña', async () => {
    const b = browser(setup([student({ mustChangePassword: true })], [probe]).app);
    const login = await b.login();
    expect(login.statusCode).toBe(200);
    expect(login.json().mustChangePassword).toBe(true);
    expect((await b.get('/api/v1/me')).statusCode).toBe(200);
    const blocked = await b.get('/api/v1/notas');
    expect(blocked.statusCode).toBe(403);
    expect(blocked.json().code).toBe('password_change_required');
  });

  it('sin la marca, el módulo responde normal', async () => {
    const b = browser(setup([student()], [probe]).app);
    await b.login();
    expect((await b.get('/api/v1/notas')).json()).toEqual({ ok: true });
  });
});

describe('host del colegio y de la plataforma', () => {
  const admin = (): MemoryUser => ({
    id: 1,
    username: 'soporte.plataforma',
    passwordHash: hash,
    schoolId: null,
    me: {
      id: '00000000-0000-4000-8000-000000000001',
      username: 'soporte.plataforma',
      displayName: 'Soporte Plataforma',
      firstName: 'Soporte',
      lastName: 'Plataforma',
      email: null,
      roles: [{ role: 'platform_admin', coordinatorType: null }],
    },
  });

  it('platform_admin entra solo por el host de administración', async () => {
    const { app } = setup([student(), admin()]);
    const res = await browser(app, ADMIN_HOST).login('soporte.plataforma');
    expect(res.statusCode).toBe(200);
    expect(res.json().school).toBeNull();
    for (const host of [HOST, OTHER_HOST]) {
      expect((await browser(app, host).login('soporte.plataforma')).statusCode, host).toBe(401);
    }
  });

  it('en el host de administración no entran usuarios de un colegio', async () => {
    const res = await browser(setup().app, ADMIN_HOST).login();
    expect(res.statusCode).toBe(401);
  });

  it('sin PLATFORM_ADMIN_HOST no hay host de administración', async () => {
    const mem = memoryAuthStore([school], [admin()]);
    const app = buildApp({
      config: { LOG_LEVEL: 'silent' },
      checkDb: async () => {},
      auth: { store: mem.store, secret: 'x'.repeat(40), idleMs: IDLE, maxMs: MAX },
    });
    expect((await app.inject({ method: 'GET', url: '/api/v1/auth/csrf', headers: { host: ADMIN_HOST } })).statusCode).toBe(404);
  });

  it('la sesión no vale en el host de otro colegio', async () => {
    const { app, sessions } = setup();
    const a = browser(app);
    await a.login();
    expect(sessions[0]!.schoolId).toBe(school.id);
    const b = browser(app, OTHER_HOST);
    for (const [k, v] of a.jar) b.jar.set(k, v);
    const res = await b.get('/api/v1/me');
    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('unauthenticated');
    // Desde el otro colegio tampoco puede actuar sobre ella (ni revocarla).
    await b.post('/api/v1/auth/logout');
    expect(sessions[0]!.revokedAt).toBeNull();
    // En su colegio sigue funcionando.
    expect((await a.get('/api/v1/me')).statusCode).toBe(200);
  });
});

describe('request.actor', () => {
  it('se carga con la sesión y el colegio del host; sin sesión, 401', async () => {
    const seen: { userId: number; schoolId: number | null; today: string }[] = [];
    const actors: ActorStore = {
      async loadActor(userId, schoolId, today) {
        seen.push({ userId, schoolId, today });
        return { userId, schoolId, roles: new Set(['student'] as const), coordinatorTypes: new Set(), staffId: null, assignments: new Map(), directedGroupIds: new Set(), enrollment: null };
      },
    };
    const probe: FastifyPluginAsync = async (api) => {
      api.get('/yo', async (request) => ({ roles: [...requireActor(request).roles] }));
    };
    const clock = { t: new Date('2026-10-29T03:00:00.000Z') }; // 28/10 en Bogotá
    const mem = memoryAuthStore([school], [student()]);
    const app = buildApp({
      config: { LOG_LEVEL: 'silent' },
      checkDb: async () => {},
      auth: { store: mem.store, actors, secret: 'x'.repeat(40), idleMs: IDLE, maxMs: MAX, now: () => clock.t },
      apiModules: [probe],
    });
    const b = browser(app);
    expect((await b.get('/api/v1/yo')).statusCode).toBe(401);
    await b.login();
    const res = await b.get('/api/v1/yo');
    expect(res.json()).toEqual({ roles: ['student'] });
    expect(seen.at(-1)).toEqual({ userId: 15, schoolId: 1, today: '2026-10-28' });
  });
});
