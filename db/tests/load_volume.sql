-- =============================================================================
-- tests/load_volume.sql  |  SOLO EN UNA BASE DESCARTABLE
-- Carga un volumen parecido a un colegio grande para medir con EXPLAIN ANALYZE las
-- consultas de tests/explain.sql. Requiere 0001-0004, seed_dev.sql y
-- seed_dev_academic.sql. Datos inventados (nombres "Estudiante N", "Docente N").
--
-- Volumen (un anio lectivo):
--   44 grupos (11 grados x 4), 1 540 estudiantes (35 por grupo), 60 docentes,
--   352 asignaciones (8 materias por grupo), ~21 000 eventos con su audiencia,
--   ~42 000 actividades y ~1,5 millones de notas de actividad,
--   ~60 000 mensajes y ~330 000 destinatarios, ~3 000 PQRS, ~230 000 asistencias.
-- Tarda unos minutos. Los ids empiezan en 1000 para no chocar con los seeds.
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';
SET SESSION cte_max_recursion_depth = 2000000;

DROP TABLE IF EXISTS tmp_seq;
CREATE TABLE tmp_seq (n INT UNSIGNED PRIMARY KEY);
INSERT INTO tmp_seq (n)
WITH RECURSIVE s(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM s WHERE n < 100000)
SELECT n FROM s;

-- Grados 6 a 11 (los seeds ya traen 1 a 5) y 4 grupos por grado, ids 1001-1044.
INSERT IGNORE INTO grade_levels (id, school_id, code, name, ordinal, education_level)
SELECT 1000 + n, 1, CAST(n + 5 AS CHAR), CONCAT(n + 5, '.º'), n + 5,
       IF(n + 5 <= 9, 'basica_secundaria', 'media')
FROM tmp_seq WHERE n <= 6;

INSERT IGNORE INTO class_groups (id, school_id, academic_year_id, grade_level_id, section, shift)
SELECT 1000 + n, 1, 1,
       CASE WHEN (n - 1) DIV 4 < 5 THEN (n - 1) DIV 4 + 1 ELSE 1000 + (n - 1) DIV 4 - 4 END,
       CONCAT('V', ELT((n - 1) % 4 + 1, 'A', 'B', 'C', 'D')), 'unica'
FROM tmp_seq WHERE n <= 44;

-- 60 docentes (usuarios 1001-1060, personal 1001-1060).
INSERT IGNORE INTO users (id, username, first_name, last_name, display_name, password_hash, status)
SELECT 1000 + n, CONCAT('docente.', n), 'Docente', CAST(n AS CHAR), CONCAT('Docente ', n),
       '$argon2id$DEV-PLACEHOLDER-NOT-A-REAL-HASH', 'active'
FROM tmp_seq WHERE n <= 60;
INSERT IGNORE INTO user_roles (user_id, school_id, role, granted_by_user_id)
SELECT 1000 + n, 1, 'teacher', 14 FROM tmp_seq WHERE n <= 60;
INSERT IGNORE INTO staff_members (id, school_id, user_id, job_title, created_by_user_id)
SELECT 1000 + n, 1, 1000 + n, 'Docente', 14 FROM tmp_seq WHERE n <= 60;

-- 1 540 estudiantes (usuarios 2001-3540, estudiantes y matriculas 1001-2540).
INSERT IGNORE INTO users (id, username, first_name, last_name, display_name, password_hash, status)
SELECT 2000 + n, CONCAT('demo.', LPAD(n, 6, '0')), 'Estudiante', CAST(n AS CHAR), CONCAT('Estudiante ', n),
       '$argon2id$DEV-PLACEHOLDER-NOT-A-REAL-HASH', 'active'
FROM tmp_seq WHERE n <= 1540;
INSERT IGNORE INTO user_roles (user_id, school_id, role, granted_by_user_id)
SELECT 2000 + n, 1, 'student', 14 FROM tmp_seq WHERE n <= 1540;
INSERT IGNORE INTO students (id, school_id, user_id, student_code, created_by_user_id)
SELECT 1000 + n, 1, 2000 + n, LPAD(n, 6, '0'), 14 FROM tmp_seq WHERE n <= 1540;
INSERT IGNORE INTO enrollments (id, school_id, student_id, academic_year_id, class_group_id, list_number, enrolled_on, created_by_user_id)
SELECT 1000 + n, 1, 1000 + n, 1, 1000 + (n - 1) DIV 35 + 1, (n - 1) % 35 + 1, '2026-01-12', 14
FROM tmp_seq WHERE n <= 1540;

-- Asignaciones titulares: 8 materias por grupo; docente rotando entre los 60.
INSERT IGNORE INTO teaching_assignments (id, school_id, academic_year_id, class_group_id, subject_id, staff_id, created_by_user_id)
SELECT 1000 + (g.n - 1) * 8 + s.n, 1, 1, 1000 + g.n, s.n, 1000 + ((g.n - 1) * 8 + s.n - 1) % 60 + 1, 14
FROM tmp_seq g JOIN tmp_seq s ON s.n <= 8
WHERE g.n <= 44;

-- Eventos: 20 tareas por asignacion y periodo (3 periodos) = 21 120, audiencia materia x grupo.
INSERT IGNORE INTO events (id, school_id, academic_year_id, event_type_id, subject_id, period_id, title, starts_at, status, published_at, created_as_role, created_by_user_id)
SELECT 10000 + (ta.id - 1001) * 60 + (p.id - 1) * 20 + k.n,
       1, 1, (k.n % 6) + 1, ta.subject_id, p.id, CONCAT('Tarea ', k.n),
       TIMESTAMP(p.starts_on + INTERVAL (k.n * 4) DAY, '20:00:00'),
       'published', TIMESTAMP(p.starts_on, '12:00:00'), 'teacher', st.user_id
FROM teaching_assignments ta
JOIN staff_members st ON st.id = ta.staff_id
JOIN periods p ON p.academic_year_id = 1 AND p.kind = 'regular'
JOIN tmp_seq k ON k.n <= 20
WHERE ta.id BETWEEN 1001 AND 1352;

INSERT IGNORE INTO event_audiences (event_id, scope_type, teaching_assignment_id)
SELECT e.id, 'subject_group', 1001 + (e.id - 10000 - 1) DIV 60
FROM events e WHERE e.id >= 10000;

-- 100 eventos de colegio y 200 por grado.
INSERT IGNORE INTO events (id, school_id, academic_year_id, event_type_id, period_id, title, starts_at, status, published_at, created_as_role, created_by_user_id)
SELECT 40000 + n, 1, 1, 9 + n % 4, NULL, CONCAT('Evento ', n),
       TIMESTAMP('2026-01-20' + INTERVAL (n * 3) % 300 DAY, '13:00:00'), 'published', '2026-01-15 12:00:00', 'school_admin', 14
FROM tmp_seq WHERE n <= 300;
INSERT IGNORE INTO event_audiences (event_id, scope_type, grade_level_id)
SELECT 40000 + n, IF(n <= 100, 'school', 'grade_level'), IF(n <= 100, NULL, 1001 + n % 6)
FROM tmp_seq WHERE n <= 300;

-- Calificacion: 4 categorias por asignacion y periodo (25 % c/u), 10 actividades por
-- categoria (40 por asignacion y periodo), nota para cada estudiante del grupo.
INSERT IGNORE INTO grading_categories (id, teaching_assignment_id, period_id, name, weight_pct, position)
SELECT 10000 + (ta.id - 1001) * 12 + (p.id - 1) * 4 + c.n, ta.id, p.id, CONCAT('Categoría ', c.n), 25, c.n
FROM teaching_assignments ta
JOIN periods p ON p.academic_year_id = 1 AND p.kind = 'regular'
JOIN tmp_seq c ON c.n <= 4
WHERE ta.id BETWEEN 1001 AND 1352;

INSERT IGNORE INTO grading_activities (id, category_id, title, position)
SELECT 100000 + (gc.id - 10000 - 1) * 10 + a.n, gc.id, CONCAT('Actividad ', a.n), a.n
FROM grading_categories gc JOIN tmp_seq a ON a.n <= 10
WHERE gc.id > 10000;

INSERT IGNORE INTO activity_scores (activity_id, enrollment_id, score)
SELECT ga.id, e.id, 30 + (ga.id * 7 + e.id * 13) % 21
FROM grading_activities ga
JOIN grading_categories gc ON gc.id = ga.category_id
JOIN teaching_assignments ta ON ta.id = gc.teaching_assignment_id
JOIN enrollments e ON e.class_group_id = ta.class_group_id
WHERE ga.id > 100000;

-- Correo: 60 000 mensajes de docentes; cada uno a 5 estudiantes de su grupo y, 1 de
-- cada 10, a todo el grupo (35). Un tercio sin leer.
INSERT IGNORE INTO messages (id, school_id, sender_user_id, subject, body, sent_at)
SELECT 10000 + n, 1, 1000 + (n % 60) + 1, CONCAT('Mensaje ', n), 'Texto de prueba.',
       TIMESTAMP('2026-01-20' + INTERVAL n % 280 DAY, '14:00:00') + INTERVAL n % 3600 SECOND
FROM tmp_seq WHERE n <= 60000;

INSERT IGNORE INTO message_recipients (message_id, recipient_user_id, folder, read_at, sent_at)
SELECT m.id, 2000 + ((m.id * 37 + r.n * 35) % 1540) + 1, 'inbox',
       IF((m.id + r.n) % 3 = 0, NULL, m.sent_at + INTERVAL 1 HOUR), m.sent_at
FROM messages m JOIN tmp_seq r ON r.n <= IF(m.id % 10 = 0, 35, 5)
WHERE m.id > 10000;

-- PQRS: 2 por estudiante, estados variados.
INSERT IGNORE INTO pqrs_tickets (id, school_id, ticket_number, kind, status, requester_user_id, student_id, subject, body, response_body, responded_at, created_at)
SELECT 1000 + n, 1, CONCAT('2026-', LPAD(1000 + n, 6, '0')),
       ELT(n % 5 + 1, 'peticion', 'queja', 'reclamo', 'sugerencia', 'felicitacion'),
       ELT(n % 4 + 1, 'received', 'in_review', 'answered', 'closed'),
       2000 + (n - 1) % 1540 + 1, 1000 + (n - 1) % 1540 + 1, CONCAT('PQRS ', n), 'Texto de prueba.',
       IF(n % 4 + 1 = 3, 'Respuesta.', NULL), IF(n % 4 + 1 = 3, '2026-06-01 15:00:00', NULL),
       TIMESTAMP('2026-01-20' + INTERVAL n % 280 DAY, '15:00:00')
FROM tmp_seq WHERE n <= 3080;

-- Asistencia del dia: 150 dias lectivos para cada estudiante.
INSERT IGNORE INTO attendance_records (enrollment_id, attendance_date, status, recorded_by_user_id)
SELECT e.id, '2026-01-19' + INTERVAL d.n DAY,
       ELT(IF((e.id + d.n) % 17 = 0, 2, IF((e.id + d.n) % 23 = 0, 3, 1)), 'presente', 'ausente', 'tarde'), 14
FROM enrollments e JOIN tmp_seq d ON d.n <= 150
WHERE e.id > 1000;

DROP TABLE tmp_seq;

ANALYZE TABLE events, event_audiences, enrollments, teaching_assignments, grading_categories,
              grading_activities, activity_scores, messages, message_recipients, pqrs_tickets,
              attendance_records, period_grades;
