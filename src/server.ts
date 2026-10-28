import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { createDb, pingDb } from './db.js';
import { createKyselyAuthStore } from './modules/auth/store.js';

const config = loadConfig();
const db = createDb(config);
const app = buildApp({
  config,
  checkDb: () => pingDb(db),
  auth: {
    store: createKyselyAuthStore(db),
    secret: config.SESSION_SECRET,
    idleMs: config.SESSION_IDLE_MINUTES * 60_000,
    maxMs: config.SESSION_MAX_HOURS * 3_600_000,
  },
});

async function shutdown(signal: string): Promise<void> {
  app.log.info({ signal }, 'cerrando');
  await app.close();
  await db.destroy();
  process.exit(0);
}

process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));

try {
  await app.listen({ host: config.HOST, port: config.PORT });
} catch (err) {
  app.log.fatal({ err }, 'no se pudo iniciar');
  await db.destroy();
  process.exit(1);
}
