import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  HOST: z.string().default('127.0.0.1'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
  DB_HOST: z.string().min(1),
  DB_PORT: z.coerce.number().int().min(1).max(65535).default(3306),
  DB_USER: z.string().min(1),
  DB_PASSWORD: z.string(),
  DB_NAME: z.string().min(1),
  DB_POOL_SIZE: z.coerce.number().int().min(1).max(100).default(10),
  // TLS hacia la base: obligatorio fuera de desarrollo (docs/database-design.md).
  DB_SSL: z
    .enum(['true', 'false'])
    .default('false')
    .transform((v) => v === 'true'),
});

export type Config = z.infer<typeof envSchema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = envSchema.safeParse(env);
  if (!parsed.success) {
    // Solo los nombres de las variables, nunca sus valores.
    const fields = [...new Set(parsed.error.issues.map((i) => i.path.join('.')))];
    throw new Error(`Configuración inválida en: ${fields.join(', ')}`);
  }
  const config = parsed.data;
  if (config.NODE_ENV === 'production' && !config.DB_SSL) {
    throw new Error('DB_SSL debe ser true en producción');
  }
  return config;
}
