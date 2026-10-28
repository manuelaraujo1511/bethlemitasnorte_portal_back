# ADR 0001: Stack del backend

- Estado: aceptado
- Fecha: 2026-10-28
- Decidió: Manuel
- Tarea: B0.1 de [`docs/plan-desarrollo.md`](https://github.com/manuelaraujo1511/bethlemitasnorte_portal/blob/main/docs/plan-desarrollo.md) del repo del portal

## Contexto

El portal tiene un prototipo web en React + Vite + TypeScript (`campus/`) con un paquete `packages/core` que contiene los tipos y la lógica de calificación (escala 10 a 50, Definitivo 30/40/30, autoevaluación). El esquema de base de datos ya está escrito y probado en MySQL 8 (migraciones `0001`–`0003`, 46 tablas). No existía ningún código de API.

Se evaluaron tres opciones: Node + TypeScript, PHP + Laravel y Python + FastAPI.

## Decisión

Node 22 + TypeScript estricto con:

| Pieza | Elección | Por qué |
|---|---|---|
| Servidor HTTP | Fastify 5 | Rápido, con plugins encapsulados, validación por esquema y logger (pino) con redacción de campos |
| Acceso a datos | Kysely sobre `mysql2` | SQL tipado sin ORM; encaja con migraciones SQL escritas a mano y con las FK compuestas y columnas generadas del esquema |
| Validación y contrato | Zod, con OpenAPI generado desde los esquemas (B0.4) | Un solo origen para validar entradas y documentar la API |
| Pruebas | Vitest | El mismo runner que el front |
| Lint | ESLint + typescript-eslint | Reglas comunes; `no-console` en el código de la API |
| Base local | MySQL 8.4 en Docker Compose | Solo con datos inventados |

Las migraciones siguen siendo archivos `.sql` numerados; `scripts/migrate.ts` las aplica en orden y registra cada una en `schema_migrations`.

## Consecuencias

- Front y back comparten lenguaje: los tipos y el cálculo de notas de `packages/core` se pueden reutilizar en la API en lugar de reescribirlos.
- Kysely obliga a declarar los tipos de cada tabla (`src/db.ts`); se agregan a medida que los módulos las usen.
- La conexión fija `time_zone = '+00:00'`; las fechas se convierten a `America/Bogota` solo al mostrar.
- Fuera de desarrollo la conexión a la base exige TLS (`DB_SSL=true`); la configuración falla al arrancar si no.
