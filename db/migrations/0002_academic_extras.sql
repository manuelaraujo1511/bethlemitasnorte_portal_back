-- =============================================================================
-- 0002_academic_extras.sql  |  FASE 2  |  MySQL 8.0.16+ / InnoDB / utf8mb4
-- Notas y Definitivo, asistencia, observador, autoevaluacion, correo, PQRSF
-- (tickets), avisos, documentos, salud y consentimientos.
-- Requiere 0001_core.sql. Mismas convenciones que la fase 1.
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- ============================ NOTAS Y DEFINITIVO =============================

-- Escala de desempeno (descriptores). Escala numerica 1,00 a 5,00.
CREATE TABLE IF NOT EXISTS grade_scales (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id  BIGINT UNSIGNED NOT NULL,
  descriptor ENUM('bajo','basico','alto','superior') NOT NULL,
  min_score  DECIMAL(3,2)    NOT NULL,
  max_score  DECIMAL(3,2)    NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_grade_scales_descriptor (school_id, descriptor),
  CONSTRAINT fk_grade_scales__school FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT ck_grade_scales_range CHECK (min_score >= 1.00 AND max_score <= 5.00 AND min_score <= max_score)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Rangos de nota por descriptor (los valores exactos los define el SIEE)';

-- Entradas del calculo del Definitivo: peso de cada periodo regular (suma 100).
-- El peso de cada materia esta en grade_level_subjects.weight_pct.
CREATE TABLE IF NOT EXISTS period_weights (
  period_id  BIGINT UNSIGNED NOT NULL,
  weight_pct DECIMAL(5,2)    NOT NULL,
  PRIMARY KEY (period_id),
  CONSTRAINT fk_period_weights__period FOREIGN KEY (period_id) REFERENCES periods (id),
  CONSTRAINT ck_period_weights CHECK (weight_pct > 0 AND weight_pct <= 100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Peso de cada periodo en el Definitivo';

-- Nota por estudiante, asignacion y periodo. El periodo 4 (Definitivo) se guarda
-- con source=computed (calculado) u override (ajuste manual auditado).
-- "previous" del front se obtiene leyendo el periodo anterior.
CREATE TABLE IF NOT EXISTS period_grades (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  enrollment_id          BIGINT UNSIGNED NOT NULL,
  teaching_assignment_id BIGINT UNSIGNED NOT NULL,
  period_id              BIGINT UNSIGNED NOT NULL,
  score                  DECIMAL(3,2)    NOT NULL,
  source                 ENUM('teacher','computed','override') NOT NULL DEFAULT 'teacher',
  comment                VARCHAR(500)    NULL,
  graded_by_user_id      BIGINT UNSIGNED NULL,
  created_at             DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at             DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_period_grades (enrollment_id, teaching_assignment_id, period_id),
  KEY ix_period_grades_ta_period (teaching_assignment_id, period_id),
  KEY ix_period_grades_period (period_id),
  CONSTRAINT fk_pg__enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments (id),
  CONSTRAINT fk_pg__assignment FOREIGN KEY (teaching_assignment_id) REFERENCES teaching_assignments (id),
  CONSTRAINT fk_pg__period     FOREIGN KEY (period_id) REFERENCES periods (id),
  CONSTRAINT fk_pg__grader     FOREIGN KEY (graded_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_pg_score CHECK (score >= 1.00 AND score <= 5.00)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Notas por periodo (y Definitivo calculado)';

-- Publicacion de notas por grupo y periodo (campo "published" del informe).
CREATE TABLE IF NOT EXISTS period_publications (
  class_group_id      BIGINT UNSIGNED NOT NULL,
  period_id           BIGINT UNSIGNED NOT NULL,
  published_at        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  published_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (class_group_id, period_id),
  KEY ix_pp_period (period_id),
  CONSTRAINT fk_pp__group  FOREIGN KEY (class_group_id) REFERENCES class_groups (id),
  CONSTRAINT fk_pp__period FOREIGN KEY (period_id) REFERENCES periods (id),
  CONSTRAINT fk_pp__user   FOREIGN KEY (published_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Notas publicadas a estudiantes (por grupo y periodo)';

-- =============================== ASISTENCIA ==================================

-- Asistencia diaria (teaching_assignment_id NULL) o por clase (con asignacion).
CREATE TABLE IF NOT EXISTS attendance_records (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  enrollment_id          BIGINT UNSIGNED NOT NULL,
  teaching_assignment_id BIGINT UNSIGNED NULL,
  attendance_date        DATE            NOT NULL COMMENT 'Fecha local del colegio',
  status                 ENUM('presente','ausente','tarde','excusa') NOT NULL,
  note                   VARCHAR(300)    NULL,
  recorded_by_user_id    BIGINT UNSIGNED NOT NULL,
  created_at             DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at             DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  ta_key BIGINT UNSIGNED GENERATED ALWAYS AS (IFNULL(teaching_assignment_id, 0)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_attendance (enrollment_id, attendance_date, ta_key),
  KEY ix_attendance_ta_date (teaching_assignment_id, attendance_date),
  CONSTRAINT fk_att__enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments (id),
  CONSTRAINT fk_att__assignment FOREIGN KEY (teaching_assignment_id) REFERENCES teaching_assignments (id),
  CONSTRAINT fk_att__recorder   FOREIGN KEY (recorded_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Asistencia';

-- ================================ OBSERVADOR =================================

CREATE TABLE IF NOT EXISTS observations (
  id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id             BIGINT UNSIGNED NOT NULL,
  enrollment_id         BIGINT UNSIGNED NOT NULL,
  author_user_id        BIGINT UNSIGNED NOT NULL,
  author_label          VARCHAR(120)    NULL COMMENT 'Ej. Coordinacion de convivencia (cuando firma un cargo)',
  kind                  ENUM('reconocimiento','convivencia','academica') NOT NULL,
  occurred_at           DATETIME(3)     NOT NULL,
  body                  TEXT            NOT NULL COMMENT 'SENSIBLE: puede describir conducta de un menor',
  seen_at               DATETIME(3)     NULL COMMENT 'Visto por el estudiante',
  acknowledged_at       DATETIME(3)     NULL COMMENT 'Firma/acuse',
  acknowledged_by_user_id BIGINT UNSIGNED NULL,
  deleted_at            DATETIME(3)     NULL,
  created_at            DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at            DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_obs_enrollment (enrollment_id, occurred_at),
  KEY ix_obs_unseen (enrollment_id, seen_at),
  KEY ix_obs_author (author_user_id, occurred_at),
  CONSTRAINT fk_obs__school     FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_obs__enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments (id),
  CONSTRAINT fk_obs__author     FOREIGN KEY (author_user_id) REFERENCES users (id),
  CONSTRAINT fk_obs__ack        FOREIGN KEY (acknowledged_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Observador del estudiante';

-- ============================== AUTOEVALUACION ===============================

-- Criterios: una vez usados en una autoevaluacion no se editan; se desactivan
-- y se crea uno nuevo, para no reescribir el historial.
CREATE TABLE IF NOT EXISTS self_assessment_criteria (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id        BIGINT UNSIGNED NOT NULL,
  academic_year_id BIGINT UNSIGNED NOT NULL,
  position         TINYINT UNSIGNED NOT NULL,
  text             VARCHAR(300)    NOT NULL,
  is_active        TINYINT(1)      NOT NULL DEFAULT 1,
  created_at       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_sac_position (academic_year_id, position),
  CONSTRAINT fk_sac__school FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_sac__year   FOREIGN KEY (academic_year_id) REFERENCES academic_years (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Criterios de autoevaluacion del anio';

-- Ventana de apertura/cierre por asignacion y periodo.
CREATE TABLE IF NOT EXISTS self_assessment_windows (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  teaching_assignment_id BIGINT UNSIGNED NOT NULL,
  period_id              BIGINT UNSIGNED NOT NULL,
  opens_at               DATETIME(3)     NOT NULL,
  closes_at              DATETIME(3)     NOT NULL,
  created_by_user_id     BIGINT UNSIGNED NULL,
  created_at             DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_saw (teaching_assignment_id, period_id),
  KEY ix_saw_open (opens_at, closes_at),
  CONSTRAINT fk_saw__assignment FOREIGN KEY (teaching_assignment_id) REFERENCES teaching_assignments (id),
  CONSTRAINT fk_saw__period     FOREIGN KEY (period_id) REFERENCES periods (id),
  CONSTRAINT fk_saw__creator    FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_saw_dates CHECK (closes_at > opens_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Ventanas de autoevaluacion';

-- UNA entrega por estudiante y ventana (UNIQUE). Editable mientras la ventana
-- este abierta (regla de la aplicacion).
CREATE TABLE IF NOT EXISTS self_assessment_submissions (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  window_id     BIGINT UNSIGNED NOT NULL,
  enrollment_id BIGINT UNSIGNED NOT NULL,
  commitment    VARCHAR(500)    NULL,
  average       DECIMAL(3,2)    NOT NULL COMMENT 'Promedio calculado por la aplicacion al guardar',
  submitted_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_sas (window_id, enrollment_id),
  KEY ix_sas_enrollment (enrollment_id),
  CONSTRAINT fk_sas__window     FOREIGN KEY (window_id) REFERENCES self_assessment_windows (id),
  CONSTRAINT fk_sas__enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments (id),
  CONSTRAINT ck_sas_avg CHECK (average >= 1.00 AND average <= 5.00)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Autoevaluaciones enviadas';

CREATE TABLE IF NOT EXISTS self_assessment_scores (
  submission_id BIGINT UNSIGNED NOT NULL,
  criterion_id  BIGINT UNSIGNED NOT NULL,
  score         TINYINT UNSIGNED NOT NULL,
  PRIMARY KEY (submission_id, criterion_id),
  KEY ix_sasc_criterion (criterion_id),
  CONSTRAINT fk_sasc__submission FOREIGN KEY (submission_id) REFERENCES self_assessment_submissions (id) ON DELETE CASCADE,
  CONSTRAINT fk_sasc__criterion  FOREIGN KEY (criterion_id) REFERENCES self_assessment_criteria (id),
  CONSTRAINT ck_sasc_score CHECK (score BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Puntaje por criterio';

-- =================================== CORREO ==================================

-- messages guarda el contenido UNA vez; message_recipients tiene una fila por
-- destinatario (fan-out al enviar, tambien para audience='colegio') con su estado
-- de lectura y carpeta. "Enviados" sale de messages.sender_user_id. La bandeja
-- de salida/deshacer es del cliente y no se guarda. Las categorias peticion/
-- queja/reclamo/sugerencia/felicitacion dirigidas a la administracion NO van
-- aqui: son tickets (pqrs_tickets). 'felicitacion' entre docente y estudiante si.
CREATE TABLE IF NOT EXISTS messages (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id         CHAR(36)        NOT NULL DEFAULT (UUID()),
  school_id         BIGINT UNSIGNED NOT NULL,
  sender_user_id    BIGINT UNSIGNED NOT NULL,
  parent_message_id BIGINT UNSIGNED NULL COMMENT 'Responder: mensaje al que contesta',
  subject           VARCHAR(200)    NOT NULL,
  body              TEXT            NOT NULL COMMENT 'Texto plano o markdown; sanitizar al mostrar',
  category          ENUM('mensaje','felicitacion') NOT NULL DEFAULT 'mensaje',
  audience          ENUM('personal','colegio') NOT NULL DEFAULT 'personal',
  sent_at           DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  sender_folder     ENUM('sent','archive','trash') NOT NULL DEFAULT 'sent',
  PRIMARY KEY (id),
  UNIQUE KEY uq_messages_public_id (public_id),
  KEY ix_messages_sender (sender_user_id, sender_folder, sent_at),
  KEY ix_messages_parent (parent_message_id),
  KEY ix_messages_school (school_id, audience, sent_at),
  CONSTRAINT fk_messages__school FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_messages__sender FOREIGN KEY (sender_user_id) REFERENCES users (id),
  CONSTRAINT fk_messages__parent FOREIGN KEY (parent_message_id) REFERENCES messages (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Mensajes (correo interno)';

CREATE TABLE IF NOT EXISTS message_recipients (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  message_id        BIGINT UNSIGNED NOT NULL,
  recipient_user_id BIGINT UNSIGNED NOT NULL,
  recipient_kind    ENUM('to','cc') NOT NULL DEFAULT 'to',
  folder            ENUM('inbox','archive','trash') NOT NULL DEFAULT 'inbox',
  read_at           DATETIME(3)     NULL COMMENT 'NULL = no leido; el cliente marca/desmarca de forma explicita',
  sent_at           DATETIME(3)     NOT NULL COMMENT 'Copia de messages.sent_at para ordenar sin JOIN',
  PRIMARY KEY (id),
  UNIQUE KEY uq_mr_message_user (message_id, recipient_user_id),
  KEY ix_mr_inbox (recipient_user_id, folder, sent_at),
  KEY ix_mr_unread (recipient_user_id, folder, read_at),
  CONSTRAINT fk_mr__message   FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE,
  CONSTRAINT fk_mr__recipient FOREIGN KEY (recipient_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Destinatarios, carpeta y estado de lectura';

CREATE TABLE IF NOT EXISTS message_attachments (
  message_id BIGINT UNSIGNED NOT NULL,
  file_id    BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (message_id, file_id),
  KEY ix_message_attachments_file (file_id),
  CONSTRAINT fk_ma__message FOREIGN KEY (message_id) REFERENCES messages (id) ON DELETE CASCADE,
  CONSTRAINT fk_ma__file    FOREIGN KEY (file_id) REFERENCES files (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Adjuntos de mensajes';

-- ===================================== PQRS ==================================

CREATE TABLE IF NOT EXISTS pqrs_tickets (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id            CHAR(36)        NOT NULL DEFAULT (UUID()),
  school_id            BIGINT UNSIGNED NOT NULL,
  ticket_number        VARCHAR(20)     NOT NULL COMMENT 'Consecutivo legible por colegio, ej. 2026-000123',
  kind                 ENUM('peticion','queja','reclamo','sugerencia','felicitacion') NOT NULL,
  status               ENUM('received','in_review','answered','closed','withdrawn') NOT NULL DEFAULT 'received',
  requester_user_id    BIGINT UNSIGNED NOT NULL,
  student_id           BIGINT UNSIGNED NULL COMMENT 'Estudiante al que se refiere, si aplica',
  addressed_to_user_id BIGINT UNSIGNED NULL COMMENT 'Destinatario elegido por quien escribe',
  handled_by_user_id   BIGINT UNSIGNED NULL COMMENT 'Funcionario que atiende',
  subject              VARCHAR(200)    NOT NULL,
  body                 TEXT            NOT NULL,
  response_body        TEXT            NULL,
  responded_by_user_id BIGINT UNSIGNED NULL,
  responded_at         DATETIME(3)     NULL,
  due_at               DATETIME(3)     NULL COMMENT 'Fecha limite de respuesta (plazo interno)',
  closed_at            DATETIME(3)     NULL,
  created_at           DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at           DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_pqrs_public_id (public_id),
  UNIQUE KEY uq_pqrs_number (school_id, ticket_number),
  KEY ix_pqrs_inbox (school_id, status, created_at),
  KEY ix_pqrs_requester (requester_user_id, created_at),
  KEY ix_pqrs_handler (handled_by_user_id, status),
  KEY ix_pqrs_student (student_id),
  CONSTRAINT fk_pqrs__school    FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_pqrs__requester FOREIGN KEY (requester_user_id) REFERENCES users (id),
  CONSTRAINT fk_pqrs__student   FOREIGN KEY (student_id) REFERENCES students (id),
  CONSTRAINT fk_pqrs__to        FOREIGN KEY (addressed_to_user_id) REFERENCES users (id),
  CONSTRAINT fk_pqrs__handler   FOREIGN KEY (handled_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_pqrs__responder FOREIGN KEY (responded_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_pqrs_answered CHECK (status <> 'answered' OR (response_body IS NOT NULL AND responded_at IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='PQRSF como tickets';

CREATE TABLE IF NOT EXISTS pqrs_ticket_attachments (
  ticket_id BIGINT UNSIGNED NOT NULL,
  file_id   BIGINT UNSIGNED NOT NULL,
  side      ENUM('request','response') NOT NULL DEFAULT 'request',
  PRIMARY KEY (ticket_id, file_id),
  KEY ix_pta_file (file_id),
  CONSTRAINT fk_pta__ticket FOREIGN KEY (ticket_id) REFERENCES pqrs_tickets (id) ON DELETE CASCADE,
  CONSTRAINT fk_pta__file   FOREIGN KEY (file_id) REFERENCES files (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Adjuntos de tickets';

CREATE TABLE IF NOT EXISTS pqrs_ticket_history (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ticket_id     BIGINT UNSIGNED NOT NULL,
  from_status   VARCHAR(20)     NULL,
  to_status     VARCHAR(20)     NOT NULL,
  actor_user_id BIGINT UNSIGNED NULL,
  note          VARCHAR(500)    NULL,
  created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_pth_ticket (ticket_id, created_at),
  CONSTRAINT fk_pth__ticket FOREIGN KEY (ticket_id) REFERENCES pqrs_tickets (id) ON DELETE CASCADE,
  CONSTRAINT fk_pth__actor  FOREIGN KEY (actor_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Historial de estados del ticket';

-- ============================ AVISOS Y DOCUMENTOS ============================

-- Alcance: todo el colegio (ambos NULL), un grado o un grupo.
CREATE TABLE IF NOT EXISTS notices (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id          CHAR(36)        NOT NULL DEFAULT (UUID()),
  school_id          BIGINT UNSIGNED NOT NULL,
  title              VARCHAR(200)    NOT NULL,
  body               TEXT            NOT NULL,
  grade_level_id     BIGINT UNSIGNED NULL,
  class_group_id     BIGINT UNSIGNED NULL,
  attachment_file_id BIGINT UNSIGNED NULL,
  status             ENUM('draft','published','archived') NOT NULL DEFAULT 'draft',
  published_at       DATETIME(3)     NULL,
  expires_at         DATETIME(3)     NULL,
  deleted_at         DATETIME(3)     NULL,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NOT NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_notices_public_id (public_id),
  KEY ix_notices_feed (school_id, status, published_at),
  KEY ix_notices_grade (grade_level_id),
  KEY ix_notices_group (class_group_id),
  CONSTRAINT fk_notices__school  FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_notices__grade   FOREIGN KEY (grade_level_id) REFERENCES grade_levels (id),
  CONSTRAINT fk_notices__group   FOREIGN KEY (class_group_id) REFERENCES class_groups (id),
  CONSTRAINT fk_notices__file    FOREIGN KEY (attachment_file_id) REFERENCES files (id),
  CONSTRAINT fk_notices__created FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_notices__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_notices_scope CHECK (grade_level_id IS NULL OR class_group_id IS NULL),
  CONSTRAINT ck_notices_published CHECK (status <> 'published' OR published_at IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Avisos institucionales';

-- Descargas / documentos. area = etiqueta de la interfaz (Institucional, Mi grupo,
-- nombre de la materia); el alcance real lo dan grade_level/class_group/subject.
CREATE TABLE IF NOT EXISTS school_documents (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id          CHAR(36)        NOT NULL DEFAULT (UUID()),
  school_id          BIGINT UNSIGNED NOT NULL,
  academic_year_id   BIGINT UNSIGNED NULL,
  title              VARCHAR(200)    NOT NULL,
  description        VARCHAR(500)    NULL,
  area               VARCHAR(80)     NOT NULL DEFAULT 'Institucional',
  file_id            BIGINT UNSIGNED NOT NULL,
  grade_level_id     BIGINT UNSIGNED NULL,
  class_group_id     BIGINT UNSIGNED NULL,
  subject_id         BIGINT UNSIGNED NULL,
  status             ENUM('draft','published','archived') NOT NULL DEFAULT 'published',
  deleted_at         DATETIME(3)     NULL,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NOT NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_school_documents_public_id (public_id),
  KEY ix_docs_school (school_id, status, area),
  KEY ix_docs_group (class_group_id),
  KEY ix_docs_grade (grade_level_id),
  KEY ix_docs_subject (subject_id),
  KEY ix_docs_file (file_id),
  CONSTRAINT fk_docs__school  FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_docs__year    FOREIGN KEY (academic_year_id) REFERENCES academic_years (id),
  CONSTRAINT fk_docs__file    FOREIGN KEY (file_id) REFERENCES files (id),
  CONSTRAINT fk_docs__grade   FOREIGN KEY (grade_level_id) REFERENCES grade_levels (id),
  CONSTRAINT fk_docs__group   FOREIGN KEY (class_group_id) REFERENCES class_groups (id),
  CONSTRAINT fk_docs__subject FOREIGN KEY (subject_id) REFERENCES subjects (id),
  CONSTRAINT fk_docs__created FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_docs__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Documentos descargables';

-- =========================== SALUD Y CONSENTIMIENTOS =========================

-- SENSIBLE (Ley 1581 de 2012: datos de salud de menores). Los campos libres van
-- cifrados por la aplicacion; key_version permite rotar la llave.
CREATE TABLE IF NOT EXISTS student_health (
  student_id          BIGINT UNSIGNED NOT NULL,
  blood_type          ENUM('A+','A-','B+','B-','AB+','AB-','O+','O-') NULL,
  eps_name            VARCHAR(120)    NULL,
  allergies_enc       VARBINARY(2048) NULL,
  conditions_enc      VARBINARY(2048) NULL,
  medications_enc     VARBINARY(2048) NULL,
  emergency_notes_enc VARBINARY(2048) NULL,
  key_version         SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  updated_by_user_id  BIGINT UNSIGNED NULL,
  created_at          DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at          DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (student_id),
  CONSTRAINT fk_health__student FOREIGN KEY (student_id) REFERENCES students (id),
  CONSTRAINT fk_health__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Datos de salud del estudiante (sensibles)';

-- Autorizaciones de tratamiento de datos / uso de imagen dadas por el acudiente.
CREATE TABLE IF NOT EXISTS data_consents (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id        BIGINT UNSIGNED NOT NULL,
  student_id       BIGINT UNSIGNED NOT NULL,
  purpose          ENUM('tratamiento_datos','uso_imagen','salidas_pedagogicas') NOT NULL,
  policy_version   VARCHAR(20)     NOT NULL,
  granted_by_name  VARCHAR(160)    NOT NULL COMMENT 'Acudiente que autoriza',
  relationship     VARCHAR(40)     NULL,
  granted_at       DATETIME(3)     NOT NULL,
  revoked_at       DATETIME(3)     NULL,
  evidence_file_id BIGINT UNSIGNED NULL,
  created_at       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_consents_student (student_id, purpose),
  CONSTRAINT fk_consents__school   FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_consents__student  FOREIGN KEY (student_id) REFERENCES students (id),
  CONSTRAINT fk_consents__evidence FOREIGN KEY (evidence_file_id) REFERENCES files (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Consentimientos de tratamiento de datos de menores';

INSERT IGNORE INTO schema_migrations (version) VALUES ('0002_academic_extras');
