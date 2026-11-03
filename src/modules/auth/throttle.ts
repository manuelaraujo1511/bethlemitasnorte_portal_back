import { createHash } from 'node:crypto';

export interface ThrottleOptions {
  /** Ventana en la que se cuentan los fallos seguidos. */
  windowMs: number;
  /** Fallos por cuenta dentro de la ventana antes de bloquear. */
  maxAccountFailures: number;
  /** Fallos por IP dentro de la ventana antes de bloquear (mayor: hay colegios tras una misma IP). */
  maxIpFailures: number;
  /** Primer bloqueo; cada bloqueo siguiente dura el doble. */
  baseLockMs: number;
  /** Tope de la duración de un bloqueo. */
  maxLockMs: number;
}

export const defaultThrottle: ThrottleOptions = {
  windowMs: 15 * 60_000,
  maxAccountFailures: 5,
  maxIpFailures: 30,
  baseLockMs: 60_000,
  maxLockMs: 30 * 60_000,
};

interface Entry {
  fails: number;
  strikes: number;
  lastFailAt: number;
  lockedUntil: number;
}

const MAX_ENTRIES = 50_000;

/**
 * Bloqueo progresivo de login. El estado es por clave (cuenta o IP), no por fila de
 * usuario: una cuenta inexistente se bloquea igual que una real, así el 429 no delata
 * qué cuentas hay. Vive en memoria del proceso (se pierde al reiniciar y no se comparte
 * entre instancias); la columna users.locked_until sigue valiendo para bloqueos manuales.
 */
export class LoginThrottle {
  private readonly accounts = new Map<string, Entry>();
  private readonly ips = new Map<string, Entry>();

  constructor(private readonly opts: ThrottleOptions = defaultThrottle) {}

  /** Clave de cuenta: hash de colegio + usuario normalizado, nunca el usuario en claro. */
  static accountKey(schoolId: number | null, username: string): string {
    return createHash('sha256').update(`${schoolId ?? 'admin'}|${username.trim().toLowerCase()}`).digest('base64url');
  }

  /** Segundos que faltan para poder intentar, o 0 si puede. Toma el mayor de cuenta e IP. */
  retryAfterSeconds(accountKey: string, ip: string, now: number): number {
    const waits = [this.accounts.get(accountKey), this.ips.get(ip)].map((e) => (e && e.lockedUntil > now ? e.lockedUntil - now : 0));
    return Math.ceil(Math.max(...waits) / 1000);
  }

  recordFailure(accountKey: string, ip: string, now: number): void {
    this.bump(this.accounts, accountKey, this.opts.maxAccountFailures, now);
    this.bump(this.ips, ip, this.opts.maxIpFailures, now);
  }

  /** Un acceso correcto limpia la cuenta; la IP no, para que no sirva de comodín. */
  recordSuccess(accountKey: string): void {
    this.accounts.delete(accountKey);
  }

  private bump(map: Map<string, Entry>, key: string, max: number, now: number): void {
    let e = map.get(key);
    // Sin fallos ni bloqueo recientes se empieza de cero.
    if (e && now - Math.max(e.lastFailAt, e.lockedUntil) > this.opts.windowMs) e = undefined;
    if (!e) {
      if (map.size >= MAX_ENTRIES) this.sweep(map, now);
      e = { fails: 0, strikes: 0, lastFailAt: now, lockedUntil: 0 };
    }
    e.fails += 1;
    e.lastFailAt = now;
    if (e.fails >= max) {
      // Tras el primer bloqueo basta un fallo más para el siguiente, del doble de duración.
      e.strikes += 1;
      e.lockedUntil = now + Math.min(this.opts.baseLockMs * 2 ** (e.strikes - 1), this.opts.maxLockMs);
    }
    map.set(key, e);
  }

  private sweep(map: Map<string, Entry>, now: number): void {
    for (const [k, e] of map) if (now - Math.max(e.lastFailAt, e.lockedUntil) > this.opts.windowMs) map.delete(k);
    // Si aun así está lleno, se descarta lo más antiguo (el Map conserva el orden de inserción).
    for (const k of map.keys()) {
      if (map.size < MAX_ENTRIES) break;
      map.delete(k);
    }
  }
}
