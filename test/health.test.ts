import { describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';

function app(checkDb: () => Promise<void>) {
  return buildApp({ config: { LOG_LEVEL: 'silent' }, checkDb });
}

describe('health', () => {
  it('GET /health responde sin tocar la base', async () => {
    let called = false;
    const res = await app(async () => {
      called = true;
    }).inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok' });
    expect(called).toBe(false);
  });

  it('GET /health/ready responde 200 si la base responde', async () => {
    const res = await app(async () => {}).inject({ method: 'GET', url: '/health/ready' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok', checks: { db: 'ok' } });
  });

  it('GET /health/ready responde 503 sin filtrar el error', async () => {
    const res = await app(async () => {
      throw new Error('ECONNREFUSED 10.0.0.5:3306 usuario campus');
    }).inject({ method: 'GET', url: '/health/ready' });
    expect(res.statusCode).toBe(503);
    expect(res.body).not.toContain('ECONNREFUSED');
    expect(res.json()).toEqual({ status: 'error', checks: { db: 'error' } });
  });
});
