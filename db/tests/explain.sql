-- =============================================================================
-- tests/explain.sql  |  EXPLAIN ANALYZE de las consultas clave del MVP
-- Ejecutar sobre una base descartable cargada con tests/load_volume.sql.
-- Estudiante de ejemplo: matricula 1100 (usuario 2100, grupo 1003).
-- Docente de ejemplo: personal 1005 (usuario 1005).
-- Resultados y conclusiones en docs/database-design.md, seccion 10.
-- =============================================================================

SET time_zone = '+00:00';
SET @enr = 1100, @user = 2100, @staff = 1005, @year = 1, @school = 1;
SET @from = '2026-09-01 05:00:00', @to = '2026-09-15 05:00:00';

-- Q1a. Proximos eventos del estudiante (Hoy, Tareas, Calendario): audiencias de
-- colegio, de su grado, de su grupo y de las asignaciones de su grupo.
-- Forma "evento IN (audiencias)": recorre todos los eventos del colegio en el rango.
EXPLAIN ANALYZE
SELECT e.id, e.title, e.starts_at, e.event_type_id, e.subject_id
FROM events e
WHERE e.school_id = @school AND e.academic_year_id = @year
  AND e.status = 'published' AND e.deleted_at IS NULL
  AND e.starts_at >= @from AND e.starts_at < @to
  AND e.id IN (
    SELECT ea.event_id FROM event_audiences ea WHERE ea.scope_type = 'school'
    UNION ALL
    SELECT ea.event_id FROM event_audiences ea
      JOIN class_groups cg ON cg.grade_level_id = ea.grade_level_id
      JOIN enrollments en ON en.class_group_id = cg.id AND en.id = @enr
    UNION ALL
    SELECT ea.event_id FROM event_audiences ea
      JOIN enrollments en ON en.class_group_id = ea.class_group_id AND en.id = @enr
    UNION ALL
    SELECT ea.event_id FROM event_audiences ea
      JOIN teaching_assignments ta ON ta.id = ea.teaching_assignment_id
      JOIN enrollments en ON en.class_group_id = ta.class_group_id AND en.id = @enr)
ORDER BY e.starts_at
LIMIT 50;

-- Q1b. Mismo resultado partiendo de las audiencias del estudiante (forma recomendada
-- para la API: lee solo los eventos que le tocan).
EXPLAIN ANALYZE
SELECT e.id, e.title, e.starts_at, e.event_type_id, e.subject_id
FROM (
  SELECT ea.event_id FROM event_audiences ea WHERE ea.scope_type = 'school'
  UNION
  SELECT ea.event_id FROM enrollments en JOIN class_groups cg ON cg.id = en.class_group_id
    JOIN event_audiences ea ON ea.grade_level_id = cg.grade_level_id WHERE en.id = @enr
  UNION
  SELECT ea.event_id FROM enrollments en
    JOIN event_audiences ea ON ea.class_group_id = en.class_group_id WHERE en.id = @enr
  UNION
  SELECT ea.event_id FROM enrollments en
    JOIN teaching_assignments ta ON ta.class_group_id = en.class_group_id
    JOIN event_audiences ea ON ea.teaching_assignment_id = ta.id WHERE en.id = @enr
) t
JOIN events e ON e.id = t.event_id
WHERE e.school_id = @school AND e.academic_year_id = @year
  AND e.status = 'published' AND e.deleted_at IS NULL
  AND e.starts_at >= @from AND e.starts_at < @to
ORDER BY e.starts_at LIMIT 50;

-- Q2. Bandeja de entrada (20 mas recientes).
EXPLAIN ANALYZE
SELECT mr.message_id, m.subject, u.display_name, mr.sent_at, mr.read_at
FROM message_recipients mr
JOIN messages m ON m.id = mr.message_id
JOIN users u ON u.id = m.sender_user_id
WHERE mr.recipient_user_id = @user AND mr.folder = 'inbox'
ORDER BY mr.sent_at DESC
LIMIT 20;

-- Q3. Contador de no leidos (se consulta en cada pantalla).
EXPLAIN ANALYZE
SELECT COUNT(*) FROM message_recipients
WHERE recipient_user_id = @user AND folder = 'inbox' AND read_at IS NULL;

-- Q4. Grupos y materias del docente en el anio.
EXPLAIN ANALYZE
SELECT ta.id, cg.section, gl.name, s.name
FROM teaching_assignments ta
JOIN class_groups cg ON cg.id = ta.class_group_id
JOIN grade_levels gl ON gl.id = cg.grade_level_id
JOIN subjects s ON s.id = ta.subject_id
WHERE ta.staff_id = @staff AND ta.academic_year_id = @year
  AND ta.status = 'active' AND ta.deleted_at IS NULL;

-- Q5a. Notas del periodo de un estudiante usando la vista.
EXPLAIN ANALYZE
SELECT teaching_assignment_id, score, descriptor
FROM v_period_scores
WHERE enrollment_id = @enr AND period_id = 2;

-- Q5b. La misma nota con consulta directa filtrada por matricula (lo que deberia
-- hacer la API en lecturas por estudiante).
EXPLAIN ANALYZE
SELECT c.teaching_assignment_id,
       IF(SUM(c.weight_pct) = 100 AND COUNT(c.score) = COUNT(*),
          (SUM(c.score * c.weight_pct) + 50) DIV 100, NULL) AS score
FROM (
  SELECT gc.id, gc.teaching_assignment_id, gc.weight_pct,
         (SELECT (2 * SUM(s.score) + COUNT(*)) DIV (2 * COUNT(*))
          FROM grading_activities ga
          JOIN activity_scores s ON s.activity_id = ga.id AND s.enrollment_id = @enr
          WHERE ga.category_id = gc.id AND ga.deleted_at IS NULL) AS score
  FROM grading_categories gc
  JOIN teaching_assignments ta ON ta.id = gc.teaching_assignment_id
  JOIN enrollments en ON en.class_group_id = ta.class_group_id AND en.id = @enr
  WHERE gc.period_id = 2 AND gc.deleted_at IS NULL AND gc.kind = 'regular'
) c
GROUP BY c.teaching_assignment_id;

-- Q6. Bandeja de PQRS de administracion (pendientes, mas antiguas primero).
EXPLAIN ANALYZE
SELECT id, ticket_number, kind, subject, created_at
FROM pqrs_tickets
WHERE school_id = @school AND status IN ('received', 'in_review')
ORDER BY created_at
LIMIT 50;

-- Q7. Asistencia del estudiante en el periodo.
EXPLAIN ANALYZE
SELECT status, COUNT(*)
FROM attendance_records
WHERE enrollment_id = @enr AND attendance_date BETWEEN '2026-05-04' AND '2026-08-14'
GROUP BY status;
