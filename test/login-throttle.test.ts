import { beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { hashPassword } from '../src/modules/auth/crypto.js';
import { CSRF_COOKIE } from '../src/modules/auth/plugin.js';
import { LoginThrottle, type ThrottleOptions } from '../src/modules/auth/throttle.js';
import { memoryAuthStore, type MemoryUser } from './support/memory-auth-store.js';

const HOST = 'demo.campus.localhost';
const PASSWORD = 'una frase larga de prueba';
const CSRF = 'c'.repeat(43);
const school = { id: 1, publicId: '00000000-0000-4000-8000-000000000001', code: 'demo', name: 'Colegio Demo', timezone: 'America/Bogota', host: HOST };
const OPTS: ThrottleOptions = { windowMs: 15 * 60_000, maxAccountFailures: 3, maxIpFailures: 6, baseLockMs: 60_000, maxLockMs: 240_000 };
const T0 = new Date('2026-10-28T15:00:00.000Z').getTime();

let hash: string;
beforeAll(async () => {
  hash = await hashPassword(PASSWORD);
});

function user(id: number, code: string): MemoryUser {
  return {
    id,
    code,
    username: `user${id}`,
    passwordHash: hash,
    me: {
      id: `00000000-0000-4000-8000-0000000000${id}`,
      username: `user${id}`,
      displayName: 'Persona Sintética',
      firstName: 'Persona',
      lastName: 'Sintética',
      email: null,
      roles: [{ role: 'student', coordinatorType: null }],
    },
  };
}

function setup() {
  const clock = { t: new Date(T0) };
  const mem = memoryAuthStore([school], [user(10, '900001'), user(11, '900002')]);
  const app = buildApp({
    config: { LOG_LEVEL: 'silent' },
    checkDb: async () => {},
    auth: { store: mem.store, secret: 'x'.repeat(40), idleMs: 1_800_000, maxMs: 43_200_000, throttle: new LoginThrottle(OPTS), now: () => clock.t },
  });
  const login = (username: string, password = 'incorrecta', ip = '10.0.0.1') =>
    app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      remoteAddress: ip,
      headers: { host: HOST, cookie: `${CSRF_COOKIE}=${CSRF}`, 'x-csrf-token': CSRF },
      payload: { username, password },
    });
  return { clock, login, ...mem };
}

const body = (r: { json: () => Record<string, unknown> }) => ({ ...r.json(), requestId: undefined });

describe('LoginThrottle', () => {
  it('bloquea al llegar al máximo y duplica la espera en cada bloqueo, hasta el tope', () => {
    const t = new LoginThrottle(OPTS);
    const k = LoginThrottle.accountKey(1, 'ana');
    let now = T0;
    for (let i = 0; i < 2; i++) t.recordFailure(k, 'ip', now);
    expect(t.retryAfterSeconds(k, 'ip', now)).toBe(0);
    t.recordFailure(k, 'ip', now);
    expect(t.retryAfterSeconds(k, 'ip', now)).toBe(60);
    now += 60_000;
    expect(t.retryAfterSeconds(k, 'ip', now)).toBe(0);
    t.recordFailure(k, 'ip', now); // un solo fallo tras el desbloqueo re-bloquea
    expect(t.retryAfterSeconds(k, 'ip', now)).toBe(120);
    now += 120_000;
    t.recordFailure(k, 'ip', now);
    expect(t.retryAfterSeconds(k, 'ip', now)).toBe(240);
    now += 240_000;
    t.recordFailure(k, 'ip', now);
    expect(t.retryAfterSeconds(k, 'ip', now)).toBe(240); // tope
  });

  it('los fallos viejos salen de la ventana y el éxito limpia la cuenta', () => {
    const t = new LoginThrottle(OPTS);
    const k = LoginThrottle.accountKey(1, 'ana');
    t.recordFailure(k, 'a', T0);
    t.recordFailure(k, 'b', T0);
    t.recordFailure(k, 'c', T0 + OPTS.windowMs + 1); // el conteo arranca de nuevo
    expect(t.retryAfterSeconds(k, 'd', T0 + OPTS.windowMs + 1)).toBe(0);
    t.recordFailure(k, 'e', T0 + OPTS.windowMs + 2);
    t.recordSuccess(k);
    t.recordFailure(k, 'f', T0 + OPTS.windowMs + 3);
    t.recordFailure(k, 'g', T0 + OPTS.windowMs + 4);
    expect(t.retryAfterSeconds(k, 'h', T0 + OPTS.windowMs + 4)).toBe(0);
  });

  it('la clave de cuenta ignora mayúsculas y espacios, y separa colegios', () => {
    expect(LoginThrottle.accountKey(1, ' Ana.Torres ')).toBe(LoginThrottle.accountKey(1, 'ana.torres'));
    expect(LoginThrottle.accountKey(1, 'ana')).not.toBe(LoginThrottle.accountKey(2, 'ana'));
    expect(LoginThrottle.accountKey(null, 'ana')).not.toBe(LoginThrottle.accountKey(1, 'ana'));
  });
});

describe('POST /auth/login con límite de intentos', () => {
  it('cuenta real y cuenta inexistente reciben exactamente la misma secuencia de respuestas', async () => {
    const { login } = setup();
    const real: unknown[] = [];
    const ghost: unknown[] = [];
    for (let i = 0; i < 5; i++) {
      const a = await login('900001', 'incorrecta', `10.0.1.${i}`);
      const b = await login('999999', 'incorrecta', `10.0.2.${i}`);
      real.push([a.statusCode, a.headers['retry-after'], body(a)]);
      ghost.push([b.statusCode, b.headers['retry-after'], body(b)]);
    }
    expect(ghost).toEqual(real);
    expect(real.map((r) => (r as [number])[0])).toEqual([401, 401, 401, 429, 429]);
  });

  it('bloquea la cuenta aun con la contraseña correcta, con Retry-After y problem+json', async () => {
    const { login } = setup();
    for (let i = 0; i < 3; i++) await login('900001');
    const res = await login('900001', PASSWORD);
    expect(res.statusCode).toBe(429);
    expect(res.headers['retry-after']).toBe('60');
    expect(res.headers['content-type']).toContain('application/problem+json');
    expect(res.json()).toMatchObject({ status: 429, code: 'too_many_attempts' });
    expect(res.headers['set-cookie'] ?? '').not.toContain('campus_session');
  });

  it('el bloqueo es progresivo y termina: pasada la espera vuelve a dejar entrar', async () => {
    const { login, clock } = setup();
    for (let i = 0; i < 3; i++) await login('900001');
    clock.t = new Date(T0 + 60_000);
    expect((await login('900001')).statusCode).toBe(401); // un fallo y re-bloquea
    const second = await login('900001', PASSWORD);
    expect(second.statusCode).toBe(429);
    expect(second.headers['retry-after']).toBe('120');
    clock.t = new Date(T0 + 60_000 + 120_000);
    expect((await login('900001', PASSWORD)).statusCode).toBe(200);
  });

  it('un acceso correcto reinicia el conteo de la cuenta', async () => {
    const { login } = setup();
    for (let i = 0; i < 2; i++) await login('900001');
    expect((await login('900001', PASSWORD)).statusCode).toBe(200);
    for (let i = 0; i < 2; i++) expect((await login('900001')).statusCode).toBe(401);
  });

  it('un bloqueo no afecta a otras cuentas', async () => {
    const { login } = setup();
    for (let i = 0; i < 3; i++) await login('900001');
    expect((await login('900002', PASSWORD, '10.0.9.9')).statusCode).toBe(200);
  });

  it('bloquea por IP aunque cada intento sea contra una cuenta distinta', async () => {
    const { login } = setup();
    for (let i = 0; i < 6; i++) expect((await login(`inexistente${i}`)).statusCode).toBe(401);
    const blocked = await login('900002', PASSWORD);
    expect(blocked.statusCode).toBe(429);
    expect(blocked.headers['retry-after']).toBe('60');
    // Otra IP no queda afectada.
    expect((await login('900002', PASSWORD, '10.0.9.9')).statusCode).toBe(200);
  });

  it('el 429 no revela datos de la cuenta ni del límite configurado', async () => {
    const { login } = setup();
    for (let i = 0; i < 3; i++) await login('900001');
    const res = await login('900001');
    expect(JSON.stringify(res.json())).not.toMatch(/900001|user10|intentos restantes/);
  });
});

describe('configuración del límite', () => {
  const base = { DB_HOST: 'localhost', DB_USER: 'campus', DB_PASSWORD: 'x', DB_NAME: 'campus', SESSION_SECRET: 's'.repeat(32) };

  it('tiene valores por defecto y se puede ajustar por variables de entorno', () => {
    expect(loadConfig(base)).toMatchObject({ LOGIN_WINDOW_MINUTES: 15, LOGIN_MAX_ATTEMPTS: 5, LOGIN_IP_MAX_ATTEMPTS: 30, LOGIN_LOCK_MAX_MINUTES: 30 });
    expect(loadConfig({ ...base, LOGIN_MAX_ATTEMPTS: '8', LOGIN_WINDOW_MINUTES: '30' })).toMatchObject({ LOGIN_MAX_ATTEMPTS: 8, LOGIN_WINDOW_MINUTES: 30 });
    expect(() => loadConfig({ ...base, LOGIN_MAX_ATTEMPTS: '1' })).toThrow(/LOGIN_MAX_ATTEMPTS/);
  });
});
