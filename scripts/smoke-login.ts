// Prueba de humo del login contra un servidor en marcha y la base con seed.
// Uso: DEV_PASSWORD=... npx tsx scripts/smoke-login.ts [usuario]
import { request } from 'node:http';

const HOST = process.env.SMOKE_HOST ?? 'demo.campus.localhost';
const PORT = Number(process.env.PORT ?? 3000);
const username = process.argv[2] ?? 'luis.gomez';
const password = process.env.DEV_PASSWORD ?? '';
const jar = new Map<string, string>();

interface Res {
  status: number;
  body: unknown;
}

function call(method: string, path: string, body?: unknown): Promise<Res> {
  const payload = body === undefined ? undefined : JSON.stringify(body);
  const headers: Record<string, string> = { host: HOST };
  if (jar.size > 0) headers.cookie = [...jar].map(([k, v]) => `${k}=${v}`).join('; ');
  const csrf = jar.get('__Host-campus_csrf');
  if (method !== 'GET' && csrf) headers['x-csrf-token'] = csrf;
  if (payload) headers['content-type'] = 'application/json';
  return new Promise((resolve, reject) => {
    const req = request({ host: '127.0.0.1', port: PORT, method, path, headers }, (res) => {
      for (const c of res.headers['set-cookie'] ?? []) {
        const [pair = ''] = c.split(';');
        const i = pair.indexOf('=');
        const name = pair.slice(0, i);
        const value = pair.slice(i + 1);
        if (value === '') jar.delete(name);
        else jar.set(name, value);
      }
      let data = '';
      res.on('data', (chunk: Buffer) => (data += chunk.toString()));
      res.on('end', () => resolve({ status: res.statusCode ?? 0, body: data ? (JSON.parse(data) as unknown) : null }));
    });
    req.on('error', reject);
    req.end(payload);
  });
}

function expectStatus(step: string, res: Res, status: number): void {
  if (res.status !== status) {
    console.error(`${step}: esperaba ${status}, llegó ${res.status}`, res.body);
    process.exit(1);
  }
  console.log(`${step}: ${status} ok`);
}

expectStatus('csrf', await call('GET', '/api/v1/auth/csrf'), 200);
expectStatus('login con clave errada', await call('POST', '/api/v1/auth/login', { username, password: `${password}x` }), 401);
expectStatus('login', await call('POST', '/api/v1/auth/login', { username, password }), 200);
expectStatus('me', await call('GET', '/api/v1/me'), 200);
expectStatus('logout', await call('POST', '/api/v1/auth/logout'), 204);
expectStatus('me tras logout', await call('GET', '/api/v1/me'), 401);
