// Pone una misma contraseña de desarrollo a los usuarios del seed (los que
// tienen el hash de marcador) para poder probar el login en local.
// Uso: DEV_PASSWORD='algo-de-12-o-mas' npm run db:dev-passwords
import { createConnection } from 'mysql2/promise';
import type { ResultSetHeader } from 'mysql2';
import { loadConfig } from '../src/config.js';
import { hashPassword } from '../src/modules/auth/crypto.js';

const PLACEHOLDER = '$argon2id$DEV-PLACEHOLDER-NOT-A-REAL-HASH';

const config = loadConfig();
if (config.NODE_ENV === 'production') {
  console.error('Las contraseñas de desarrollo no se aplican en producción.');
  process.exit(1);
}
const password = process.env.DEV_PASSWORD ?? '';
if (password.length < 12) {
  console.error('Define DEV_PASSWORD con al menos 12 caracteres.');
  process.exit(1);
}

const conn = await createConnection({
  host: config.DB_HOST,
  port: config.DB_PORT,
  user: config.DB_USER,
  password: config.DB_PASSWORD,
  database: config.DB_NAME,
  ssl: config.DB_SSL ? { rejectUnauthorized: true } : undefined,
});
try {
  const [res] = await conn.execute<ResultSetHeader>(
    'UPDATE users SET password_hash = ?, must_change_password = 0 WHERE password_hash = ?',
    [await hashPassword(password), PLACEHOLDER],
  );
  console.log(`Contraseña de desarrollo aplicada a ${res.affectedRows} usuarios.`);
} finally {
  await conn.end();
}
