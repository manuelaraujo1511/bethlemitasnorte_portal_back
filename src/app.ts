import Fastify, { type FastifyInstance } from 'fastify';
import type { Config } from './config.js';
import { healthRoutes } from './modules/health/routes.js';

export interface AppDeps {
  config: Pick<Config, 'LOG_LEVEL'>;
  checkDb: () => Promise<void>;
}

export function buildApp({ config, checkDb }: AppDeps): FastifyInstance {
  const app = Fastify({
    logger: {
      level: config.LOG_LEVEL,
      // Nunca registrar credenciales ni cookies de sesión.
      redact: ['req.headers.authorization', 'req.headers.cookie', 'res.headers["set-cookie"]'],
    },
    // Ids de petición propios; no se confía en cabeceras del cliente.
    genReqId: () => crypto.randomUUID(),
  });

  app.register(healthRoutes, { checkDb });

  return app;
}
