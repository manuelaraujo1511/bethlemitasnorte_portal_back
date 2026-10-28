import { readFileSync } from 'node:fs';
import { Ajv2020 } from 'ajv/dist/2020.js';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';
import { buildApp } from '../src/app.js';
import { AppError, errorCodes } from '../src/http/problem.js';

const spec = parse(readFileSync(new URL('../openapi.yaml', import.meta.url), 'utf8'));
const ajv = new Ajv2020({ strict: false, validateFormats: false });
ajv.addSchema({ $id: 'openapi', components: spec.components });
const validateProblem = ajv.getSchema('openapi#/components/schemas/Problem')!;

function app() {
  const a = buildApp({ config: { LOG_LEVEL: 'silent' }, checkDb: async () => {} });
  a.post(
    '/api/v1/_test/echo',
    { schema: { body: { type: 'object', required: ['name'], properties: { name: { type: 'string' } } } } },
    async (req) => req.body,
  );
  a.get('/api/v1/_test/boom', async () => {
    throw new Error("ER_ACCESS_DENIED_ERROR: Access denied for user 'campus'@'10.0.0.5'");
  });
  a.get('/api/v1/_test/conflict', async () => {
    throw Object.assign(new Error('fila duplicada en users'), { statusCode: 409 });
  });
  a.get('/api/v1/_test/app-error', async () => {
    throw new AppError(401, 'invalid_credentials', 'Usuario o contraseña incorrectos');
  });
  return a;
}

function expectProblem(res: { headers: Record<string, unknown>; json: () => unknown }, status: number, code: string) {
  expect(res.headers['content-type']).toMatch(/^application\/problem\+json/);
  const body = res.json() as Record<string, unknown>;
  expect(validateProblem(body), JSON.stringify(validateProblem.errors)).toBe(true);
  expect(body.status).toBe(status);
  expect(body.code).toBe(code);
  expect(typeof body.requestId).toBe('string');
  return body;
}

describe('contrato openapi.yaml', () => {
  it('v1 solo expone /auth/* y /me en esta fase', () => {
    expect(spec.servers).toEqual([{ url: '/api/v1' }]);
    expect(Object.keys(spec.paths).sort()).toEqual([
      '/auth/csrf',
      '/auth/login',
      '/auth/logout',
      '/auth/password/change',
      '/auth/password/forgot',
      '/auth/password/reset',
      '/me',
    ]);
  });

  it('los códigos de error del servidor son los del contrato', () => {
    expect([...errorCodes].sort()).toEqual([...spec.components.schemas.ErrorCode.enum].sort());
  });
});

describe('errores como problem+json', () => {
  it('404 en una ruta inexistente', async () => {
    const res = await app().inject({ method: 'GET', url: '/api/v1/no-existe' });
    expectProblem(res, 404, 'not_found');
  });

  it('400 con el campo que falla', async () => {
    const res = await app().inject({ method: 'POST', url: '/api/v1/_test/echo', payload: {} });
    const body = expectProblem(res, 400, 'validation_failed');
    expect(body.errors).toEqual([{ field: 'name', message: expect.any(String) }]);
  });

  it('400 con JSON mal formado', async () => {
    const res = await app().inject({
      method: 'POST',
      url: '/api/v1/_test/echo',
      headers: { 'content-type': 'application/json' },
      payload: '{"name":',
    });
    expectProblem(res, 400, 'validation_failed');
  });

  it('413 si el cuerpo pasa de 64 KiB', async () => {
    const res = await app().inject({
      method: 'POST',
      url: '/api/v1/_test/echo',
      payload: { name: 'x'.repeat(70 * 1024) },
    });
    expectProblem(res, 413, 'payload_too_large');
  });

  it('un 4xx sin código propio conserva su estado y no se vuelve 500', async () => {
    const res = await app().inject({ method: 'GET', url: '/api/v1/_test/conflict' });
    expectProblem(res, 409, 'request_rejected');
    expect(res.body).not.toContain('fila duplicada');
  });

  it('un AppError conserva su estado y código', async () => {
    const res = await app().inject({ method: 'GET', url: '/api/v1/_test/app-error' });
    expectProblem(res, 401, 'invalid_credentials');
  });

  it('500 sin filtrar el mensaje interno', async () => {
    const res = await app().inject({ method: 'GET', url: '/api/v1/_test/boom' });
    const body = expectProblem(res, 500, 'internal_error');
    expect(res.body).not.toMatch(/ER_ACCESS_DENIED|campus|10\.0\.0\.5/);
    expect(body.detail).toBeUndefined();
  });
});
