# Base de datos de Campus

Esquema MySQL 8.0.16+ (InnoDB, utf8mb4, collation `utf8mb4_0900_ai_ci`). El diseño y sus razones están en [`docs/database-design.md`](https://github.com/manuelaraujo1511/bethlemitasnorte_portal/blob/main/docs/database-design.md) del repo del portal (las rutas `docs/...` y `campus/...` que aparecen en este directorio son de ese repo).

Desde la tarea B0.2 (2026-10-28) este directorio es la única fuente de las migraciones: se movió desde `backend/db/` del repo del portal, sin cambios en los `.sql`. Las migraciones nuevas solo se escriben aquí.

## Archivos

| Archivo | Fase | Contenido |
|---|---|---|
| `migrations/0001_core.sql` | 1 | Colegios, años, períodos, usuarios y roles, estudiantes, matrículas, grados, grupos, materias, asignaciones, eventos y audiencias, archivos, auditoría, sesiones |
| `migrations/0002_academic_extras.sql` | 2 | Notas y Definitivo, asistencia, observador, autoevaluación, correo, PQRSF, avisos, documentos, salud, consentimientos |
| `migrations/0003_grading_codocencia.sql` | 2b | Dominio por colegio, co-docencia (titular y reemplazo), escala 10 a 50, categorías y actividades de calificación, autoevaluación con valor por defecto 36, descriptores y pesos 30/40/30 |
| `migrations/0004_grading_views.sql` | 2b | Vistas de cálculo: `v_category_scores`, `v_period_scores` y `v_definitive_scores` (misma regla que `campus/packages/core/src/logic/grading.ts`) |
| `seed_dev.sql` | solo dev | Datos inventados que reflejan el mock; requiere solo `0001` |
| `seed_dev_academic.sql` | solo dev | Calificación del ejemplo del dueño (46 y 48), autoevaluación, notas de período, asistencia, observador, co-docencia, correo, PQRS y avisos; requiere `0001`–`0004` y `seed_dev.sql` |
| `seed_dev_school.sql` | solo dev | B1.1: dominios del colegio (`localhost`, `demo.campus.localhost`), 39 estudiantes más (3.º B con 30 y 3.º A con 10) y las 8 asignaciones de 3.º A; requiere los dos seeds anteriores |
| `tests/run.sh` + `tests/checks.sql` | pruebas | Base temporal, aplica todo dos veces y corre 46 comprobaciones (cálculo de notas y rechazos esperados) |
| `tests/load_volume.sql` + `tests/explain.sql` | rendimiento | Volumen de un colegio grande y `EXPLAIN ANALYZE` de las consultas clave (resultados en `docs/database-design.md` §10) |

## Cómo aplicar

Con el runner del backend (recomendado; ver el README raíz):

```bash
npm run db:migrate   # migraciones pendientes
npm run db:seed      # migraciones + los tres seeds de desarrollo (nunca en producción)
npm run db:test      # tests/run.sh: base temporal, todo dos veces y checks.sql
```

A mano, con el cliente `mysql`:

Las migraciones se aplican en orden numérico. Son re-ejecutables (`CREATE TABLE IF NOT EXISTS`, `INSERT IGNORE` en `schema_migrations`), pero **no** son un sistema de cambios: para modificar una tabla ya creada se escribe una migración nueva (`0005_...`), nunca se edita una aplicada.

```bash
# La contraseña va en la variable de entorno MYSQL_PWD (o en un archivo ~/.my.cnf con permisos 600).
# No la escriba en scripts ni en el repositorio.
mysql -h HOST -u USUARIO -e "CREATE DATABASE campus CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci"
mysql -h HOST -u USUARIO campus < db/migrations/0001_core.sql
mysql -h HOST -u USUARIO campus < db/migrations/0002_academic_extras.sql
mysql -h HOST -u USUARIO campus < db/migrations/0003_grading_codocencia.sql
mysql -h HOST -u USUARIO campus < db/migrations/0004_grading_views.sql
# Solo desarrollo, base local y descartable:
mysql -h HOST -u USUARIO campus < db/seed_dev.sql
mysql -h HOST -u USUARIO campus < db/seed_dev_academic.sql
mysql -h HOST -u USUARIO campus < db/seed_dev_school.sql
```

Requisitos del servidor y de la conexión:

- MySQL 8.0.16 o superior (los `CHECK` se aplican desde esa versión; las expresiones `DEFAULT (UUID())` desde 8.0.13).
- Zona horaria del servidor y de cada conexión en UTC (`default-time-zone='+00:00'`, o `SET time_zone='+00:00'` al abrir la conexión del pool). Los scripts ya lo fijan en su sesión. Si la aplicación escribe en otra zona, las fechas quedan corridas.
- Usuario de la aplicación sin `DROP`/`ALTER`/`CREATE`; un usuario aparte, de migraciones, con esos permisos. En producción, además, sin `UPDATE`/`DELETE` sobre `audit_log`.

## Pruebas

```bash
# Crea una base temporal campus_test_*, aplica migraciones y seeds dos veces, corre
# tests/checks.sql y borra la base. Con MySQL en Docker:
#   docker run -d --name camdb -e MYSQL_ROOT_PASSWORD=... -p 3306:3306 mysql:8.0.42
MYSQL="docker exec -i -e MYSQL_PWD camdb mysql -uroot" MYSQL_PWD=... db/tests/run.sh
# Con un cliente local: MYSQL_PWD=... db/tests/run.sh   (por defecto mysql -uroot -h127.0.0.1)
```

Para medir rendimiento, sobre una base descartable con migraciones y seeds: `tests/load_volume.sql` (≈1 minuto) y luego `tests/explain.sql`.

## Convenciones de nombres

- Tablas en plural y `snake_case`, en inglés. Columnas igual. Textos de comentarios en español.
- PK: `id BIGINT UNSIGNED AUTO_INCREMENT`. Entidades que la API expone llevan además `public_id CHAR(36)` (UUID); el `id` numérico no sale del servidor.
- FK: `<tabla>_id`. Restricciones con nombre: `fk_<tabla>__<detalle>`, `uq_<tabla>_<detalle>`, `ix_<tabla>_<detalle>`, `ck_<tabla>_<detalle>`.
- Fechas y horas: `DATETIME(3)` en UTC (`created_at`, `updated_at`, `deleted_at`). Fechas de calendario sin hora: `DATE`. La aplicación convierte a `America/Bogota` solo al mostrar.
- Auditoría de fila: `created_by_user_id` / `updated_by_user_id` en tablas de negocio; historial de cambios en `audit_log`.
- Borrado: `deleted_at` (borrado lógico) o `status` según la tabla. Los usuarios no se borran: se anonimizan (`anonymized_at`).
- Sets cerrados y estables (estados, rol, tipo de coordinación, categoría de mensaje) son `ENUM`. Lo que el colegio puede ampliar (tipos de evento) es una tabla (`event_types`).
- Datos sensibles: columnas terminadas en `_enc` (`VARBINARY`) se cifran en la aplicación; `_hash` es un HMAC para búsqueda.

## Reglas que conviene recordar

- `ON DELETE RESTRICT` por defecto. `CASCADE` solo en tablas hijas puras (adjuntos, audiencias, destinatarios, puntajes).
- MySQL no permite `CASCADE`/`SET NULL` en columnas que estén en un `CHECK` o en una columna generada; por eso esas FK son `RESTRICT`.
- Las FK compuestas `(id, school_id)` y `(id, academic_year_id, school_id)` evitan mezclar colegios o años entre tablas relacionadas.
- Unicidad con `NULL`: MySQL trata cada `NULL` como distinto; por eso hay columnas generadas (`school_key`, `coord_key`, `active_flag`, `target_key`, `ta_key`, `active_key`) para que el `UNIQUE` sí funcione.
- Validación: las migraciones se verificaron en MySQL 8.0.42 sobre una base temporal (ver informe en `docs/database-design.md`, sección de validación).
