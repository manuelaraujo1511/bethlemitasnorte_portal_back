import type { FastifyPluginAsync } from 'fastify';

export interface HealthOptions {
  checkDb: () => Promise<void>;
}

export const healthRoutes: FastifyPluginAsync<HealthOptions> = async (app, opts) => {
  // Vivo: el proceso responde. No toca dependencias.
  app.get('/health', async () => ({ status: 'ok' }));

  // Listo: puede atender tráfico (la base responde).
  app.get('/health/ready', async (request, reply) => {
    try {
      await opts.checkDb();
      return { status: 'ok', checks: { db: 'ok' } };
    } catch (err) {
      request.log.error({ err }, 'base de datos no disponible');
      return reply.code(503).send({ status: 'error', checks: { db: 'error' } });
    }
  });
};
