import Fastify, { type FastifyInstance, type FastifyPluginAsync } from 'fastify';
import type { Config } from './config.js';
import { registerProblemHandlers } from './http/problem.js';
import { authPlugin, type AuthOptions } from './modules/auth/plugin.js';
import { healthRoutes } from './modules/health/routes.js';

export interface AppDeps {
  config: Pick<Config, 'LOG_LEVEL'>;
  checkDb: () => Promise<void>;
  /** Sin auth solo quedan /health y /health/ready (pruebas que no la necesitan). */
  auth?: AuthOptions;
  /** Módulos de /api/v1; quedan detrás de la sesión y el CSRF de auth. */
  apiModules?: FastifyPluginAsync[];
}

export function buildApp({ config, checkDb, auth, apiModules = [] }: AppDeps): FastifyInstance {
  const app = Fastify({
    logger: {
      level: config.LOG_LEVEL,
      // Nunca registrar credenciales ni cookies de sesión.
      redact: ['req.headers.authorization', 'req.headers.cookie', 'res.headers["set-cookie"]'],
    },
    // Ids de petición propios; no se confía en cabeceras del cliente.
    genReqId: () => crypto.randomUUID(),
    // Campos de más en el body son 400, no se descartan en silencio.
    ajv: { customOptions: { removeAdditional: false } },
    // La API v1 solo recibe JSON pequeño; los archivos irán por URL firmada.
    bodyLimit: 64 * 1024,
  });

  registerProblemHandlers(app);

  app.register(healthRoutes, { checkDb });
  if (auth) {
    app.register(
      async (api) => {
        await api.register(authPlugin, auth);
        for (const mod of apiModules) await api.register(mod);
      },
      { prefix: '/api/v1' },
    );
  }

  return app;
}
