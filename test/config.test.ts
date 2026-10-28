import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';

const base = { DB_HOST: 'localhost', DB_USER: 'campus', DB_PASSWORD: 'x', DB_NAME: 'campus', SESSION_SECRET: 's'.repeat(32) };

describe('loadConfig', () => {
  it('aplica valores por defecto', () => {
    const config = loadConfig(base);
    expect(config.PORT).toBe(3000);
    expect(config.DB_PORT).toBe(3306);
    expect(config.DB_SSL).toBe(false);
  });

  it('nombra las variables que faltan sin mostrar valores', () => {
    expect(() => loadConfig({ DB_PASSWORD: 'secreto-no-visible' })).toThrow(
      /DB_HOST, DB_USER, DB_NAME/,
    );
    expect(() => loadConfig({ ...base, PORT: 'abc', DB_PASSWORD: 'secreto' })).not.toThrow(/secreto/);
  });

  it('exige TLS hacia la base en producción', () => {
    expect(() => loadConfig({ ...base, NODE_ENV: 'production' })).toThrow(/DB_SSL/);
    expect(loadConfig({ ...base, NODE_ENV: 'production', DB_SSL: 'true' }).DB_SSL).toBe(true);
  });

  it('rechaza en producción el SESSION_SECRET de .env.example', () => {
    const prod = { ...base, NODE_ENV: 'production', DB_SSL: 'true' };
    expect(() => loadConfig({ ...prod, SESSION_SECRET: 'genera-uno-propio-de-al-menos-32-caracteres' })).toThrow(/SESSION_SECRET/);
    expect(() => loadConfig(prod)).not.toThrow();
  });

  it('valida PLATFORM_ADMIN_HOST', () => {
    expect(loadConfig(base).PLATFORM_ADMIN_HOST).toBeUndefined();
    expect(loadConfig({ ...base, PLATFORM_ADMIN_HOST: 'admin.campus.localhost' }).PLATFORM_ADMIN_HOST).toBe('admin.campus.localhost');
    expect(() => loadConfig({ ...base, PLATFORM_ADMIN_HOST: 'Admin.Campus' })).toThrow(/PLATFORM_ADMIN_HOST/);
  });
});
