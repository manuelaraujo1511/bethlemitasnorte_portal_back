# bethlemitasnorte_portal_back

API del portal Bethlemitas Norte. Frontend: [`bethlemitasnorte_portal`](https://github.com/manuelaraujo1511/bethlemitasnorte_portal).

- Plan de desarrollo (oficial): [`docs/plan-desarrollo.md`](https://github.com/manuelaraujo1511/bethlemitasnorte_portal/blob/main/docs/plan-desarrollo.md) en el repo del portal.
- Stack: [ADR 0001](docs/adr/0001-stack.md). Node 22, TypeScript, Fastify, Kysely sobre MySQL 8, Zod, Vitest.
- Agente de desarrollo y auditoría: [`.claude/agents/backend.md`](.claude/agents/backend.md).

Solo datos inventados: no se cargan datos reales de estudiantes, familias ni docentes hasta cerrar la revisión legal.

## Desarrollo local

Requiere Node 22 y Docker.

```bash
cp .env.example .env        # cambia DB_PASSWORD y SESSION_SECRET
npm install
npm run db:up               # MySQL 8.4 en 127.0.0.1:3306
npm run db:migrate          # aplica db/migrations/*.sql pendientes
npm run db:seed             # migraciones + datos inventados (nunca en producción)
npm run db:test             # pruebas de la base (ver db/README.md)
DEV_PASSWORD='una-clave-de-12+' npm run db:dev-passwords  # clave común para los usuarios del seed
npm run dev                 # API en http://127.0.0.1:3000
```

La base de datos vive en [`db/`](db/README.md): migraciones, seeds de desarrollo y pruebas. Las migraciones nuevas se escriben solo aquí (se movieron desde el repo del portal en la tarea B0.2). `npm run db:test` usa el cliente `mysql`; con el MySQL de Docker: `MYSQL="docker compose exec -T -e MYSQL_PWD mysql mysql -uroot" MYSQL_PWD=<DB_ROOT_PASSWORD> npm run db:test`.

## Comandos

| Comando | Qué hace |
|---|---|
| `npm run check` | typecheck + lint + contrato + pruebas (lo que corre CI) |
| `npm run api:lint` | Valida `openapi.yaml` (Redocly, reglas estrictas) |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run lint` | ESLint |
| `npm test` | Vitest |
| `npm run build` | Compila a `dist/` |

## Contrato de la API

[`openapi.yaml`](openapi.yaml) es el contrato v1 (`/api/v1`). Un endpoint nuevo empieza como cambio en ese archivo; el front genera sus tipos desde ahí. Ahí están las convenciones: errores `application/problem+json` con `code` estable, paginación por cursor, fechas en UTC, sesión por cookie y CSRF de doble envío. Hoy define `/auth/*` y `/me`.

Todos los errores ya salen como `application/problem+json` (`src/http/problem.ts`); un 5xx solo devuelve `requestId`.

## Endpoints implementados

| Ruta | Uso |
|---|---|
| `GET /health` | El proceso responde; no toca la base |
| `GET /health/ready` | La base responde (`503` si no) |
| `GET /api/v1/auth/csrf` | Entrega la cookie `__Host-campus_csrf` (hay que mandarla en `X-CSRF-Token` en todo lo que no sea GET) |
| `POST /api/v1/auth/login` | Usuario (o código de estudiante) y contraseña; abre sesión nueva y rota el CSRF |
| `POST /api/v1/auth/logout` | Revoca la sesión y borra las cookies |
| `GET /api/v1/me` | Usuario de la sesión, colegio y roles |

Login (B1.2): el colegio sale del `Host` (`school_domains`); la contraseña se verifica con argon2id y, si el usuario no existe, contra un hash ficticio, para que el tiempo de respuesta no delate qué usuarios existen. La sesión es un token aleatorio en `__Host-campus_session` (HttpOnly, Secure, SameSite=Lax) y en la base solo queda su SHA-256. Vence por inactividad (`SESSION_IDLE_MINUTES`) y por vida máxima (`SESSION_MAX_HOURS`). Con sesión, el token CSRF es un HMAC del hash de la sesión con `SESSION_SECRET`, así que un CSRF de otra sesión no sirve. Si el usuario debe cambiar la contraseña, todo responde `403 password_change_required` menos `/me`, `/auth/csrf`, `/auth/logout` y `/auth/password/change`. Para probar en local, pide con `Host: demo.campus.localhost` (o `localhost`).

Hosts: el colegio sale del `Host` y la sesión queda atada al colegio donde se inició (`auth_sessions.school_id`). `platform_admin` solo entra por `PLATFORM_ADMIN_HOST`, y un host que no es de ningún colegio ni del panel responde `404` en `/api/v1`. La API no usa `trustProxy`: en producción el proxy debe reenviar el `Host` original del navegador (no reescribirlo ni depender de `X-Forwarded-Host`); queda anotado para el despliegue (B7.x).

## Permisos (B1.3)

Con sesión, `request.actor` trae roles, tipos de coordinación, asignaciones vigentes hoy (titular o reemplazo dentro de su vigencia, en la fecha del colegio), grupos que dirige y la matrícula activa (`src/modules/authz/actor.ts`). Toda decisión de permisos pasa por `can(actor, acción, recurso)` / `authorize(...)` en `src/modules/authz/policy.ts`, que sigue la matriz de `docs/database-design.md §2` del portal; `test/policy.test.ts` la prueba tabla por tabla. `authorize` responde `404` si la persona no puede ver el recurso y `403` si lo ve pero no puede hacer la acción. Un recurso de otro colegio nunca se permite, y el admin de plataforma no ve datos de menores.

Lecturas de la matriz que se tomaron como supuesto: en el observador, la coordinación académica gestiona las observaciones académicas y la de convivencia las de convivencia, y cualquier coordinación las de reconocimiento. Un mensaje solo lo leen y responden sus participantes; escribir uno nuevo es `new_message`, donde irá la regla de quién le escribe a quién (pregunta 5). Docentes y estudiantes no ven cuentas de otras personas, solo su contacto (`user_contact`). Docentes y estudiantes ven los eventos y avisos de sus grupos o los de todo el colegio.

## Estructura

```
src/
  app.ts            construcción de la app Fastify (sin red, se prueba con inject)
  server.ts         arranque y cierre ordenado
  config.ts         variables de entorno validadas con Zod
  db.ts             Kysely + pool mysql2 en UTC
  modules/<módulo>/ rutas y lógica por módulo
scripts/migrate.ts  runner de migraciones SQL
scripts/dev-passwords.ts  clave de desarrollo para los usuarios del seed
scripts/smoke-login.ts    login de punta a punta contra un servidor en marcha (CI)
db/migrations/      0001_*.sql, 0002_*.sql, ...
db/seed_*.sql       datos inventados de desarrollo
db/tests/           pruebas y medición de la base
test/               pruebas Vitest
docs/adr/           decisiones de arquitectura
```
