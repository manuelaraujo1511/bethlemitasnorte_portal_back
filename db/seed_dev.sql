-- =============================================================================
-- seed_dev.sql  |  SOLO DESARROLLO  |  requiere 0001_core.sql
-- Datos INVENTADOS que reflejan packages/core/src/mock/seed.ts.
--
-- ADVERTENCIAS
--  * No ejecutar en staging ni produccion. No contiene datos reales.
--  * Los usuarios llevan un hash FALSO ('$argon2id$DEV-PLACEHOLDER...'): no es un
--    hash valido, nadie puede iniciar sesion con el. Para probar el ingreso, el
--    backend debe generar hashes reales en local (nunca versionar credenciales).
--  * El documento del estudiante es un marcador ficticio, no un numero real.
--  * Re-ejecutable: usa INSERT IGNORE con ids fijos.
--  * Las fechas de eventos son relativas a la fecha UTC actual. Hora de Bogota =
--    UTC-5, por eso 8:00 locales se guardan como 13:00 UTC.
-- Ejecutar con: mysql ... NOMBRE_BD < seed_dev.sql
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- --------------------------- Usuarios (15) -----------------------------------
-- 1 admin externo de plataforma | 2-9 docentes | 10-13 coordinadores | 14 admin | 15 estudiante
SET @fake_hash = '$argon2id$DEV-PLACEHOLDER-NOT-A-REAL-HASH';

INSERT IGNORE INTO users (id, username, email, first_name, last_name, display_name, password_hash, status) VALUES
 (1,  'soporte.plataforma', 'soporte@ejemplo.test',  'Soporte',   'Plataforma',      'Soporte Plataforma (externo)', @fake_hash, 'active'),
 (2,  'luis.gomez',         'luis.gomez@ejemplo.test',      'Luis',     'Gómez',      'Luis Gómez',         @fake_hash, 'active'),
 (3,  'elena.vargas',       'elena.vargas@ejemplo.test',    'Elena',    'Vargas',     'Elena Vargas',       @fake_hash, 'active'),
 (4,  'sandra.mejia',       'sandra.mejia@ejemplo.test',    'Sandra',   'Mejía',      'Sandra Mejía',       @fake_hash, 'active'),
 (5,  'marta.rios',         'marta.rios@ejemplo.test',      'Marta',    'Ríos',       'Marta Ríos',         @fake_hash, 'active'),
 (6,  'carlos.nino',        'carlos.nino@ejemplo.test',     'Carlos',   'Niño',       'Carlos Niño',        @fake_hash, 'active'),
 (7,  'patricia.londono',   'patricia.londono@ejemplo.test','Patricia', 'Londoño',    'Patricia Londoño',   @fake_hash, 'active'),
 (8,  'andres.cano',        'andres.cano@ejemplo.test',     'Andrés',   'Cano',       'Andrés Cano',        @fake_hash, 'active'),
 (9,  'daniel.pardo',       'daniel.pardo@ejemplo.test',    'Daniel',   'Pardo',      'Daniel Pardo',       @fake_hash, 'active'),
 (10, 'rosa.quintero',      'rosa.quintero@ejemplo.test',   'Rosa Elena','Quintero',  'Rosa Elena Quintero',@fake_hash, 'active'),
 (11, 'beatriz.camacho',    'beatriz.camacho@ejemplo.test', 'Beatriz',  'Camacho',    'Beatriz Camacho',    @fake_hash, 'active'),
 (12, 'jorge.salazar',      'jorge.salazar@ejemplo.test',   'Jorge Iván','Salazar',   'Jorge Iván Salazar', @fake_hash, 'active'),
 (13, 'lucia.herrera',      'lucia.herrera@ejemplo.test',   'Lucía',    'Herrera',    'Lucía Herrera',      @fake_hash, 'active'),
 (14, 'olga.marin',         'olga.marin@ejemplo.test',      'Olga',     'Marín',      'Olga Marín',         @fake_hash, 'active'),
 (15, 'ana.torres',         'ana.torres@ejemplo.test',      'Ana',      'Torres Ruiz','Ana Torres Ruiz',    @fake_hash, 'active');

-- --------------------------- Colegio, anio, periodos -------------------------
INSERT IGNORE INTO schools (id, code, name, city, department, created_by_user_id)
VALUES (1, 'demo', 'Colegio Demo Campus', 'Bogotá', 'Bogotá D.C.', 1);

INSERT IGNORE INTO academic_years (id, school_id, year, name, starts_on, ends_on, status, created_by_user_id)
VALUES (1, 1, 2026, 'Año lectivo 2026', '2026-01-19', '2026-11-27', 'active', 14);

INSERT IGNORE INTO periods (id, academic_year_id, number, kind, name, starts_on, ends_on) VALUES
 (1, 1, 1, 'regular', 'Período 1', '2026-01-19', '2026-05-01'),
 (2, 1, 2, 'regular', 'Período 2', '2026-05-04', '2026-08-14'),
 (3, 1, 3, 'regular', 'Período 3', '2026-08-17', '2026-11-20'),
 (4, 1, 4, 'final',   'Definitivo','2026-11-23', '2026-11-27');

-- --------------------------- Roles ------------------------------------------
-- Rosa Elena Quintero tiene DOS roles (coordinadora academica + administradora
-- del colegio) para demostrar que una persona puede acumular roles.
INSERT IGNORE INTO user_roles (id, user_id, school_id, role, coordinator_type, granted_by_user_id) VALUES
 (1,  1,  NULL, 'platform_admin', NULL, 1),
 (2,  2,  1, 'teacher', NULL, 1), (3,  3,  1, 'teacher', NULL, 1), (4,  4,  1, 'teacher', NULL, 1),
 (5,  5,  1, 'teacher', NULL, 1), (6,  6,  1, 'teacher', NULL, 1), (7,  7,  1, 'teacher', NULL, 1),
 (8,  8,  1, 'teacher', NULL, 1), (9,  9,  1, 'teacher', NULL, 1),
 (10, 10, 1, 'coordinator', 'academica',   1),
 (11, 11, 1, 'coordinator', 'pastoral',    1),
 (12, 12, 1, 'coordinator', 'convivencia', 1),
 (13, 13, 1, 'coordinator', 'orientacion', 1),
 (14, 10, 1, 'school_admin', NULL, 1),
 (15, 14, 1, 'school_admin', NULL, 1),
 (16, 15, 1, 'student', NULL, 14);

-- Personal: staff_id = user_id - 1 (docentes 1-8, coordinadores 9-12, admin 13).
INSERT IGNORE INTO staff_members (id, school_id, user_id, job_title, created_by_user_id) VALUES
 (1, 1, 2, 'Docente', 14),  (2, 1, 3, 'Docente', 14),  (3, 1, 4, 'Docente', 14),  (4, 1, 5, 'Docente', 14),
 (5, 1, 6, 'Docente', 14),  (6, 1, 7, 'Docente', 14),  (7, 1, 8, 'Docente', 14),  (8, 1, 9, 'Docente', 14),
 (9, 1, 10, 'Coordinadora académica', 14), (10, 1, 11, 'Coordinadora de pastoral', 14),
 (11, 1, 12, 'Coordinador de convivencia escolar', 14), (12, 1, 13, 'Orientadora escolar', 14),
 (13, 1, 14, 'Administradora del colegio', 1);

-- --------------------------- Grados y grupos ---------------------------------
INSERT IGNORE INTO grade_levels (id, school_id, code, name, ordinal, education_level) VALUES
 (1, 1, '1', '1.º', 1, 'basica_primaria'), (2, 1, '2', '2.º', 2, 'basica_primaria'),
 (3, 1, '3', '3.º', 3, 'basica_primaria'), (4, 1, '4', '4.º', 4, 'basica_primaria'),
 (5, 1, '5', '5.º', 5, 'basica_primaria');

-- Grupos A y B por grado: id = 2*(grado-1)+1 (A) y +2 (B). 3.º B = id 6.
INSERT IGNORE INTO class_groups (id, school_id, academic_year_id, grade_level_id, section, shift) VALUES
 (1,1,1,1,'A','unica'),(2,1,1,1,'B','unica'),(3,1,1,2,'A','unica'),(4,1,1,2,'B','unica'),
 (5,1,1,3,'A','unica'),(6,1,1,3,'B','unica'),(7,1,1,4,'A','unica'),(8,1,1,4,'B','unica'),
 (9,1,1,5,'A','unica'),(10,1,1,5,'B','unica');

-- Director de 3.º B: Carlos Niño (staff 5).
UPDATE class_groups SET director_staff_id = 5 WHERE id = 6 AND director_staff_id IS NULL;

-- --------------------------- Materias ----------------------------------------
INSERT IGNORE INTO subjects (id, school_id, code, name, area) VALUES
 (1,1,'MAT','Matemáticas','Matemáticas'), (2,1,'LEN','Lenguaje','Humanidades'),
 (3,1,'ING','Inglés','Humanidades'),     (4,1,'CIE','Ciencias','Ciencias naturales'),
 (5,1,'SOC','Entorno social','Ciencias sociales'), (6,1,'REL','Religión','Educación religiosa'),
 (7,1,'ART','Artes','Educación artística'), (8,1,'EDF','Educación física','Educación física');

-- Plan de estudios: las 8 materias en los 5 grados. Pesos inventados (suman 100).
INSERT IGNORE INTO grade_level_subjects (grade_level_id, subject_id, weekly_hours, weight_pct)
SELECT g.id, s.id, w.hours, w.weight
FROM grade_levels g
JOIN subjects s ON s.school_id = g.school_id
JOIN (SELECT 'MAT' c, 5 hours, 15.00 weight UNION ALL SELECT 'LEN',5,15.00 UNION ALL SELECT 'ING',3,12.00
      UNION ALL SELECT 'CIE',3,12.00 UNION ALL SELECT 'SOC',3,12.00 UNION ALL SELECT 'REL',1,10.00
      UNION ALL SELECT 'ART',2,12.00 UNION ALL SELECT 'EDF',2,12.00) w ON w.c = s.code
WHERE g.school_id = 1;

-- Asignaciones de 3.º B (grupo 6): ids 1-8 = materia 1-8, docente = staff 1-8.
INSERT IGNORE INTO teaching_assignments (id, school_id, academic_year_id, class_group_id, subject_id, staff_id, created_by_user_id) VALUES
 (1,1,1,6,1,1,14),(2,1,1,6,2,2,14),(3,1,1,6,3,3,14),(4,1,1,6,4,4,14),
 (5,1,1,6,5,5,14),(6,1,1,6,6,6,14),(7,1,1,6,7,7,14),(8,1,1,6,8,8,14);

-- --------------------------- Estudiante y matricula --------------------------
-- document_number_enc / hash: marcadores FICTICIOS. En el backend real el numero
-- se cifra con AES-256-GCM y el hash es un HMAC con pepper; aqui no hay numero real.
INSERT IGNORE INTO students (id, school_id, user_id, student_code, document_type, document_number_enc, document_number_hash, birth_date, sex, created_by_user_id)
VALUES (1, 1, 15, 'DEV-0001', 'TI', UNHEX('00'), UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT', 256)), '2017-03-14', 'F', 14);

INSERT IGNORE INTO enrollments (id, school_id, student_id, academic_year_id, class_group_id, list_number, enrolled_on, transport_route, created_by_user_id)
VALUES (1, 1, 1, 1, 6, 7, '2026-01-12', 'Ruta 4', 14);

-- --------------------------- Tipos de evento (datos de referencia) -----------
-- En produccion los crea el backend al dar de alta un colegio.
INSERT IGNORE INTO event_types (id, school_id, code, label, category, sort_order, is_system) VALUES
 (1,1,'tarea','Tarea','task',1,1),               (2,1,'trabajo','Trabajo','task',2,1),
 (3,1,'quiz','Quiz','task',3,1),                 (4,1,'evaluacion','Evaluación','task',4,1),
 (5,1,'investigacion','Investigación','task',5,1),(6,1,'actividad','Actividad','task',6,1),
 (7,1,'clase_virtual','Clase virtual','task',7,1),(8,1,'pregunta','Pregunta','task',8,1),
 (9,1,'evento_institucional','Evento institucional','school',9,1),
 (10,1,'reunion_padres','Reunión de padres','school',10,1),
 (11,1,'receso','Receso','school',11,1),
 (12,1,'salida_pedagogica','Salida pedagógica','school',12,1);

-- --------------------------- Eventos -----------------------------------------
-- Tareas (starts_at = entrega). 13:00 UTC = 8:00 Bogota; 20:00 UTC = 15:00 Bogota.
INSERT IGNORE INTO events (id, school_id, academic_year_id, event_type_id, subject_id, period_id, title, description, starts_at, modality, status, published_at, created_as_role, created_by_user_id) VALUES
 (1,1,1,1,1,3,'Taller de fracciones','Resuelve los ejercicios 1 al 8 de la guía. Dibuja cada fracción.',
   TIMESTAMP(UTC_DATE(), '20:00:00'), 'presencial','published', UTC_TIMESTAMP(3) - INTERVAL 3 DAY,'teacher',2),
 (2,1,1,3,3,3,'Quiz de vocabulario: la casa','Repasa las palabras de la unidad 5. Se hace en el computador del colegio.',
   TIMESTAMP(UTC_DATE() + INTERVAL 1 DAY, '13:00:00'), 'virtual','published', UTC_TIMESTAMP(3) - INTERVAL 4 DAY,'teacher',4),
 (3,1,1,4,5,3,'Prueba de comprensión: los recursos naturales','Evaluación escrita sobre las lecturas de las últimas dos semanas.',
   TIMESTAMP(UTC_DATE() + INTERVAL 2 DAY, '13:00:00'), 'presencial','published', UTC_TIMESTAMP(3) - INTERVAL 6 DAY,'teacher',6),
 (4,1,1,6,4,3,'Laboratorio 3: cambios de la materia','Trae un recipiente transparente y una cucharada de sal.',
   TIMESTAMP(UTC_DATE() + INTERVAL 4 DAY, '16:00:00'), 'presencial','published', UTC_TIMESTAMP(3) - INTERVAL 2 DAY,'teacher',5);

-- Eventos del colegio (all_day: 05:00 UTC = 00:00 Bogota).
INSERT IGNORE INTO events (id, school_id, academic_year_id, event_type_id, period_id, title, description, starts_at, ends_at, all_day, status, published_at, created_as_role, created_by_user_id) VALUES
 (5,1,1,9,3,'Muestra de ciencias','Los estudiantes presentan sus carteleras y laboratorios a las familias.',
   TIMESTAMP(UTC_DATE() + INTERVAL 3 DAY, '13:00:00'), TIMESTAMP(UTC_DATE() + INTERVAL 3 DAY, '17:30:00'), 0,'published', UTC_TIMESTAMP(3),'coordinator',10),
 (6,1,1,10,3,'Reunión de padres de familia','Entrega de informes del período.',
   TIMESTAMP(UTC_DATE() + INTERVAL 8 DAY, '23:00:00'), TIMESTAMP(UTC_DATE() + INTERVAL 9 DAY, '00:30:00'), 0,'published', UTC_TIMESTAMP(3),'school_admin',14),
 (7,1,1,11,3,'Receso escolar','Descanso a mitad del período.',
   TIMESTAMP(UTC_DATE() + INTERVAL 15 DAY, '05:00:00'), TIMESTAMP(UTC_DATE() + INTERVAL 19 DAY, '05:00:00'), 1,'published', UTC_TIMESTAMP(3),'school_admin',14),
 (8,1,1,12,NULL,'Salida pedagógica al parque','Traer ropa cómoda, gorra y botella de agua.',
   TIMESTAMP(UTC_DATE() + INTERVAL 6 DAY, '13:00:00'), TIMESTAMP(UTC_DATE() + INTERVAL 6 DAY, '19:00:00'), 0,'published', UTC_TIMESTAMP(3),'teacher',6);

-- Publico objetivo: tareas -> materia x grupo (3.º B); institucionales -> colegio;
-- la salida pedagogica -> todo el grado 3.º.
INSERT IGNORE INTO event_audiences (id, event_id, scope_type, grade_level_id, class_group_id, teaching_assignment_id) VALUES
 (1, 1, 'subject_group', NULL, NULL, 1),
 (2, 2, 'subject_group', NULL, NULL, 3),
 (3, 3, 'subject_group', NULL, NULL, 5),
 (4, 4, 'subject_group', NULL, NULL, 4),
 (5, 5, 'school',        NULL, NULL, NULL),
 (6, 6, 'school',        NULL, NULL, NULL),
 (7, 7, 'school',        NULL, NULL, NULL),
 (8, 8, 'grade_level',   3,    NULL, NULL);
