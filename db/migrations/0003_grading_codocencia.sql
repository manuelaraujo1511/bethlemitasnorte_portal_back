-- =============================================================================
-- 0003_grading_codocencia.sql  |  FASE 2b  |  MySQL 8.0.16+ / InnoDB / utf8mb4
-- Cambios acordados con el dueno el 2026-10-27 (docs/database-design.md, sec. 9):
--   1. Dominio propio por colegio (school_domains).
--   2. Co-docencia: titular + reemplazos con vigencia (teaching_assignments) y
--      marca "en reemplazo de" en los mensajes (messages.on_behalf_of_staff_id).
--   3. Calificacion en escala 10 a 50 (enteros): categorias con porcentaje y
--      actividades con nota (grading_categories, grading_activities, activity_scores).
--   4. Escala 10 a 50 en period_grades, grade_scales y autoevaluacion; la
--      autoevaluacion sin enviar queda en 36 (source='default').
--   5. Carga de descriptores (grade_scales) y pesos de periodo 30/40/30 para los
--      colegios y periodos que ya existen.
-- Requiere 0001 y 0002. Se ejecuta una sola vez: las sentencias ALTER estan dentro
-- de un procedimiento que se salta si '0003_grading_codocencia' ya esta registrada.
-- Las tablas nuevas usan CREATE TABLE IF NOT EXISTS. En una base con notas ya
-- guardadas, los valores 1,0-5,0 se convierten a 10-50 (x10).
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- ============================ DOMINIO POR COLEGIO ============================

CREATE TABLE IF NOT EXISTS school_domains (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id  BIGINT UNSIGNED NOT NULL,
  host       VARCHAR(190)    NOT NULL COMMENT 'Nombre de host en minusculas, ej. portal.colegio.edu.co',
  is_primary TINYINT(1)      NOT NULL DEFAULT 0,
  status     ENUM('active','disabled') NOT NULL DEFAULT 'active',
  created_at DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_school_domains_host (host),
  KEY ix_school_domains_school (school_id),
  CONSTRAINT fk_school_domains__school FOREIGN KEY (school_id) REFERENCES schools (id),
  -- La collation de la tabla no distingue mayusculas, por eso se compara con una que si.
  CONSTRAINT ck_school_domains_host CHECK (host COLLATE utf8mb4_0900_as_cs = LOWER(host) AND host NOT LIKE '% %')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Dominio propio de cada colegio: el host resuelve el colegio al ingresar con codigo de estudiante';

-- ========================= TABLAS NUEVAS DE CALIFICACION ======================

-- Categoria de una materia en un periodo (Exploracion 5 %, Proyecto final 30 %...).
-- Los porcentajes de las categorias de una asignacion en un periodo deben sumar 100;
-- esa suma la valida la API (la base no puede expresar una suma entre filas).
-- kind='self_assessment': la nota sale de la autoevaluacion del estudiante y no tiene
-- actividades (a lo sumo una por asignacion y periodo).
CREATE TABLE IF NOT EXISTS grading_categories (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  teaching_assignment_id BIGINT UNSIGNED NOT NULL COMMENT 'Debe ser del titular (regla de la API)',
  period_id              BIGINT UNSIGNED NOT NULL,
  name                   VARCHAR(120)    NOT NULL,
  kind                   ENUM('regular','self_assessment') NOT NULL DEFAULT 'regular',
  weight_pct             TINYINT UNSIGNED NOT NULL COMMENT 'Entero 1 a 100',
  position               SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  deleted_at             DATETIME(3)     NULL,
  created_at             DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at             DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id     BIGINT UNSIGNED NULL,
  updated_by_user_id     BIGINT UNSIGNED NULL,
  sa_key TINYINT GENERATED ALWAYS AS (IF(kind = 'self_assessment' AND deleted_at IS NULL, 1, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_gc_name (teaching_assignment_id, period_id, name),
  UNIQUE KEY uq_gc_self_assessment (teaching_assignment_id, period_id, sa_key),
  KEY ix_gc_period (period_id),
  CONSTRAINT fk_gc__assignment FOREIGN KEY (teaching_assignment_id) REFERENCES teaching_assignments (id),
  CONSTRAINT fk_gc__period     FOREIGN KEY (period_id) REFERENCES periods (id),
  CONSTRAINT fk_gc__created    FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_gc__updated    FOREIGN KEY (updated_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_gc_weight CHECK (weight_pct BETWEEN 1 AND 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Categorias de calificacion por asignacion y periodo (porcentajes suman 100)';

CREATE TABLE IF NOT EXISTS grading_activities (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  category_id        BIGINT UNSIGNED NOT NULL,
  title              VARCHAR(160)    NOT NULL,
  activity_date      DATE            NULL COMMENT 'Fecha local del colegio',
  event_id           BIGINT UNSIGNED NULL COMMENT 'Tarea del calendario asociada, si existe',
  position           SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  deleted_at         DATETIME(3)     NULL,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  KEY ix_ga_category (category_id, position),
  KEY ix_ga_event (event_id),
  CONSTRAINT fk_ga__category FOREIGN KEY (category_id) REFERENCES grading_categories (id),
  CONSTRAINT fk_ga__event    FOREIGN KEY (event_id) REFERENCES events (id),
  CONSTRAINT fk_ga__created  FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_ga__updated  FOREIGN KEY (updated_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Actividades calificables de una categoria';

CREATE TABLE IF NOT EXISTS activity_scores (
  activity_id       BIGINT UNSIGNED NOT NULL,
  enrollment_id     BIGINT UNSIGNED NOT NULL,
  score             TINYINT UNSIGNED NOT NULL COMMENT 'Entero 10 a 50',
  graded_by_user_id BIGINT UNSIGNED NULL,
  created_at        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (activity_id, enrollment_id),
  KEY ix_as_enrollment (enrollment_id),
  CONSTRAINT fk_as__activity   FOREIGN KEY (activity_id) REFERENCES grading_activities (id),
  CONSTRAINT fk_as__enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments (id),
  CONSTRAINT fk_as__grader     FOREIGN KEY (graded_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_as_score CHECK (score BETWEEN 10 AND 50)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Nota de cada estudiante en cada actividad (escala 10 a 50)';

-- ================================ CAMBIOS (ALTER) =============================

DROP PROCEDURE IF EXISTS campus_migrate_0003;

DELIMITER $$
CREATE PROCEDURE campus_migrate_0003()
BEGIN
  IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '0003_grading_codocencia') THEN

    -- ---- Co-docencia en teaching_assignments -------------------------------
    -- Un titular activo por (grupo, materia); reemplazos ilimitados con vigencia.
    -- El reemplazo apunta a la asignacion del titular del MISMO grupo y materia
    -- (FK compuesta). Solo el titular califica (regla de la API).
    ALTER TABLE teaching_assignments
      ADD COLUMN role ENUM('titular','reemplazo') NOT NULL DEFAULT 'titular' AFTER staff_id,
      ADD COLUMN replaces_assignment_id BIGINT UNSIGNED NULL AFTER role,
      ADD COLUMN valid_from DATE NULL COMMENT 'Inicio de la vigencia (reemplazos)' AFTER replaces_assignment_id,
      ADD COLUMN valid_to   DATE NULL COMMENT 'Fin de la vigencia (reemplazos)' AFTER valid_from,
      ADD COLUMN titular_key TINYINT GENERATED ALWAYS AS
        (IF(role = 'titular' AND status = 'active' AND deleted_at IS NULL, 1, NULL)) STORED,
      ADD UNIQUE KEY uq_ta_titular (class_group_id, subject_id, titular_key),
      ADD UNIQUE KEY uq_ta_id_group_subject (id, class_group_id, subject_id),
      ADD CONSTRAINT ck_ta_role CHECK (
        (role = 'titular'  AND replaces_assignment_id IS NULL) OR
        (role = 'reemplazo' AND replaces_assignment_id IS NOT NULL)),
      ADD CONSTRAINT ck_ta_valid CHECK (valid_from IS NULL OR valid_to IS NULL OR valid_to >= valid_from);

    ALTER TABLE teaching_assignments
      ADD CONSTRAINT fk_ta__replaces FOREIGN KEY (replaces_assignment_id, class_group_id, subject_id)
        REFERENCES teaching_assignments (id, class_group_id, subject_id),
      DROP INDEX uq_ta_group_subject;

    ALTER TABLE teaching_assignments
      COMMENT = 'Asignacion academica: docente x materia x grupo (titular o reemplazo con vigencia)';

    -- ---- Marca "en reemplazo de" en mensajes --------------------------------
    -- Las respuestas del estudiante llegan al reemplazo y el titular las recibe como
    -- copia (message_recipients.recipient_kind = 'cc'): lo hace la API al enviar.
    ALTER TABLE messages
      ADD COLUMN on_behalf_of_staff_id BIGINT UNSIGNED NULL
        COMMENT 'Titular al que reemplaza el remitente: la interfaz muestra "en reemplazo de ..."'
        AFTER sender_user_id,
      ADD CONSTRAINT fk_messages__on_behalf FOREIGN KEY (on_behalf_of_staff_id, school_id)
        REFERENCES staff_members (id, school_id);

    -- ---- Escala 10 a 50 en period_grades ------------------------------------
    ALTER TABLE period_grades DROP CHECK ck_pg_score;
    ALTER TABLE period_grades MODIFY score DECIMAL(5,2) NOT NULL;
    UPDATE period_grades SET score = ROUND(score * 10);
    ALTER TABLE period_grades
      MODIFY score TINYINT UNSIGNED NOT NULL COMMENT 'Entero 10 a 50',
      ADD CONSTRAINT ck_pg_score CHECK (score BETWEEN 10 AND 50);

    -- ---- Escala 10 a 50 en grade_scales -------------------------------------
    ALTER TABLE grade_scales DROP CHECK ck_grade_scales_range;
    ALTER TABLE grade_scales MODIFY min_score DECIMAL(5,2) NOT NULL, MODIFY max_score DECIMAL(5,2) NOT NULL;
    UPDATE grade_scales SET min_score = ROUND(min_score * 10), max_score = ROUND(max_score * 10);
    ALTER TABLE grade_scales
      MODIFY min_score TINYINT UNSIGNED NOT NULL COMMENT 'Nota minima del rango, entero 10 a 50',
      MODIFY max_score TINYINT UNSIGNED NOT NULL COMMENT 'Nota maxima del rango, entero 10 a 50',
      ADD CONSTRAINT ck_grade_scales_range CHECK (min_score >= 10 AND max_score <= 50 AND min_score <= max_score);

    -- ---- Autoevaluacion: criterios y resultado en 10 a 50 --------------------
    ALTER TABLE self_assessment_scores DROP CHECK ck_sasc_score;
    UPDATE self_assessment_scores SET score = score * 10 WHERE score BETWEEN 1 AND 5;
    ALTER TABLE self_assessment_scores
      ADD CONSTRAINT ck_sasc_score CHECK (score BETWEEN 10 AND 50);

    ALTER TABLE self_assessment_submissions DROP CHECK ck_sas_avg;
    ALTER TABLE self_assessment_submissions MODIFY average DECIMAL(5,2) NOT NULL;
    UPDATE self_assessment_submissions SET average = ROUND(average * 10);
    ALTER TABLE self_assessment_submissions
      CHANGE average final_score TINYINT UNSIGNED NOT NULL
        COMMENT 'Nota de la categoria Autoevaluacion: suma de criterios / cantidad, redondeada (10 a 50); 36 si no se envio',
      ADD COLUMN source ENUM('submitted','default') NOT NULL DEFAULT 'submitted'
        COMMENT 'default = la ventana cerro sin envio y se asigno 36' AFTER final_score,
      ADD CONSTRAINT ck_sas_final CHECK (final_score BETWEEN 10 AND 50);

    -- ---- Plan de estudios: el peso por materia ya no entra en las notas -----
    ALTER TABLE grade_level_subjects
      MODIFY weight_pct DECIMAL(5,2) NULL
        COMMENT 'OBSOLETO desde 0003: no entra en ningun calculo de nota (los pesos son de las categorias)';

    INSERT IGNORE INTO schema_migrations (version) VALUES ('0003_grading_codocencia');
  END IF;
END$$
DELIMITER ;

CALL campus_migrate_0003();
DROP PROCEDURE campus_migrate_0003;

-- ===================== VALORES POR DEFECTO PARA LO EXISTENTE ==================

-- Descriptores (enteros 10 a 50): Bajo 10-35, Basico 36-43, Alto 44-46, Superior 47-50.
INSERT IGNORE INTO grade_scales (school_id, descriptor, min_score, max_score)
SELECT s.id, d.descriptor, d.min_score, d.max_score
FROM schools s
JOIN (
  SELECT 'bajo'     AS descriptor, 10 AS min_score, 35 AS max_score
  UNION ALL SELECT 'basico',   36, 43
  UNION ALL SELECT 'alto',     44, 46
  UNION ALL SELECT 'superior', 47, 50
) d;

-- Pesos de periodo en el Definitivo: 30 / 40 / 30 (periodo final sin peso).
INSERT IGNORE INTO period_weights (period_id, weight_pct)
SELECT p.id, CASE p.number WHEN 1 THEN 30 WHEN 2 THEN 40 WHEN 3 THEN 30 END
FROM periods p
WHERE p.kind = 'regular';
