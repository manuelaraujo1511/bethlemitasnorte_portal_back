# bethlemitasnorte_portal_back

API del portal Bethlemitas Norte. Frontend: [`bethlemitasnorte_portal`](https://github.com/manuelaraujo1511/bethlemitasnorte_portal).

- Plan de desarrollo (oficial): [`docs/plan-desarrollo.md`](https://github.com/manuelaraujo1511/bethlemitasnorte_portal/blob/main/docs/plan-desarrollo.md) en el repo del portal.
- Stack: [ADR 0001](docs/adr/0001-stack.md). Node 22, TypeScript, Fastify, Kysely sobre MySQL 8, Zod, Vitest.
- Agente de desarrollo y auditoría: [`.claude/agents/backend.md`](.claude/agents/backend.md).

Solo datos inventados: no se cargan datos reales de estudiantes, familias ni docentes hasta cerrar la revisión legal.

## Desarrollo local

Requiere Node 22 y Docker.

```bash
cp .env.example .env        # cambia DB_PASSWORD
npm install
npm run db:up               # MySQL 8.4 en 127.0.0.1:3306
npm run db:migrate          # aplica db/migrations/*.sql pendientes
npm run db:seed             # migraciones + datos inventados (nunca en producción)
npm run db:test             # pruebas de la base (ver db/README.md)
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

[`openapi.yaml`](openapi.yaml) es el contrato v1 (`/api/v1`). Un endpoint nuevo empieza como cambio en ese archivo; el front genera sus tipos desde ahí. Ahí están las convenciones: errores `application/problem+json` con `code` estable, paginación por cursor, fechas en UTC, sesión por cookie y CSRF de doble envío. Hoy define `/auth/*` y `/me`; las rutas se implementan en B1.2 y B2.1.

Todos los errores ya salen como `application/problem+json` (`src/http/problem.ts`); un 5xx solo devuelve `requestId`.

## Endpoints implementados

| Ruta | Uso |
|---|---|
| `GET /health` | El proceso responde; no toca la base |
| `GET /health/ready` | La base responde (`503` si no) |

## Estructura

```
src/
  app.ts            construcción de la app Fastify (sin red, se prueba con inject)
  server.ts         arranque y cierre ordenado
  config.ts         variables de entorno validadas con Zod
  db.ts             Kysely + pool mysql2 en UTC
  modules/<módulo>/ rutas y lógica por módulo
scripts/migrate.ts  runner de migraciones SQL
db/migrations/      0001_*.sql, 0002_*.sql, ...
db/seed_*.sql       datos inventados de desarrollo
db/tests/           pruebas y medición de la base
test/               pruebas Vitest
docs/adr/           decisiones de arquitectura
```
