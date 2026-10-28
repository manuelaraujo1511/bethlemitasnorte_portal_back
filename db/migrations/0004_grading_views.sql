-- =============================================================================
-- 0004_grading_views.sql  |  FASE 2b  |  MySQL 8.0.16+ / InnoDB / utf8mb4
-- Vistas de calculo de notas que replican campus/packages/core/src/logic/grading.ts
-- (docs/database-design.md, sec. 9). Sirven para:
--   * que la API lea la nota de una categoria, de un periodo y el Definitivo sin
--     repetir la regla en cada consulta;
--   * que un trabajo al cerrar el periodo copie el resultado a period_grades
--     (source='computed');
--   * verificar en pruebas que la base y el front calculan lo mismo.
-- Reglas:
--   * Categoria regular: promedio simple de sus actividades con nota, redondeado a
--     entero, medio hacia arriba (24,5 -> 25). Una actividad sin nota del estudiante
--     no cuenta (aun no calificada; confirmado por el dueno el 2026-10-28).
--   * Categoria de autoevaluacion: final_score de la entrega del estudiante en la
--     ventana de esa asignacion y periodo (36 si cerro sin envio).
--   * Periodo: suma de (nota de categoria ya redondeada x porcentaje) / 100,
--     redondeada. Solo se calcula si los porcentajes suman 100 y todas las
--     categorias tienen nota; si no, score es NULL e is_complete = 0.
--   * Definitivo: suma de (nota de periodo x peso del periodo) / 100, redondeada,
--     solo con los 3 periodos regulares calificados y pesos que suman 100.
-- El redondeo se hace con aritmetica entera o decimal exacta (sin FLOAT).
-- Requiere 0001 a 0003. Re-ejecutable (CREATE OR REPLACE VIEW).
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- Nota de cada estudiante en cada categoria.
CREATE OR REPLACE VIEW v_category_scores AS
SELECT gc.id                     AS category_id,
       gc.teaching_assignment_id,
       gc.period_id,
       s.enrollment_id,
       (2 * SUM(s.score) + COUNT(*)) DIV (2 * COUNT(*)) AS score,
       COUNT(*)                  AS scored_activities
FROM grading_categories gc
JOIN grading_activities ga ON ga.category_id = gc.id AND ga.deleted_at IS NULL
JOIN activity_scores s     ON s.activity_id = ga.id
WHERE gc.deleted_at IS NULL
  AND gc.kind = 'regular'
GROUP BY gc.id, gc.teaching_assignment_id, gc.period_id, s.enrollment_id
UNION ALL
SELECT gc.id,
       gc.teaching_assignment_id,
       gc.period_id,
       sub.enrollment_id,
       sub.final_score,
       NULL
FROM grading_categories gc
JOIN self_assessment_windows w      ON w.teaching_assignment_id = gc.teaching_assignment_id
                                   AND w.period_id = gc.period_id
JOIN self_assessment_submissions sub ON sub.window_id = w.id
WHERE gc.deleted_at IS NULL
  AND gc.kind = 'self_assessment';

-- Nota de periodo por estudiante, asignacion y periodo (con descriptor).
-- Una fila por estudiante que tenga al menos una categoria con nota.
CREATE OR REPLACE VIEW v_period_scores AS
WITH cats AS (
  SELECT teaching_assignment_id, period_id,
         COUNT(*) AS categories, SUM(weight_pct) AS total_pct
  FROM grading_categories
  WHERE deleted_at IS NULL
  GROUP BY teaching_assignment_id, period_id
),
partial AS (
  SELECT cs.teaching_assignment_id, cs.period_id, cs.enrollment_id,
         COUNT(*)                        AS scored_categories,
         SUM(cs.score * gc.weight_pct)   AS weighted_sum
  FROM v_category_scores cs
  JOIN grading_categories gc ON gc.id = cs.category_id
  GROUP BY cs.teaching_assignment_id, cs.period_id, cs.enrollment_id
),
scored AS (
  SELECT p.teaching_assignment_id, p.period_id, p.enrollment_id,
         p.scored_categories, c.categories, c.total_pct,
         IF(c.total_pct = 100 AND p.scored_categories = c.categories,
            (p.weighted_sum + 50) DIV 100, NULL) AS score
  FROM partial p
  JOIN cats c ON c.teaching_assignment_id = p.teaching_assignment_id
             AND c.period_id = p.period_id
)
SELECT sc.teaching_assignment_id, sc.period_id, sc.enrollment_id,
       sc.score,
       gs.descriptor,
       (sc.score IS NOT NULL)  AS is_complete,
       sc.scored_categories, sc.categories, sc.total_pct
FROM scored sc
JOIN enrollments e       ON e.id = sc.enrollment_id
LEFT JOIN grade_scales gs ON gs.school_id = e.school_id
                         AND sc.score BETWEEN gs.min_score AND gs.max_score;

-- Definitivo por estudiante y materia, a partir de period_grades (notas de periodo
-- ya cerradas o ajustadas). Se agrupa por materia y no por asignacion, porque el
-- titular puede cambiar entre periodos.
CREATE OR REPLACE VIEW v_definitive_scores AS
WITH weights AS (
  SELECT p.academic_year_id, COUNT(*) AS periods, SUM(pw.weight_pct) AS total_pct
  FROM periods p
  JOIN period_weights pw ON pw.period_id = p.id
  WHERE p.kind = 'regular'
  GROUP BY p.academic_year_id
),
graded AS (
  SELECT pg.enrollment_id, ta.subject_id, p.academic_year_id,
         COUNT(*)                        AS graded_periods,
         SUM(pg.score * pw.weight_pct)   AS weighted_sum
  FROM period_grades pg
  JOIN periods p              ON p.id = pg.period_id AND p.kind = 'regular'
  JOIN period_weights pw      ON pw.period_id = p.id
  JOIN teaching_assignments ta ON ta.id = pg.teaching_assignment_id
  GROUP BY pg.enrollment_id, ta.subject_id, p.academic_year_id
),
scored AS (
  SELECT g.enrollment_id, g.subject_id, g.academic_year_id, g.graded_periods,
         IF(w.total_pct = 100 AND g.graded_periods = w.periods,
            FLOOR((g.weighted_sum + 50) / 100), NULL) AS score
  FROM graded g
  JOIN weights w ON w.academic_year_id = g.academic_year_id
)
SELECT sc.enrollment_id, sc.subject_id, sc.academic_year_id,
       CAST(sc.score AS UNSIGNED) AS score,
       gs.descriptor,
       (sc.score IS NOT NULL)     AS is_complete,
       sc.graded_periods
FROM scored sc
JOIN enrollments e       ON e.id = sc.enrollment_id
LEFT JOIN grade_scales gs ON gs.school_id = e.school_id
                         AND sc.score BETWEEN gs.min_score AND gs.max_score;

INSERT IGNORE INTO schema_migrations (version) VALUES ('0004_grading_views');
