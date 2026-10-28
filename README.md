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
npm run dev                 # API en http://127.0.0.1:3000
```

Las migraciones viven en `db/migrations/` (se están moviendo desde `backend/db/` del repo del portal, tarea B0.2). Mientras tanto se puede apuntar a ellas con `MIGRATIONS_DIR` y `SEED_FILES` (lista en orden, separada por comas).

## Comandos

| Comando | Qué hace |
|---|---|
| `npm run check` | typecheck + lint + pruebas (lo que corre CI) |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run lint` | ESLint |
| `npm test` | Vitest |
| `npm run build` | Compila a `dist/` |

## Endpoints

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
test/               pruebas Vitest
docs/adr/           decisiones de arquitectura
```
