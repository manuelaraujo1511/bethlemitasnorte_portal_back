-- =============================================================================
-- tests/checks.sql  |  pruebas del esquema sobre una base DESCARTABLE
-- Requiere 0001-0005, seed_dev.sql y seed_dev_academic.sql. Lo ejecuta run.sh.
-- Cada prueba que falla detiene el script con SIGNAL y un mensaje "FALLA: ...".
-- Las pruebas negativas ejecutan SQL que la base debe rechazar (CHECK, UNIQUE, FK).
-- Algunas pruebas positivas insertan filas: no ejecutar sobre una base con datos.
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

DROP PROCEDURE IF EXISTS t_eq;
DROP PROCEDURE IF EXISTS t_rejects;

DELIMITER $$
-- Compara dos valores como texto (NULL solo es igual a NULL).
CREATE PROCEDURE t_eq(IN label VARCHAR(200), IN actual TEXT, IN expected TEXT)
BEGIN
  DECLARE msg VARCHAR(255);
  IF NOT (actual <=> expected) THEN
    SET msg = LEFT(CONCAT('FALLA: ', label, ' (esperado ', IFNULL(expected, 'NULL'),
                          ', obtenido ', IFNULL(actual, 'NULL'), ')'), 255);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
  END IF;
END$$

-- Ejecuta una sentencia que debe fallar. Si se ejecuta sin error, la prueba falla.
CREATE PROCEDURE t_rejects(IN label VARCHAR(200), IN stmt TEXT)
BEGIN
  DECLARE failed TINYINT DEFAULT 0;
  DECLARE msg VARCHAR(255);
  BEGIN
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET failed = 1;
    SET @t_stmt = stmt;
    PREPARE t_s FROM @t_stmt;
    EXECUTE t_s;
    DEALLOCATE PREPARE t_s;
  END;
  IF failed = 0 THEN
    SET msg = LEFT(CONCAT('FALLA: la base acepto lo que debia rechazar: ', label), 255);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;
  END IF;
END$$
DELIMITER ;

-- ============================== Migraciones ==================================
CALL t_eq('migraciones registradas',
  (SELECT GROUP_CONCAT(version ORDER BY version) FROM schema_migrations),
  '0001_core,0002_academic_extras,0003_grading_codocencia,0004_grading_views');

-- ============================== Calculo de notas =============================
-- Ejemplo del dueno: 7 actividades (48,48,34,50,50,50,40) -> 45,7 -> 46.
CALL t_eq('categoria Desarrollo = 46',
  (SELECT score FROM v_category_scores WHERE category_id = 2 AND enrollment_id = 1), '46');
CALL t_eq('categoria Autoevaluacion enviada = 50',
  (SELECT score FROM v_category_scores WHERE category_id = 5 AND enrollment_id = 1), '50');
CALL t_eq('autoevaluacion sin enviar = 36',
  (SELECT score FROM v_category_scores WHERE category_id = 8 AND enrollment_id = 1), '36');

-- Periodo: 5x50 + 40x46 + 20x49 + 30x49 + 5x50 = 4790 -> 47,9 -> 48 (Superior).
CALL t_eq('periodo 3 Matematicas = 48',
  (SELECT score FROM v_period_scores WHERE teaching_assignment_id = 1 AND period_id = 3 AND enrollment_id = 1), '48');
CALL t_eq('periodo 3 Matematicas es Superior',
  (SELECT descriptor FROM v_period_scores WHERE teaching_assignment_id = 1 AND period_id = 3 AND enrollment_id = 1), 'superior');
CALL t_eq('la nota guardada coincide con la calculada',
  (SELECT pg.score FROM period_grades pg WHERE pg.enrollment_id = 1 AND pg.teaching_assignment_id = 1 AND pg.period_id = 3),
  (SELECT v.score  FROM v_period_scores v WHERE v.enrollment_id = 1 AND v.teaching_assignment_id = 1 AND v.period_id = 3));

-- Ingles tiene una categoria sin notas: el periodo no se calcula.
CALL t_eq('periodo incompleto da NULL',
  (SELECT score FROM v_period_scores WHERE teaching_assignment_id = 3 AND period_id = 3 AND enrollment_id = 1), NULL);
CALL t_eq('periodo incompleto marcado',
  (SELECT is_complete FROM v_period_scores WHERE teaching_assignment_id = 3 AND period_id = 3 AND enrollment_id = 1), '0');

-- Definitivo: 30x48 + 40x50 + 30x48 = 4880 -> 48,8 -> 49.
CALL t_eq('Definitivo Matematicas = 49',
  (SELECT score FROM v_definitive_scores WHERE enrollment_id = 1 AND subject_id = 1), '49');

-- Redondeo medio hacia arriba: (48 + 49) / 2 = 48,5 -> 49. Categoria temporal en Lenguaje.
INSERT INTO grading_categories (id, teaching_assignment_id, period_id, name, weight_pct) VALUES (900, 2, 3, 'Prueba de redondeo', 100);
INSERT INTO grading_activities (id, category_id, title) VALUES (900, 900, 'A'), (901, 900, 'B');
INSERT INTO activity_scores (activity_id, enrollment_id, score) VALUES (900, 1, 48), (901, 1, 49);
CALL t_eq('48,5 se redondea a 49',
  (SELECT score FROM v_category_scores WHERE category_id = 900 AND enrollment_id = 1), '49');
CALL t_eq('periodo con una categoria de 100 %',
  (SELECT score FROM v_period_scores WHERE teaching_assignment_id = 2 AND period_id = 3 AND enrollment_id = 1), '49');

-- Una categoria borrada (deleted_at) no cuenta.
UPDATE grading_categories SET deleted_at = UTC_TIMESTAMP(3) WHERE id = 900;
CALL t_eq('categoria borrada no aparece',
  (SELECT COUNT(*) FROM v_category_scores WHERE category_id = 900), '0');

-- Porcentajes que no suman 100: el periodo no se calcula.
INSERT INTO grading_categories (id, teaching_assignment_id, period_id, name, weight_pct) VALUES (901, 2, 3, 'Solo 90 %', 90);
INSERT INTO grading_activities (id, category_id, title) VALUES (902, 901, 'C');
INSERT INTO activity_scores (activity_id, enrollment_id, score) VALUES (902, 1, 40);
CALL t_eq('porcentajes incompletos dan NULL',
  (SELECT score FROM v_period_scores WHERE teaching_assignment_id = 2 AND period_id = 3 AND enrollment_id = 1), NULL);

-- Limites de los descriptores.
CALL t_eq('35 es bajo',     (SELECT descriptor FROM grade_scales WHERE school_id = 1 AND 35 BETWEEN min_score AND max_score), 'bajo');
CALL t_eq('36 es basico',   (SELECT descriptor FROM grade_scales WHERE school_id = 1 AND 36 BETWEEN min_score AND max_score), 'basico');
CALL t_eq('43 es basico',   (SELECT descriptor FROM grade_scales WHERE school_id = 1 AND 43 BETWEEN min_score AND max_score), 'basico');
CALL t_eq('44 es alto',     (SELECT descriptor FROM grade_scales WHERE school_id = 1 AND 44 BETWEEN min_score AND max_score), 'alto');
CALL t_eq('46 es alto',     (SELECT descriptor FROM grade_scales WHERE school_id = 1 AND 46 BETWEEN min_score AND max_score), 'alto');
CALL t_eq('47 es superior', (SELECT descriptor FROM grade_scales WHERE school_id = 1 AND 47 BETWEEN min_score AND max_score), 'superior');

-- ============================== Correo y co-docencia =========================
CALL t_eq('no leidos de la estudiante',
  (SELECT COUNT(*) FROM message_recipients WHERE recipient_user_id = 15 AND folder = 'inbox' AND read_at IS NULL), '1');
CALL t_eq('respuesta al reemplazo con copia a la titular',
  (SELECT GROUP_CONCAT(CONCAT(recipient_user_id, ':', recipient_kind) ORDER BY recipient_user_id)
   FROM message_recipients WHERE message_id = 4), '3:to,4:cc');
CALL t_eq('marca "en reemplazo de"',
  (SELECT CONCAT(su.display_name, ' en reemplazo de ', tu.display_name)
   FROM messages m JOIN users su ON su.id = m.sender_user_id
   JOIN staff_members st ON st.id = m.on_behalf_of_staff_id JOIN users tu ON tu.id = st.user_id
   WHERE m.id = 3), 'Elena Vargas en reemplazo de Sandra Mejía');

-- ============================== PQRS, avisos, asistencia =====================
CALL t_eq('historial de la PQRS respondida',
  (SELECT GROUP_CONCAT(to_status ORDER BY id) FROM pqrs_ticket_history WHERE ticket_id = 1), 'received,in_review,answered');
CALL t_eq('avisos visibles para 3.o B',
  (SELECT COUNT(*) FROM notices n
   WHERE n.school_id = 1 AND n.status = 'published' AND n.deleted_at IS NULL
     AND (n.grade_level_id IS NULL OR n.grade_level_id = 3) AND (n.class_group_id IS NULL OR n.class_group_id = 6)), '2');
CALL t_eq('ausencias del dia',
  (SELECT COUNT(*) FROM attendance_records WHERE enrollment_id = 1 AND teaching_assignment_id IS NULL AND status = 'ausente'), '1');

-- ============================== Rechazos esperados ===========================
CALL t_rejects('nota de actividad 9',
  'INSERT INTO activity_scores (activity_id, enrollment_id, score) VALUES (12, 1, 9)');
CALL t_rejects('nota de actividad 51',
  'INSERT INTO activity_scores (activity_id, enrollment_id, score) VALUES (12, 1, 51)');
CALL t_rejects('nota de periodo 51',
  'UPDATE period_grades SET score = 51 WHERE id = 1');
CALL t_rejects('porcentaje de categoria 0',
  'INSERT INTO grading_categories (teaching_assignment_id, period_id, name, weight_pct) VALUES (1, 2, ''X'', 0)');
CALL t_rejects('segunda categoria de autoevaluacion',
  'INSERT INTO grading_categories (teaching_assignment_id, period_id, name, kind, weight_pct) VALUES (1, 3, ''Otra auto'', ''self_assessment'', 5)');
CALL t_rejects('criterio de autoevaluacion en 9',
  'INSERT INTO self_assessment_scores (submission_id, criterion_id, score) VALUES (2, 1, 9)');
CALL t_rejects('segunda entrega en la misma ventana',
  'INSERT INTO self_assessment_submissions (window_id, enrollment_id, final_score) VALUES (1, 1, 40)');
CALL t_rejects('segundo titular activo de la misma materia y grupo',
  'INSERT INTO teaching_assignments (school_id, academic_year_id, class_group_id, subject_id, staff_id) VALUES (1, 1, 6, 1, 2)');
CALL t_rejects('reemplazo que apunta a otra materia',
  'INSERT INTO teaching_assignments (school_id, academic_year_id, class_group_id, subject_id, staff_id, role, replaces_assignment_id) VALUES (1, 1, 6, 3, 1, ''reemplazo'', 1)');
CALL t_rejects('reemplazo sin titular',
  'INSERT INTO teaching_assignments (school_id, academic_year_id, class_group_id, subject_id, staff_id, role) VALUES (1, 1, 6, 3, 1, ''reemplazo'')');
CALL t_rejects('vigencia invertida',
  'UPDATE teaching_assignments SET valid_to = ''2026-09-01'' WHERE id = 9');
CALL t_rejects('mensaje en reemplazo de personal inexistente',
  'INSERT INTO messages (school_id, sender_user_id, on_behalf_of_staff_id, subject, body) VALUES (1, 3, 999, ''x'', ''x'')');
CALL t_rejects('destinatario repetido en un mensaje',
  'INSERT INTO message_recipients (message_id, recipient_user_id, sent_at) VALUES (1, 15, UTC_TIMESTAMP(3))');
CALL t_rejects('PQRS respondida sin respuesta',
  'UPDATE pqrs_tickets SET status = ''answered'' WHERE id = 2');
CALL t_rejects('consecutivo de PQRS repetido',
  'INSERT INTO pqrs_tickets (school_id, ticket_number, kind, requester_user_id, subject, body) VALUES (1, ''2026-000001'', ''queja'', 15, ''x'', ''x'')');
CALL t_rejects('aviso publicado sin fecha',
  'INSERT INTO notices (school_id, title, body, status, created_by_user_id) VALUES (1, ''x'', ''x'', ''published'', 14)');
CALL t_rejects('aviso para grado y grupo a la vez',
  'INSERT INTO notices (school_id, title, body, grade_level_id, class_group_id, created_by_user_id) VALUES (1, ''x'', ''x'', 3, 6, 14)');
CALL t_rejects('asistencia del dia repetida',
  'INSERT INTO attendance_records (enrollment_id, attendance_date, status, recorded_by_user_id) VALUES (1, ''2026-10-19'', ''ausente'', 6)');
CALL t_rejects('dominio con mayusculas',
  'INSERT INTO school_domains (school_id, host) VALUES (1, ''Portal.Demo.test'')');
CALL t_rejects('sesion con colegio inexistente',
  'INSERT INTO auth_sessions (user_id, school_id, token_hash, expires_at) VALUES (2, 999999, UNHEX(SHA2(''x'', 256)), ''2030-01-01'')');
CALL t_rejects('segunda matricula del mismo anio',
  'INSERT INTO enrollments (school_id, student_id, academic_year_id, class_group_id, enrolled_on) VALUES (1, 1, 1, 5, ''2026-02-01'')');

DROP PROCEDURE t_eq;
DROP PROCEDURE t_rejects;

SELECT 'OK: todas las pruebas pasaron' AS resultado;
