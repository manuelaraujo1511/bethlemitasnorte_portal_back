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
  // Firma del token CSRF ligado a la sesión (HMAC). 32 caracteres o más, fuera del repo.
  SESSION_SECRET: z.string().min(32),
  // Sin uso durante este tiempo la sesión vence; y vence siempre al cumplir la vida máxima.
  SESSION_IDLE_MINUTES: z.coerce.number().int().min(5).max(24 * 60).default(30),
  SESSION_MAX_HOURS: z.coerce.number().int().min(1).max(24 * 30).default(12),
  // Host del panel de administración de la plataforma: el único donde entra platform_admin.
  // Sin definir, platform_admin no entra por ningún host.
  PLATFORM_ADMIN_HOST: z
    .string()
    .regex(/^[a-z0-9.-]+$/)
    .optional(),
  // TLS hacia la base: obligatorio fuera de desarrollo (docs/database-design.md).
  DB_SSL: z
    .enum(['true', 'false'])
    .default('false')
    .transform((v) => v === 'true'),
});

// Comienzo del valor de ejemplo de .env.example.
const EXAMPLE_SESSION_SECRET_PREFIX = 'genera-uno-propio';

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
  if (config.NODE_ENV === 'production' && config.SESSION_SECRET.startsWith(EXAMPLE_SESSION_SECRET_PREFIX)) {
    throw new Error('SESSION_SECRET de producción no puede ser el de .env.example');
  }
  return config;
}
