-- =============================================================================
-- 0001_core.sql  |  FASE 1 (nucleo)  |  MySQL 8.0.16+ / InnoDB / utf8mb4
-- Portal "Campus": colegios, anios lectivos, periodos, usuarios y roles,
-- estudiantes, matriculas, grados, grupos, materias, asignaciones docentes,
-- eventos con publico objetivo, archivos adjuntos y bitacora de auditoria.
--
-- Convenciones (detalle en backend/db/README.md):
--   * Tablas en plural, snake_case; PK `id` BIGINT UNSIGNED AUTO_INCREMENT.
--   * `public_id` (UUID) solo en entidades que la API expone; el `id` numerico
--     nunca sale al cliente.
--   * Fechas/horas en UTC, DATETIME(3). La conexion DEBE fijar time_zone='+00:00'.
--   * Borrado logico con `deleted_at` en entidades de negocio; `status` para
--     ciclos de vida (activo/inactivo/etc.). Nunca se borra un usuario: se
--     anonimiza (ver docs/database-design.md).
--   * ON DELETE RESTRICT por defecto; CASCADE solo en tablas hijas puras.
--     NOTA: MySQL prohibe CASCADE/SET NULL en columnas usadas en un CHECK o en
--     una columna generada, por eso esas FK son RESTRICT.
--   * Idempotente: CREATE TABLE IF NOT EXISTS + INSERT IGNORE en el registro.
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- -----------------------------------------------------------------------------
-- Control de migraciones
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
  version     VARCHAR(64)  NOT NULL COMMENT 'Nombre del archivo, ej. 0001_core',
  applied_at  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Migraciones aplicadas';

-- -----------------------------------------------------------------------------
-- users: identidad global de cualquier persona que entra al portal.
-- Sin school_id a proposito: una persona puede tener roles en varios colegios
-- (o ser administrador externo de la plataforma). El alcance vive en user_roles.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id            CHAR(36)        NOT NULL DEFAULT (UUID()),
  username             VARCHAR(80)     NOT NULL COMMENT 'Identificador de ingreso; nunca se reutiliza',
  email                VARCHAR(190)    NULL     COMMENT 'Opcional: menores pueden no tener correo',
  email_verified_at    DATETIME(3)     NULL,
  first_name           VARCHAR(80)     NOT NULL,
  last_name            VARCHAR(80)     NOT NULL,
  display_name         VARCHAR(160)    NOT NULL COMMENT 'Como se muestra en la interfaz',
  password_hash        VARCHAR(255)    NULL     COMMENT 'SOLO hash argon2id (o bcrypt); NULL mientras la cuenta esta invitada',
  password_changed_at  DATETIME(3)     NULL,
  must_change_password TINYINT(1)      NOT NULL DEFAULT 1,
  failed_login_count   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  locked_until         DATETIME(3)     NULL,
  last_login_at        DATETIME(3)     NULL,
  mfa_secret_enc       VARBINARY(255)  NULL     COMMENT 'Secreto TOTP cifrado por la aplicacion (opcional)',
  status               ENUM('invited','active','suspended','archived') NOT NULL DEFAULT 'invited',
  anonymized_at        DATETIME(3)     NULL     COMMENT 'Derecho de supresion: datos personales reemplazados',
  deleted_at           DATETIME(3)     NULL,
  created_at           DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at           DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id   BIGINT UNSIGNED NULL,
  updated_by_user_id   BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_public_id (public_id),
  UNIQUE KEY uq_users_username (username),
  UNIQUE KEY uq_users_email (email),
  KEY ix_users_name (last_name, first_name),
  CONSTRAINT fk_users__created_by FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_users__updated_by FOREIGN KEY (updated_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_users_active_has_password CHECK (status <> 'active' OR password_hash IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Cuentas de acceso (todas las personas)';

-- -----------------------------------------------------------------------------
-- schools: inquilino (tenant). Hoy hay un solo colegio; el esquema ya lo soporta.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schools (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id          CHAR(36)        NOT NULL DEFAULT (UUID()),
  code               VARCHAR(30)     NOT NULL COMMENT 'Slug corto unico, ej. demo',
  name               VARCHAR(160)    NOT NULL,
  legal_name         VARCHAR(200)    NULL,
  nit                VARCHAR(20)     NULL,
  dane_code          VARCHAR(20)     NULL,
  city               VARCHAR(80)     NULL,
  department         VARCHAR(80)     NULL,
  country_code       CHAR(2)         NOT NULL DEFAULT 'CO',
  timezone           VARCHAR(40)     NOT NULL DEFAULT 'America/Bogota' COMMENT 'Solo para mostrar; todo se guarda en UTC',
  status             ENUM('active','suspended','archived') NOT NULL DEFAULT 'active',
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_schools_public_id (public_id),
  UNIQUE KEY uq_schools_code (code),
  CONSTRAINT fk_schools__created_by FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_schools__updated_by FOREIGN KEY (updated_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Colegios (inquilinos)';

-- -----------------------------------------------------------------------------
-- user_roles: un usuario puede tener varios roles. school_id NULL = alcance de
-- plataforma (administrador externo). Revocar = poner revoked_at (se conserva
-- el historial). La unicidad solo aplica a filas activas (ver active_flag).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_roles (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id            BIGINT UNSIGNED NOT NULL,
  school_id          BIGINT UNSIGNED NULL     COMMENT 'NULL solo para platform_admin',
  role               ENUM('platform_admin','school_admin','coordinator','teacher','student') NOT NULL,
  coordinator_type   ENUM('academica','pastoral','convivencia','orientacion') NULL
                     COMMENT 'Obligatorio si role=coordinator; un coordinador de dos tipos = dos filas',
  granted_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  granted_by_user_id BIGINT UNSIGNED NULL,
  revoked_at         DATETIME(3)     NULL,
  revoked_by_user_id BIGINT UNSIGNED NULL,
  -- Columnas generadas para poder tener un UNIQUE que trate NULL como valor.
  school_key  BIGINT UNSIGNED GENERATED ALWAYS AS (IFNULL(school_id, 0)) STORED,
  coord_key   VARCHAR(12)     GENERATED ALWAYS AS (IFNULL(coordinator_type, '')) STORED,
  active_flag TINYINT         GENERATED ALWAYS AS (IF(revoked_at IS NULL, 1, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_user_roles_active (user_id, role, school_key, coord_key, active_flag),
  KEY ix_user_roles_school_role (school_id, role, active_flag),
  CONSTRAINT fk_user_roles__user    FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT fk_user_roles__school  FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_user_roles__granted FOREIGN KEY (granted_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_user_roles__revoked FOREIGN KEY (revoked_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_user_roles_scope CHECK (
    (role = 'platform_admin' AND school_id IS NULL) OR (role <> 'platform_admin' AND school_id IS NOT NULL)),
  CONSTRAINT ck_user_roles_coord CHECK (
    (role = 'coordinator' AND coordinator_type IS NOT NULL) OR (role <> 'coordinator' AND coordinator_type IS NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Roles de cada usuario con alcance (colegio) y tipo de coordinacion';

-- -----------------------------------------------------------------------------
-- files: metadatos de archivos. El binario vive en almacenamiento de objetos
-- privado (storage_key); la base solo guarda la referencia.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS files (
  id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id           CHAR(36)        NOT NULL DEFAULT (UUID()),
  school_id           BIGINT UNSIGNED NOT NULL,
  storage_key         VARCHAR(255)    NOT NULL COMMENT 'Clave en el almacenamiento privado (nunca una URL publica)',
  original_name       VARCHAR(255)    NOT NULL,
  mime_type           VARCHAR(120)    NOT NULL,
  size_bytes          BIGINT UNSIGNED NOT NULL,
  sha256              CHAR(64)        NULL,
  purpose             ENUM('attachment','photo','document','import') NOT NULL DEFAULT 'attachment',
  scan_status         ENUM('pending','clean','infected','skipped') NOT NULL DEFAULT 'pending',
  uploaded_by_user_id BIGINT UNSIGNED NOT NULL,
  created_at          DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  deleted_at          DATETIME(3)     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_files_public_id (public_id),
  UNIQUE KEY uq_files_storage_key (storage_key),
  KEY ix_files_school (school_id, purpose),
  CONSTRAINT fk_files__school   FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_files__uploader FOREIGN KEY (uploaded_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_files_size CHECK (size_bytes > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Metadatos de archivos adjuntos, fotos y documentos';

-- -----------------------------------------------------------------------------
-- staff_members: vinculo laboral de un usuario con un colegio (docentes,
-- coordinadores y administrativos). Los permisos salen de user_roles.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staff_members (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id          BIGINT UNSIGNED NOT NULL,
  user_id            BIGINT UNSIGNED NOT NULL,
  employee_code      VARCHAR(30)     NULL,
  job_title          VARCHAR(80)     NULL,
  photo_file_id      BIGINT UNSIGNED NULL,
  hired_on           DATE            NULL,
  status             ENUM('active','inactive') NOT NULL DEFAULT 'active',
  deleted_at         DATETIME(3)     NULL,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_staff_school_user (school_id, user_id),
  UNIQUE KEY uq_staff_id_school (id, school_id),
  UNIQUE KEY uq_staff_school_code (school_id, employee_code),
  KEY ix_staff_user (user_id),
  CONSTRAINT fk_staff__school  FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_staff__user    FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT fk_staff__photo   FOREIGN KEY (photo_file_id) REFERENCES files (id),
  CONSTRAINT fk_staff__created FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_staff__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Personal del colegio (docentes, coordinadores, administrativos)';

-- -----------------------------------------------------------------------------
-- grade_levels (Grados): 1.o ... 5.o. Catalogo por colegio, no por anio.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS grade_levels (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id          BIGINT UNSIGNED NOT NULL,
  code               VARCHAR(10)     NOT NULL COMMENT 'Ej. 3',
  name               VARCHAR(40)     NOT NULL COMMENT 'Ej. 3.º',
  ordinal            TINYINT UNSIGNED NOT NULL COMMENT 'Orden de progresion; sirve para promocion',
  education_level    ENUM('preescolar','basica_primaria','basica_secundaria','media') NOT NULL,
  status             ENUM('active','inactive') NOT NULL DEFAULT 'active',
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_grade_levels_code (school_id, code),
  UNIQUE KEY uq_grade_levels_ordinal (school_id, ordinal),
  UNIQUE KEY uq_grade_levels_id_school (id, school_id),
  CONSTRAINT fk_grade_levels__school  FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_grade_levels__created FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_grade_levels__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Grados escolares';

-- -----------------------------------------------------------------------------
-- academic_years: un solo anio "active" por colegio (active_key).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS academic_years (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id          BIGINT UNSIGNED NOT NULL,
  year               SMALLINT UNSIGNED NOT NULL,
  name               VARCHAR(40)     NOT NULL,
  starts_on          DATE            NOT NULL,
  ends_on            DATE            NOT NULL,
  status             ENUM('planned','active','closed') NOT NULL DEFAULT 'planned',
  active_key         TINYINT GENERATED ALWAYS AS (IF(status = 'active', 1, NULL)) STORED,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_academic_years_year (school_id, year),
  UNIQUE KEY uq_academic_years_one_active (school_id, active_key),
  UNIQUE KEY uq_academic_years_id_school (id, school_id),
  CONSTRAINT fk_academic_years__school  FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_academic_years__created FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_academic_years__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_academic_years_dates CHECK (ends_on > starts_on)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Anios lectivos';

-- -----------------------------------------------------------------------------
-- periods: periodos 1..3 (regular) y el Definitivo (kind=final, numero 4).
-- Para un colegio con 4 periodos se cambia el CHECK en una migracion nueva.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS periods (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  academic_year_id BIGINT UNSIGNED NOT NULL,
  number           TINYINT UNSIGNED NOT NULL,
  kind             ENUM('regular','final') NOT NULL DEFAULT 'regular',
  name             VARCHAR(40)     NOT NULL COMMENT 'Ej. Período 1, Definitivo',
  starts_on        DATE            NOT NULL,
  ends_on          DATE            NOT NULL,
  created_at       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_periods_number (academic_year_id, number),
  CONSTRAINT fk_periods__year FOREIGN KEY (academic_year_id) REFERENCES academic_years (id),
  CONSTRAINT ck_periods_kind CHECK (
    (kind = 'regular' AND number BETWEEN 1 AND 3) OR (kind = 'final' AND number = 4)),
  CONSTRAINT ck_periods_dates CHECK (ends_on >= starts_on)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Periodos academicos y Definitivo';

-- -----------------------------------------------------------------------------
-- class_groups (Grupos/secciones): 3.o B en 2026. Pertenece a UN anio y UN grado.
-- director_staff_id = director de grupo (maximo uno por grupo, por diseno).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS class_groups (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id          BIGINT UNSIGNED NOT NULL,
  academic_year_id   BIGINT UNSIGNED NOT NULL,
  grade_level_id     BIGINT UNSIGNED NOT NULL,
  section            VARCHAR(5)      NOT NULL COMMENT 'A, B, C...',
  shift              ENUM('manana','tarde','unica') NOT NULL DEFAULT 'unica',
  capacity           SMALLINT UNSIGNED NULL,
  classroom          VARCHAR(40)     NULL,
  director_staff_id  BIGINT UNSIGNED NULL,
  status             ENUM('active','inactive') NOT NULL DEFAULT 'active',
  deleted_at         DATETIME(3)     NULL,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_class_groups_section (academic_year_id, grade_level_id, section),
  UNIQUE KEY uq_class_groups_id_year_school (id, academic_year_id, school_id),
  UNIQUE KEY uq_class_groups_id_school (id, school_id),
  KEY ix_class_groups_grade (grade_level_id, academic_year_id),
  KEY ix_class_groups_director (director_staff_id),
  CONSTRAINT fk_class_groups__year     FOREIGN KEY (academic_year_id, school_id) REFERENCES academic_years (id, school_id),
  CONSTRAINT fk_class_groups__grade    FOREIGN KEY (grade_level_id, school_id) REFERENCES grade_levels (id, school_id),
  CONSTRAINT fk_class_groups__director FOREIGN KEY (director_staff_id, school_id) REFERENCES staff_members (id, school_id),
  CONSTRAINT fk_class_groups__created  FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_class_groups__updated  FOREIGN KEY (updated_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Grupos o secciones por anio (ej. 3.º B 2026)';

-- -----------------------------------------------------------------------------
-- subjects (Materias). kind=behavior permite modelar "Comportamiento" como una
-- materia mas (sin docente propio: lo califica el director de grupo).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subjects (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id          BIGINT UNSIGNED NOT NULL,
  code               VARCHAR(20)     NOT NULL,
  name               VARCHAR(100)    NOT NULL,
  area               VARCHAR(80)     NULL COMMENT 'Area de conocimiento (agrupa materias en el boletin)',
  kind               ENUM('academic','behavior') NOT NULL DEFAULT 'academic',
  status             ENUM('active','inactive') NOT NULL DEFAULT 'active',
  deleted_at         DATETIME(3)     NULL,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_subjects_code (school_id, code),
  UNIQUE KEY uq_subjects_name (school_id, name),
  UNIQUE KEY uq_subjects_id_school (id, school_id),
  CONSTRAINT fk_subjects__school  FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_subjects__created FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_subjects__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Materias';

-- Plan de estudios: que materias tiene cada grado, con intensidad y peso.
CREATE TABLE IF NOT EXISTS grade_level_subjects (
  grade_level_id BIGINT UNSIGNED NOT NULL,
  subject_id     BIGINT UNSIGNED NOT NULL,
  weekly_hours   TINYINT UNSIGNED NULL,
  weight_pct     DECIMAL(5,2)    NULL COMMENT 'Peso en el Definitivo/boletin (la suma por grado deberia ser 100)',
  created_at     DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (grade_level_id, subject_id),
  KEY ix_gls_subject (subject_id),
  CONSTRAINT fk_gls__grade   FOREIGN KEY (grade_level_id) REFERENCES grade_levels (id),
  CONSTRAINT fk_gls__subject FOREIGN KEY (subject_id) REFERENCES subjects (id),
  CONSTRAINT ck_gls_weight CHECK (weight_pct IS NULL OR (weight_pct >= 0 AND weight_pct <= 100))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Plan de estudios: materias por grado';

-- -----------------------------------------------------------------------------
-- students: perfil del estudiante (1:1 con users). Contiene DATOS SENSIBLES de
-- un menor: documento cifrado (+ hash HMAC para buscar sin descifrar).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS students (
  id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id            CHAR(36)        NOT NULL DEFAULT (UUID()),
  school_id            BIGINT UNSIGNED NOT NULL,
  user_id              BIGINT UNSIGNED NOT NULL,
  student_code         VARCHAR(30)     NULL COMMENT 'Codigo interno del colegio',
  document_type        ENUM('RC','TI','CC','CE','PEP','PPT','NUIP','OTRO') NULL,
  document_number_enc  VARBINARY(255)  NULL COMMENT 'SENSIBLE: cifrado por la aplicacion (AES-256-GCM); nunca en claro',
  document_number_hash BINARY(32)      NULL COMMENT 'HMAC-SHA256 con pepper para busqueda/unicidad sin descifrar',
  birth_date           DATE            NULL COMMENT 'SENSIBLE (menor)',
  sex                  ENUM('F','M','X') NULL,
  photo_file_id        BIGINT UNSIGNED NULL COMMENT 'SENSIBLE: foto de un menor; solo URL firmada de corta vida',
  status               ENUM('active','withdrawn','graduated','archived') NOT NULL DEFAULT 'active',
  deleted_at           DATETIME(3)     NULL,
  created_at           DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at           DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id   BIGINT UNSIGNED NULL COMMENT 'Administrador que matriculo',
  updated_by_user_id   BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_students_public_id (public_id),
  UNIQUE KEY uq_students_user (user_id),
  UNIQUE KEY uq_students_document (school_id, document_type, document_number_hash),
  UNIQUE KEY uq_students_code (school_id, student_code),
  UNIQUE KEY uq_students_id_school (id, school_id),
  CONSTRAINT fk_students__school  FOREIGN KEY (school_id) REFERENCES schools (id),
  CONSTRAINT fk_students__user    FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT fk_students__photo   FOREIGN KEY (photo_file_id) REFERENCES files (id),
  CONSTRAINT fk_students__created FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_students__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Estudiantes (datos personales sensibles de menores)';

-- -----------------------------------------------------------------------------
-- enrollments: UNA matricula por estudiante por anio (uq_enrollments_student_year)
-- => un estudiante esta en UN solo grado/grupo por anio. Si se retira y vuelve en
-- el mismo anio se reactiva/mueve la misma fila (el historial queda en audit_log).
-- La FK compuesta garantiza que el grupo pertenece al mismo anio y colegio.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS enrollments (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id          BIGINT UNSIGNED NOT NULL,
  student_id         BIGINT UNSIGNED NOT NULL,
  academic_year_id   BIGINT UNSIGNED NOT NULL,
  class_group_id     BIGINT UNSIGNED NOT NULL,
  list_number        SMALLINT UNSIGNED NULL COMMENT 'Numero de lista en el grupo',
  status             ENUM('active','withdrawn','transferred','graduated') NOT NULL DEFAULT 'active',
  enrolled_on        DATE            NOT NULL,
  ended_on           DATE            NULL,
  end_reason         VARCHAR(200)    NULL,
  transport_route    VARCHAR(40)     NULL,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NULL COMMENT 'Administrador que matriculo (obligatorio por regla de negocio)',
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_enrollments_student_year (student_id, academic_year_id),
  UNIQUE KEY uq_enrollments_list_number (class_group_id, list_number),
  KEY ix_enrollments_group_status (class_group_id, status),
  KEY ix_enrollments_year (academic_year_id, status),
  CONSTRAINT fk_enrollments__student FOREIGN KEY (student_id, school_id) REFERENCES students (id, school_id),
  CONSTRAINT fk_enrollments__year    FOREIGN KEY (academic_year_id) REFERENCES academic_years (id),
  CONSTRAINT fk_enrollments__group   FOREIGN KEY (class_group_id, academic_year_id, school_id)
                                     REFERENCES class_groups (id, academic_year_id, school_id),
  CONSTRAINT fk_enrollments__created FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_enrollments__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_enrollments_ended CHECK (status IN ('active','graduated') OR ended_on IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Matriculas: un estudiante, un grupo, por anio';

-- -----------------------------------------------------------------------------
-- teaching_assignments: docente x materia x grupo (el grupo ya trae el anio).
-- Un docente pertenece a uno o varios grupos a traves de estas filas.
-- Un solo docente por (grupo, materia); si luego hay co-docencia, se relaja el UNIQUE.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS teaching_assignments (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id          BIGINT UNSIGNED NOT NULL,
  academic_year_id   BIGINT UNSIGNED NOT NULL,
  class_group_id     BIGINT UNSIGNED NOT NULL,
  subject_id         BIGINT UNSIGNED NOT NULL,
  staff_id           BIGINT UNSIGNED NOT NULL,
  weekly_hours       TINYINT UNSIGNED NULL,
  status             ENUM('active','ended') NOT NULL DEFAULT 'active',
  deleted_at         DATETIME(3)     NULL,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_ta_group_subject (class_group_id, subject_id),
  UNIQUE KEY uq_ta_id_school (id, school_id),
  KEY ix_ta_staff_year (staff_id, academic_year_id, class_group_id),
  KEY ix_ta_subject (subject_id),
  KEY ix_ta_year (academic_year_id),
  CONSTRAINT fk_ta__group   FOREIGN KEY (class_group_id, academic_year_id, school_id)
                            REFERENCES class_groups (id, academic_year_id, school_id),
  CONSTRAINT fk_ta__subject FOREIGN KEY (subject_id, school_id) REFERENCES subjects (id, school_id),
  CONSTRAINT fk_ta__staff   FOREIGN KEY (staff_id, school_id) REFERENCES staff_members (id, school_id),
  CONSTRAINT fk_ta__created FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_ta__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Asignacion academica: docente x materia x grupo';

-- -----------------------------------------------------------------------------
-- event_types: tabla de apoyo (no ENUM) porque el colegio puede agregar tipos.
-- category: 'task' = actividad evaluable de una materia; 'school' = evento institucional.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS event_types (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  school_id   BIGINT UNSIGNED NOT NULL,
  code        VARCHAR(40)     NOT NULL COMMENT 'Estable para el codigo: tarea, quiz, clase_virtual...',
  label       VARCHAR(80)     NOT NULL,
  category    ENUM('task','school') NOT NULL,
  color       CHAR(7)         NULL COMMENT 'Hex #RRGGBB opcional',
  sort_order  SMALLINT        NOT NULL DEFAULT 0,
  is_system   TINYINT(1)      NOT NULL DEFAULT 0 COMMENT '1 = tipo base que no se puede borrar',
  is_active   TINYINT(1)      NOT NULL DEFAULT 1,
  created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uq_event_types_code (school_id, code),
  UNIQUE KEY uq_event_types_id_school (id, school_id),
  CONSTRAINT fk_event_types__school FOREIGN KEY (school_id) REFERENCES schools (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Tipos de evento (tarea, quiz, reunion de padres, receso...)';

-- -----------------------------------------------------------------------------
-- events: calendario. Para tipos 'task', starts_at = fecha/hora de ENTREGA y
-- published_at = "Publicado". Para eventos institucionales, starts_at/ends_at
-- son el inicio y fin. Quien lo ve se define en event_audiences.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS events (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id          CHAR(36)        NOT NULL DEFAULT (UUID()),
  school_id          BIGINT UNSIGNED NOT NULL,
  academic_year_id   BIGINT UNSIGNED NOT NULL,
  event_type_id      BIGINT UNSIGNED NOT NULL,
  subject_id         BIGINT UNSIGNED NULL     COMMENT 'Materia, para tareas; NULL en eventos del colegio',
  period_id          BIGINT UNSIGNED NULL,
  title              VARCHAR(200)    NOT NULL,
  description        TEXT            NULL,
  starts_at          DATETIME(3)     NOT NULL COMMENT 'UTC. Tareas: entrega',
  ends_at            DATETIME(3)     NULL,
  all_day            TINYINT(1)      NOT NULL DEFAULT 0,
  modality           ENUM('presencial','virtual') NULL,
  virtual_url        VARCHAR(500)    NULL,
  status             ENUM('draft','published','cancelled') NOT NULL DEFAULT 'draft',
  published_at       DATETIME(3)     NULL,
  created_as_role    ENUM('school_admin','coordinator','teacher','platform_admin') NOT NULL
                     COMMENT 'Rol con el que actuo el autor (un usuario puede tener varios)',
  deleted_at         DATETIME(3)     NULL,
  created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  created_by_user_id BIGINT UNSIGNED NOT NULL,
  updated_by_user_id BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_events_public_id (public_id),
  KEY ix_events_feed (school_id, academic_year_id, status, starts_at),
  KEY ix_events_author (created_by_user_id, starts_at),
  KEY ix_events_subject (subject_id, starts_at),
  KEY ix_events_period (period_id),
  KEY ix_events_type (event_type_id),
  CONSTRAINT fk_events__year    FOREIGN KEY (academic_year_id, school_id) REFERENCES academic_years (id, school_id),
  CONSTRAINT fk_events__type    FOREIGN KEY (event_type_id, school_id) REFERENCES event_types (id, school_id),
  CONSTRAINT fk_events__subject FOREIGN KEY (subject_id, school_id) REFERENCES subjects (id, school_id),
  CONSTRAINT fk_events__period  FOREIGN KEY (period_id) REFERENCES periods (id),
  CONSTRAINT fk_events__created FOREIGN KEY (created_by_user_id) REFERENCES users (id),
  CONSTRAINT fk_events__updated FOREIGN KEY (updated_by_user_id) REFERENCES users (id),
  CONSTRAINT ck_events_dates CHECK (ends_at IS NULL OR ends_at >= starts_at),
  CONSTRAINT ck_events_published CHECK (status <> 'published' OR published_at IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Eventos del calendario (tareas y eventos del colegio)';

-- -----------------------------------------------------------------------------
-- event_audiences: publico objetivo. Un evento puede tener varias filas
-- (ej. 3.º A y 3.º B). scope_type decide que columna debe venir llena.
--   school        -> todo el colegio del evento
--   grade_level   -> todos los grupos de un grado
--   class_group   -> un grupo
--   subject_group -> estudiantes de una asignacion (materia x grupo)
-- FK en RESTRICT: estas columnas estan en CHECK/columna generada.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS event_audiences (
  id                     BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  event_id               BIGINT UNSIGNED NOT NULL,
  scope_type             ENUM('school','grade_level','class_group','subject_group') NOT NULL,
  grade_level_id         BIGINT UNSIGNED NULL,
  class_group_id         BIGINT UNSIGNED NULL,
  teaching_assignment_id BIGINT UNSIGNED NULL,
  target_key BIGINT UNSIGNED GENERATED ALWAYS AS
             (COALESCE(teaching_assignment_id, class_group_id, grade_level_id, 0)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_event_audiences_target (event_id, scope_type, target_key),
  KEY ix_ea_scope (scope_type, event_id),
  KEY ix_ea_grade (grade_level_id, event_id),
  KEY ix_ea_group (class_group_id, event_id),
  KEY ix_ea_assignment (teaching_assignment_id, event_id),
  CONSTRAINT fk_ea__event      FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE,
  CONSTRAINT fk_ea__grade      FOREIGN KEY (grade_level_id) REFERENCES grade_levels (id),
  CONSTRAINT fk_ea__group      FOREIGN KEY (class_group_id) REFERENCES class_groups (id),
  CONSTRAINT fk_ea__assignment FOREIGN KEY (teaching_assignment_id) REFERENCES teaching_assignments (id),
  CONSTRAINT ck_ea_scope CHECK (
       (scope_type = 'school'        AND grade_level_id IS NULL     AND class_group_id IS NULL     AND teaching_assignment_id IS NULL)
    OR (scope_type = 'grade_level'   AND grade_level_id IS NOT NULL AND class_group_id IS NULL     AND teaching_assignment_id IS NULL)
    OR (scope_type = 'class_group'   AND grade_level_id IS NULL     AND class_group_id IS NOT NULL AND teaching_assignment_id IS NULL)
    OR (scope_type = 'subject_group' AND grade_level_id IS NULL     AND class_group_id IS NULL     AND teaching_assignment_id IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Publico objetivo de cada evento (colegio/grado/grupo/materia-grupo)';

CREATE TABLE IF NOT EXISTS event_attachments (
  event_id   BIGINT UNSIGNED NOT NULL,
  file_id    BIGINT UNSIGNED NOT NULL,
  position   TINYINT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (event_id, file_id),
  KEY ix_event_attachments_file (file_id),
  CONSTRAINT fk_event_attachments__event FOREIGN KEY (event_id) REFERENCES events (id) ON DELETE CASCADE,
  CONSTRAINT fk_event_attachments__file  FOREIGN KEY (file_id) REFERENCES files (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Adjuntos de un evento';

-- -----------------------------------------------------------------------------
-- audit_log: solo se inserta (append-only). Sin FK a proposito: debe sobrevivir
-- a cualquier borrado y no frenar escrituras. En produccion: particionar por mes
-- y revocar UPDATE/DELETE al usuario de la aplicacion.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  occurred_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  school_id     BIGINT UNSIGNED NULL,
  actor_user_id BIGINT UNSIGNED NULL     COMMENT 'NULL = sistema',
  actor_role    VARCHAR(30)     NULL     COMMENT 'Rol con el que actuo',
  action        VARCHAR(60)     NOT NULL COMMENT 'Ej. enrollment.create, student.read_sensitive, login.failed',
  entity_type   VARCHAR(40)     NULL,
  entity_id     BIGINT UNSIGNED NULL,
  changes_json  JSON            NULL     COMMENT 'Antes/despues SIN valores sensibles en claro',
  ip_address    VARBINARY(16)   NULL,
  user_agent    VARCHAR(255)    NULL,
  request_id    CHAR(36)        NULL,
  PRIMARY KEY (id),
  KEY ix_audit_entity (entity_type, entity_id, occurred_at),
  KEY ix_audit_actor (actor_user_id, occurred_at),
  KEY ix_audit_school (school_id, occurred_at),
  KEY ix_audit_action (action, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Bitacora de auditoria (append-only)';

-- -----------------------------------------------------------------------------
-- Autenticacion: sesiones (refresh tokens) y tokens de un solo uso.
-- Solo se guarda el hash del token, nunca el token.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auth_sessions (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id      BIGINT UNSIGNED NOT NULL,
  token_hash   BINARY(32)      NOT NULL COMMENT 'SHA-256 del refresh token',
  created_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  last_used_at DATETIME(3)     NULL,
  expires_at   DATETIME(3)     NOT NULL,
  revoked_at   DATETIME(3)     NULL,
  ip_address   VARBINARY(16)   NULL,
  user_agent   VARCHAR(255)    NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_auth_sessions_token (token_hash),
  KEY ix_auth_sessions_user (user_id, revoked_at, expires_at),
  CONSTRAINT fk_auth_sessions__user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Sesiones activas';

CREATE TABLE IF NOT EXISTS auth_tokens (
  id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id    BIGINT UNSIGNED NOT NULL,
  purpose    ENUM('invite','password_reset','email_verify') NOT NULL,
  token_hash BINARY(32)      NOT NULL,
  created_at DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  expires_at DATETIME(3)     NOT NULL,
  used_at    DATETIME(3)     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_auth_tokens_hash (token_hash),
  KEY ix_auth_tokens_user (user_id, purpose),
  CONSTRAINT fk_auth_tokens__user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
  COMMENT='Invitacion de cuenta, recuperacion de clave, verificacion de correo';

INSERT IGNORE INTO schema_migrations (version) VALUES ('0001_core');
