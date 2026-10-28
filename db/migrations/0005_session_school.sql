-- =============================================================================
-- 0005_session_school.sql  |  FASE 1  |  MySQL 8.0.16+ / InnoDB / utf8mb4
-- La sesión queda atada al colegio donde se inició (revisión de seguridad S1.1):
-- auth_sessions.school_id. NULL = sesión del host de administración de la
-- plataforma. La API rechaza una sesión usada desde el host de otro colegio.
-- Requiere 0001. Se ejecuta una sola vez: el ALTER está dentro de un
-- procedimiento que se salta si '0005_session_school' ya está registrada.
-- Las sesiones abiertas antes de esta migración se revocan (no tienen colegio).
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';

DROP PROCEDURE IF EXISTS campus_migrate_0005;

DELIMITER $$
CREATE PROCEDURE campus_migrate_0005()
BEGIN
  IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '0005_session_school') THEN
    UPDATE auth_sessions SET revoked_at = CURRENT_TIMESTAMP(3) WHERE revoked_at IS NULL;

    ALTER TABLE auth_sessions
      ADD COLUMN school_id BIGINT UNSIGNED NULL
        COMMENT 'Colegio donde se inició; NULL = host de administración'
        AFTER user_id,
      ADD CONSTRAINT fk_auth_sessions__school FOREIGN KEY (school_id) REFERENCES schools (id) ON DELETE CASCADE;

    INSERT IGNORE INTO schema_migrations (version) VALUES ('0005_session_school');
  END IF;
END$$
DELIMITER ;

CALL campus_migrate_0005();
DROP PROCEDURE campus_migrate_0005;
