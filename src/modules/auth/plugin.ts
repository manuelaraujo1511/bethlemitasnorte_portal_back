import cookie from '@fastify/cookie';
import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import { AppError } from '../../http/problem.js';
import { csrfForSession, newToken, safeEqual, sha256, verifyPassword } from './crypto.js';
import type { AuthStore, MeRecord, School, SessionRecord } from './store.js';

export const SESSION_COOKIE = '__Host-campus_session';
export const CSRF_COOKIE = '__Host-campus_csrf';
const CSRF_HEADER = 'x-csrf-token';
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);
// Con mustChangePassword solo se permiten estas rutas (openapi.yaml, "Sesión y CSRF").
const ALLOWED_WHILE_MUST_CHANGE = new Set(['/api/v1/me', '/api/v1/auth/csrf', '/api/v1/auth/logout', '/api/v1/auth/password/change']);
// last_used_at se actualiza a lo sumo una vez por minuto, no en cada petición.
const TOUCH_EVERY_MS = 60_000;

export interface AuthOptions {
  store: AuthStore;
  secret: string;
  idleMs: number;
  maxMs: number;
  /** Host del panel de la plataforma (school = null); solo ahí entra platform_admin. */
  adminHost?: string | undefined;
  now?: () => Date;
}

declare module 'fastify' {
  interface FastifyRequest {
    school: School | null;
    session: SessionRecord | null;
    sessionExpired: boolean;
  }
}

const cookieBase = { path: '/', secure: true, sameSite: 'lax' } as const;

const loginBody = {
  type: 'object',
  required: ['username', 'password'],
  additionalProperties: false,
  properties: {
    username: { type: 'string', minLength: 1, maxLength: 80 },
    password: { type: 'string', minLength: 1, maxLength: 128 },
  },
} as const;

const meResponse = {
  type: 'object',
  required: ['id', 'username', 'displayName', 'firstName', 'lastName', 'email', 'mustChangePassword', 'school', 'roles'],
  additionalProperties: false,
  properties: {
    id: { type: 'string' },
    username: { type: 'string' },
    displayName: { type: 'string' },
    firstName: { type: 'string' },
    lastName: { type: 'string' },
    email: { type: ['string', 'null'] },
    mustChangePassword: { type: 'boolean' },
    school: {
      anyOf: [
        {
          type: 'object',
          required: ['id', 'code', 'name', 'timezone'],
          additionalProperties: false,
          properties: { id: { type: 'string' }, code: { type: 'string' }, name: { type: 'string' }, timezone: { type: 'string' } },
        },
        { type: 'null' },
      ],
    },
    roles: {
      type: 'array',
      items: {
        type: 'object',
        required: ['role', 'coordinatorType'],
        additionalProperties: false,
        properties: { role: { type: 'string' }, coordinatorType: { type: ['string', 'null'] } },
      },
    },
  },
} as const;

const invalidCredentials = () => new AppError(401, 'invalid_credentials', 'Usuario o contraseña incorrectos');

/**
 * Sesión, CSRF y rutas /auth/* y /me. Se registra dentro del ámbito /api/v1 sin
 * encapsular (fastify-plugin), así sus hooks cubren también los módulos hermanos.
 */
const auth: FastifyPluginAsync<AuthOptions> = async (app, opts) => {
  const { store, secret, idleMs, maxMs, adminHost } = opts;
  const now = opts.now ?? (() => new Date());

  await app.register(cookie);
  app.decorateRequest('school', null);
  app.decorateRequest('session', null);
  app.decorateRequest('sessionExpired', false);

  const setSessionCookies = (reply: FastifyReply, token: string, tokenHash: Buffer) => {
    reply.setCookie(SESSION_COOKIE, token, { ...cookieBase, httpOnly: true, maxAge: Math.floor(maxMs / 1000) });
    reply.setCookie(CSRF_COOKIE, csrfForSession(secret, tokenHash), { ...cookieBase, httpOnly: false });
  };
  const clearSessionCookies = (reply: FastifyReply) => {
    reply.clearCookie(SESSION_COOKIE, { ...cookieBase, httpOnly: true });
    reply.clearCookie(CSRF_COOKIE, cookieBase);
  };

  const toMe = (me: MeRecord, school: School | null) => ({
    ...me,
    school: school && { id: school.publicId, code: school.code, name: school.name, timezone: school.timezone },
  });

  app.addHook('onRequest', async (request, reply) => {
    // El Host decide el colegio (school_domains) o el panel de la plataforma; cualquier
    // otro host no tiene API. request.hostname sale del Host del cliente (sin trustProxy).
    const host = request.hostname.toLowerCase();
    if (adminHost === undefined || host !== adminHost) {
      request.school = await store.schoolByHost(host);
      if (!request.school) throw new AppError(404, 'not_found', 'No existe');
    }
    const schoolId = request.school?.id ?? null;

    const token = request.cookies[SESSION_COOKIE];
    if (token) {
      const found = await store.findSession(sha256(token));
      // Una sesión solo vale en el colegio (o el panel) donde se inició.
      const record = found && found.schoolId === schoolId ? found : null;
      const t = now().getTime();
      if (found && !record) {
        request.log.warn({ sessionId: found.id }, 'sesión usada desde otro colegio');
      } else if (record) {
        const idleSince = (record.lastUsedAt ?? record.createdAt).getTime();
        if (t >= record.expiresAt.getTime() || t - idleSince >= idleMs) {
          await store.revokeSession(record.id, now());
          request.sessionExpired = true;
          clearSessionCookies(reply);
        } else {
          request.session = record;
          if (t - idleSince >= TOUCH_EVERY_MS) await store.touchSession(record.id, now());
        }
      } else {
        request.sessionExpired = true;
        clearSessionCookies(reply);
      }
    }

    if (!SAFE_METHODS.has(request.method)) {
      const header = request.headers[CSRF_HEADER];
      const cookieValue = request.cookies[CSRF_COOKIE];
      const sent = typeof header === 'string' ? header : '';
      const expected = request.session ? csrfForSession(secret, request.session.tokenHash) : cookieValue;
      if (!sent || !cookieValue || !expected || !safeEqual(sent, cookieValue) || !safeEqual(sent, expected)) {
        throw new AppError(403, 'csrf_invalid', 'Falta el token CSRF o no coincide');
      }
    }
  });

  app.addHook('preHandler', async (request) => {
    if (request.session?.mustChangePassword && !ALLOWED_WHILE_MUST_CHANGE.has(request.routeOptions.url ?? '')) {
      throw new AppError(403, 'password_change_required', 'Debes cambiar tu contraseña antes de seguir');
    }
  });

  const requireSession = (request: FastifyRequest): SessionRecord => {
    if (request.session) return request.session;
    throw request.sessionExpired
      ? new AppError(401, 'session_expired', 'Tu sesión venció; vuelve a entrar')
      : new AppError(401, 'unauthenticated', 'Hay que iniciar sesión');
  };

  app.get('/auth/csrf', async (request, reply) => {
    let csrfToken: string;
    if (request.session) {
      csrfToken = csrfForSession(secret, request.session.tokenHash);
    } else {
      const existing = request.cookies[CSRF_COOKIE];
      csrfToken = existing && /^[A-Za-z0-9_-]{43}$/.test(existing) ? existing : newToken();
    }
    reply.setCookie(CSRF_COOKIE, csrfToken, { ...cookieBase, httpOnly: false });
    return { csrfToken };
  });

  app.post<{ Body: { username: string; password: string } }>(
    '/auth/login',
    { schema: { body: loginBody, response: { 200: meResponse } } },
    async (request, reply) => {
      const { username, password } = request.body;
      const schoolId = request.school?.id ?? null;
      const candidate = await store.findLoginCandidate(schoolId, username.trim());
      // Siempre se verifica un hash (el real o uno ficticio) para que el tiempo no delate la cuenta.
      const passwordOk = await verifyPassword(candidate?.passwordHash ?? null, password);
      const t = now();
      const locked = candidate?.lockedUntil != null && candidate.lockedUntil.getTime() > t.getTime();
      if (!candidate || !passwordOk || !candidate.active || locked) {
        if (candidate && !passwordOk) await store.recordLoginFailure(candidate.userId);
        throw invalidCredentials();
      }
      const me = await store.getMe(candidate.userId, schoolId);
      if (!me) throw invalidCredentials();

      // Rotación: la sesión anterior del navegador, si había, deja de valer.
      if (request.session) await store.revokeSession(request.session.id, t);
      const token = newToken();
      const tokenHash = sha256(token);
      await store.createSession({
        userId: candidate.userId,
        schoolId,
        tokenHash,
        expiresAt: new Date(t.getTime() + maxMs),
        userAgent: request.headers['user-agent'] ?? null,
        now: t,
      });
      await store.recordLoginSuccess(candidate.userId, t);
      setSessionCookies(reply, token, tokenHash);
      return toMe(me, request.school);
    },
  );

  app.post('/auth/logout', async (request, reply) => {
    if (request.session) await store.revokeSession(request.session.id, now());
    clearSessionCookies(reply);
    return reply.code(204).send();
  });

  app.get('/me', { schema: { response: { 200: meResponse } } }, async (request) => {
    const session = requireSession(request);
    const me = await store.getMe(session.userId, request.school?.id ?? null);
    if (!me) throw new AppError(401, 'unauthenticated', 'Hay que iniciar sesión');
    return toMe(me, request.school);
  });
};

export const authPlugin = fp(auth, { name: 'auth' });
