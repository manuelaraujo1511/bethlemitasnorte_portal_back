import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';

const base = { DB_HOST: 'localhost', DB_USER: 'campus', DB_PASSWORD: 'x', DB_NAME: 'campus' };

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
});
