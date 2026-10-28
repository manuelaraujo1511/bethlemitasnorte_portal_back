-- =============================================================================
-- seed_dev_academic.sql  |  SOLO DESARROLLO  |  requiere 0001-0004 y seed_dev.sql
-- Datos INVENTADOS para ejercitar las tablas de fase 2: calificacion (categorias,
-- actividades, notas), autoevaluacion, notas de periodo, asistencia, observador,
-- co-docencia con mensajes "en reemplazo de", correo, PQRS y avisos.
--
-- Todo gira alrededor de la estudiante de ejemplo (enrollment 1, 3.o B, grupo 6).
-- Matematicas (asignacion 1), periodo 3, reproduce el ejemplo confirmado por el
-- dueno (docs/database-design.md, sec. 9):
--   categorias 5 / 40 / 20 / 30 / 5 %; la de 40 % tiene 7 actividades
--   (48, 48, 34, 50, 50, 50, 40) -> 45,7 -> 46; periodo -> 47,9 -> 48 (Superior).
-- Las pruebas de tests/checks.sql verifican esos valores con las vistas de 0004.
--
-- Re-ejecutable: INSERT IGNORE con ids fijos. Sin datos reales.
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- --------------------------- Descriptores y pesos -----------------------------
-- 0003 carga estos valores solo para los colegios y periodos que ya existian al
-- aplicarla. seed_dev.sql se aplica despues, asi que aqui se cargan para el colegio
-- de ejemplo. En produccion los crea el alta de colegio y de anio lectivo (API).
INSERT IGNORE INTO grade_scales (school_id, descriptor, min_score, max_score) VALUES
 (1, 'bajo', 10, 35), (1, 'basico', 36, 43), (1, 'alto', 44, 46), (1, 'superior', 47, 50);

INSERT IGNORE INTO period_weights (period_id, weight_pct) VALUES (1, 30), (2, 40), (3, 30);

-- --------------------------- Co-docencia -------------------------------------
-- Elena Vargas (staff 2, titular de Lenguaje) reemplaza a Sandra Mejia (staff 3,
-- titular de Ingles, asignacion 3) durante un permiso. Solo envia mensajes; no califica.
INSERT IGNORE INTO teaching_assignments
  (id, school_id, academic_year_id, class_group_id, subject_id, staff_id, role, replaces_assignment_id, valid_from, valid_to, created_by_user_id)
VALUES (9, 1, 1, 6, 3, 2, 'reemplazo', 3, '2026-09-14', '2026-10-09', 14);

-- --------------------------- Notas de periodos anteriores --------------------
-- Matematicas: periodos 1 y 2 ya cerrados y publicados.
INSERT IGNORE INTO period_grades (id, enrollment_id, teaching_assignment_id, period_id, score, source, graded_by_user_id) VALUES
 (1, 1, 1, 1, 48, 'computed', 2),
 (2, 1, 1, 2, 50, 'computed', 2);

INSERT IGNORE INTO period_publications (class_group_id, period_id, published_by_user_id) VALUES
 (6, 1, 10), (6, 2, 10);

-- --------------------------- Calificacion del periodo 3 ----------------------
INSERT IGNORE INTO grading_categories (id, teaching_assignment_id, period_id, name, kind, weight_pct, position, created_by_user_id) VALUES
 (1, 1, 3, 'Exploración',      'regular',          5, 1, 2),
 (2, 1, 3, 'Desarrollo',       'regular',         40, 2, 2),
 (3, 1, 3, 'Evaluación',       'regular',         20, 3, 2),
 (4, 1, 3, 'Proyecto final',   'regular',         30, 4, 2),
 (5, 1, 3, 'Autoevaluación',   'self_assessment',  5, 5, 2),
 -- Ingles (titular Sandra, asignacion 3): incompleta a proposito (sin notas en
 -- "Proyecto"), para probar que el periodo no se calcula hasta tener todo.
 (6, 3, 3, 'Trabajo en clase', 'regular',         60, 1, 4),
 (7, 3, 3, 'Proyecto',         'regular',         35, 2, 4),
 (8, 3, 3, 'Autoevaluación',   'self_assessment',  5, 3, 4);

-- Actividad 2 enlaza la tarea "Taller de fracciones" del calendario (evento 1).
INSERT IGNORE INTO grading_activities (id, category_id, title, activity_date, event_id, position, created_by_user_id) VALUES
 (1,  1, 'Lluvia de ideas: fracciones en la cocina', '2026-08-20', NULL, 1, 2),
 (2,  2, 'Taller de fracciones',                     '2026-08-27', 1,    1, 2),
 (3,  2, 'Guía 2: fracciones equivalentes',          '2026-09-03', NULL, 2, 2),
 (4,  2, 'Ejercicios de suma',                       '2026-09-10', NULL, 3, 2),
 (5,  2, 'Ejercicios de resta',                      '2026-09-17', NULL, 4, 2),
 (6,  2, 'Problemas con dibujos',                    '2026-09-24', NULL, 5, 2),
 (7,  2, 'Juego de tarjetas',                        '2026-10-01', NULL, 6, 2),
 (8,  2, 'Guía 3: recta numérica',                   '2026-10-08', NULL, 7, 2),
 (9,  3, 'Prueba escrita del período',               '2026-10-15', NULL, 1, 2),
 (10, 4, 'Maqueta: la pizza de fracciones',          '2026-10-22', NULL, 1, 2),
 (11, 6, 'Diálogo en parejas',                       '2026-09-02', NULL, 1, 4),
 (12, 7, 'Mi casa en inglés',                        '2026-10-20', NULL, 1, 4);

INSERT IGNORE INTO activity_scores (activity_id, enrollment_id, score, graded_by_user_id) VALUES
 (1, 1, 50, 2),
 (2, 1, 48, 2), (3, 1, 48, 2), (4, 1, 34, 2), (5, 1, 50, 2), (6, 1, 50, 2), (7, 1, 50, 2), (8, 1, 40, 2),
 (9, 1, 49, 2),
 (10, 1, 49, 2),
 (11, 1, 44, 4);

-- --------------------------- Autoevaluacion ----------------------------------
INSERT IGNORE INTO self_assessment_criteria (id, school_id, academic_year_id, position, text) VALUES
 (1, 1, 1, 1, 'Llego a tiempo y con mis materiales.'),
 (2, 1, 1, 2, 'Entrego mis tareas en la fecha acordada.'),
 (3, 1, 1, 3, 'Participo y escucho a mis compañeros.'),
 (4, 1, 1, 4, 'Pregunto cuando no entiendo.'),
 (5, 1, 1, 5, 'Cuido mi puesto y los materiales del salón.'),
 (6, 1, 1, 6, 'Me esfuerzo por mejorar.');

-- Ventanas del periodo 3 (las abre administracion o coordinacion). Ya cerradas.
INSERT IGNORE INTO self_assessment_windows (id, teaching_assignment_id, period_id, opens_at, closes_at, created_by_user_id) VALUES
 (1, 1, 3, '2026-10-19 13:00:00', '2026-10-24 04:59:59', 10),
 (2, 3, 3, '2026-10-19 13:00:00', '2026-10-24 04:59:59', 10);

-- Matematicas: enviada, seis criterios en 50 -> 50.
-- Ingles: no se envio antes del cierre -> 36 por defecto (source='default', sin criterios).
INSERT IGNORE INTO self_assessment_submissions (id, window_id, enrollment_id, commitment, final_score, source, submitted_at) VALUES
 (1, 1, 1, 'Seguir practicando las fracciones con mi familia.', 50, 'submitted', '2026-10-21 22:10:00'),
 (2, 2, 1, NULL, 36, 'default', '2026-10-24 05:00:00');

INSERT IGNORE INTO self_assessment_scores (submission_id, criterion_id, score) VALUES
 (1, 1, 50), (1, 2, 50), (1, 3, 50), (1, 4, 50), (1, 5, 50), (1, 6, 50);

-- El resultado del periodo 3 de Matematicas se guarda como calculado (lo haria la
-- API o un trabajo al cerrar el periodo, leyendo v_period_scores).
INSERT IGNORE INTO period_grades (id, enrollment_id, teaching_assignment_id, period_id, score, source, graded_by_user_id) VALUES
 (3, 1, 1, 3, 48, 'computed', NULL);

-- --------------------------- Asistencia --------------------------------------
-- Sin asignacion = asistencia del dia (director de grupo); con asignacion = por clase.
INSERT IGNORE INTO attendance_records (id, enrollment_id, teaching_assignment_id, attendance_date, status, note, recorded_by_user_id) VALUES
 (1, 1, NULL, '2026-10-19', 'presente', NULL, 6),
 (2, 1, NULL, '2026-10-20', 'ausente',  NULL, 6),
 (3, 1, NULL, '2026-10-21', 'excusa',   'Cita médica (excusa entregada).', 6),
 (4, 1, 1,    '2026-10-22', 'tarde',    NULL, 2),
 (5, 1, NULL, '2026-10-22', 'presente', NULL, 6);

-- --------------------------- Observador --------------------------------------
INSERT IGNORE INTO observations (id, school_id, enrollment_id, author_user_id, author_label, kind, occurred_at, body, seen_at) VALUES
 (1, 1, 1, 6,  NULL, 'reconocimiento', '2026-09-30 15:00:00', 'Ayudó a organizar la muestra de ciencias del grupo.', '2026-09-30 22:00:00'),
 (2, 1, 1, 12, 'Coordinación de convivencia', 'convivencia', '2026-10-16 14:00:00', 'Observación de ejemplo para pruebas (texto inventado).', NULL);

-- --------------------------- Archivos ----------------------------------------
-- Solo metadatos; el archivo no existe. storage_key inventada.
INSERT IGNORE INTO files (id, school_id, storage_key, original_name, mime_type, size_bytes, purpose, scan_status, uploaded_by_user_id) VALUES
 (1, 1, 'dev/attachments/guia-fracciones.pdf', 'guia-fracciones.pdf', 'application/pdf', 182340, 'attachment', 'clean', 2),
 (2, 1, 'dev/notices/circular-receso.pdf',     'circular-receso.pdf', 'application/pdf',  90211, 'document',   'clean', 14);

-- --------------------------- Correo ------------------------------------------
-- 1: docente -> estudiante, con adjunto, sin leer.
-- 2: coordinacion -> todo el colegio (audience='colegio'), leido.
-- 3: reemplazo (Elena) -> estudiante, "en reemplazo de" Sandra (staff 3).
-- 4: respuesta de la estudiante al reemplazo, con copia a la titular (cc).
INSERT IGNORE INTO messages (id, school_id, sender_user_id, on_behalf_of_staff_id, parent_message_id, subject, body, category, audience, sent_at) VALUES
 (1, 1, 2,  NULL, NULL, 'Guía para el taller', 'Te dejo la guía del taller de fracciones.', 'mensaje', 'personal', '2026-10-26 14:00:00'),
 (2, 1, 10, NULL, NULL, 'Muestra de ciencias', 'Invitamos a las familias a la muestra de ciencias.', 'mensaje', 'colegio', '2026-10-25 13:00:00'),
 (3, 1, 3,  3,    NULL, 'Vocabulario de la unidad 5', 'Mientras regresa la profesora Sandra, repasen la lista de palabras.', 'mensaje', 'personal', '2026-09-21 15:00:00'),
 (4, 1, 15, NULL, 3,    'RE: Vocabulario de la unidad 5', 'Profe, ¿la lista es de la página 40?', 'mensaje', 'personal', '2026-09-21 23:00:00');

INSERT IGNORE INTO message_recipients (id, message_id, recipient_user_id, recipient_kind, folder, read_at, sent_at) VALUES
 (1, 1, 15, 'to', 'inbox', NULL,                  '2026-10-26 14:00:00'),
 (2, 2, 15, 'to', 'inbox', '2026-10-25 20:00:00', '2026-10-25 13:00:00'),
 (3, 3, 15, 'to', 'inbox', '2026-09-21 22:00:00', '2026-09-21 15:00:00'),
 (4, 4, 3,  'to', 'inbox', NULL,                  '2026-09-21 23:00:00'),
 (5, 4, 4,  'cc', 'inbox', NULL,                  '2026-09-21 23:00:00');

INSERT IGNORE INTO message_attachments (message_id, file_id) VALUES (1, 1);

-- --------------------------- PQRS --------------------------------------------
INSERT IGNORE INTO pqrs_tickets (id, school_id, ticket_number, kind, status, requester_user_id, student_id, handled_by_user_id, subject, body, response_body, responded_by_user_id, responded_at, due_at, created_at) VALUES
 (1, 1, '2026-000001', 'peticion', 'answered', 15, 1, 14, 'Horario de la biblioteca',
    '¿La biblioteca abre en la jornada de la tarde?', 'Sí, de 2:00 a 4:00 p. m. de lunes a jueves.', 14,
    '2026-10-14 16:00:00', '2026-10-27 22:00:00', '2026-10-13 15:00:00'),
 (2, 1, '2026-000002', 'sugerencia', 'received', 15, 1, NULL, 'Más juegos en el descanso',
    'Sería bueno tener balones para el descanso.', NULL, NULL, NULL, '2026-11-10 22:00:00', '2026-10-27 14:00:00');

INSERT IGNORE INTO pqrs_ticket_history (id, ticket_id, from_status, to_status, actor_user_id, note, created_at) VALUES
 (1, 1, NULL,        'received',  15, NULL, '2026-10-13 15:00:00'),
 (2, 1, 'received',  'in_review', 14, 'Asignada a administración.', '2026-10-13 18:00:00'),
 (3, 1, 'in_review', 'answered',  14, NULL, '2026-10-14 16:00:00'),
 (4, 2, NULL,        'received',  15, NULL, '2026-10-27 14:00:00');

-- --------------------------- Avisos ------------------------------------------
INSERT IGNORE INTO notices (id, school_id, title, body, grade_level_id, attachment_file_id, status, published_at, expires_at, created_by_user_id) VALUES
 (1, 1, 'Receso escolar', 'Recuerden que la próxima semana no hay clases.', NULL, 2, 'published', '2026-10-24 13:00:00', '2026-11-15 05:00:00', 14),
 (2, 1, 'Salida pedagógica de 3.º', 'Traer ropa cómoda y botella de agua.', 3, NULL, 'published', '2026-10-26 13:00:00', NULL, 6),
 (3, 1, 'Borrador sin publicar', 'No debe verse en el feed.', NULL, NULL, 'draft', NULL, NULL, 14);
