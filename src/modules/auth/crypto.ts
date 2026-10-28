import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { hash, verify } from '@node-rs/argon2';

// argon2id con los parámetros mínimos de OWASP (19 MiB, 2 pasadas, 1 hilo).
const ARGON2 = { algorithm: 2, memoryCost: 19456, timeCost: 2, parallelism: 1 } as const;

export function hashPassword(password: string): Promise<string> {
  return hash(password, ARGON2);
}

// Hash de una contraseña al azar: se verifica contra él cuando la cuenta no existe
// o no tiene hash válido, para que el tiempo de respuesta no revele qué cuentas hay.
const dummyHash = hashPassword(randomBytes(32).toString('base64url'));

export async function verifyPassword(stored: string | null, password: string): Promise<boolean> {
  const usable = stored !== null && stored.startsWith('$argon2id$v=');
  try {
    const ok = await verify(usable ? stored : await dummyHash, password);
    return usable && ok;
  } catch {
    return false;
  }
}

/** Token opaco para cookies: 32 bytes al azar en base64url. */
export function newToken(): string {
  return randomBytes(32).toString('base64url');
}

export function sha256(value: string): Buffer {
  return createHash('sha256').update(value).digest();
}

/** Token CSRF ligado a la sesión: HMAC del hash de su token (doble envío firmado). */
export function csrfForSession(secret: string, sessionTokenHash: Buffer): string {
  return createHmac('sha256', secret).update('csrf:').update(sessionTokenHash).digest('base64url');
}

export function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  return ab.length === bb.length && timingSafeEqual(ab, bb);
}
