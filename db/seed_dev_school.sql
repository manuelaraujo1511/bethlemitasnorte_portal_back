-- =============================================================================
-- seed_dev_school.sql  |  SOLO DESARROLLO  |  requiere 0001-0004, seed_dev.sql y
-- seed_dev_academic.sql
-- B1.1: completa el colegio sintetico para probar la API con datos realistas:
--   * dominios del colegio para resolverlo por host (localhost y demo.campus.localhost),
--   * 39 estudiantes mas (3.o B queda con 30 y 3.o A con 10; 40 en total con Ana),
--   * asignaciones de las 8 materias en 3.o A (los mismos docentes que en 3.o B),
--     para probar alcances de docente y director entre dos grupos.
-- Todos los nombres, codigos y fechas son INVENTADOS (generados con semilla fija).
-- Hash de contrasena falso como en seed_dev.sql; para entrar en local se fija con
-- `npm run db:dev-passwords` (B1.2), nunca con hashes versionados.
-- Ids 100-199 en usuarios, estudiantes, matriculas y asignaciones; no chocan con
-- los seeds anteriores ni con tests/load_volume.sql (ids >= 1000).
-- Re-ejecutable: INSERT IGNORE con ids fijos.
-- =============================================================================

SET NAMES utf8mb4;
SET time_zone = '+00:00';
SET @fake_hash = '$argon2id$DEV-PLACEHOLDER-NOT-A-REAL-HASH';

-- --------------------------- Dominios del colegio ----------------------------
INSERT IGNORE INTO school_domains (id, school_id, host, is_primary) VALUES
 (1, 1, 'demo.campus.localhost', 1),
 (2, 1, 'localhost', 0);

-- --------------------------- 3.o A: director y asignaciones ------------------
UPDATE class_groups SET director_staff_id = 2 WHERE id = 5 AND director_staff_id IS NULL;

INSERT IGNORE INTO teaching_assignments (id, school_id, academic_year_id, class_group_id, subject_id, staff_id, created_by_user_id) VALUES
 (101,1,1,5,1,1,14),(102,1,1,5,2,2,14),(103,1,1,5,3,3,14),(104,1,1,5,4,4,14),
 (105,1,1,5,5,5,14),(106,1,1,5,6,6,14),(107,1,1,5,7,7,14),(108,1,1,5,8,8,14);

-- --------------------------- Estudiantes (39) --------------------------------
INSERT IGNORE INTO users (id, username, first_name, last_name, display_name, password_hash, status) VALUES
 (101,'natalia.cardenas.002','Natalia','Cárdenas Pérez','Natalia Cárdenas Pérez',@fake_hash,'active'),
 (102,'luciana.rodriguez.003','Luciana','Rodríguez Castro','Luciana Rodríguez Castro',@fake_hash,'active'),
 (103,'natalia.cardenas.004','Natalia','Cárdenas Mora','Natalia Cárdenas Mora',@fake_hash,'active'),
 (104,'camila.castro.005','Camila','Castro Muñoz','Camila Castro Muñoz',@fake_hash,'active'),
 (105,'camila.castro.006','Camila','Castro García','Camila Castro García',@fake_hash,'active'),
 (106,'camila.ortiz.007','Camila','Ortiz Martínez','Camila Ortiz Martínez',@fake_hash,'active'),
 (107,'manuela.arango.008','Manuela','Arango Hernández','Manuela Arango Hernández',@fake_hash,'active'),
 (108,'salome.diaz.009','Salomé','Díaz Ospina','Salomé Díaz Ospina',@fake_hash,'active'),
 (109,'alejandro.sanchez.010','Alejandro','Sánchez Rojas','Alejandro Sánchez Rojas',@fake_hash,'active'),
 (110,'samuel.garcia.011','Samuel','García Acosta','Samuel García Acosta',@fake_hash,'active'),
 (111,'nicolas.acosta.012','Nicolás','Acosta Martínez','Nicolás Acosta Martínez',@fake_hash,'active'),
 (112,'nicolas.moreno.013','Nicolás','Moreno Rodríguez','Nicolás Moreno Rodríguez',@fake_hash,'active'),
 (113,'juanjose.zapata.014','Juan José','Zapata Restrepo','Juan José Zapata Restrepo',@fake_hash,'active'),
 (114,'juliana.gutierrez.015','Juliana','Gutiérrez Zapata','Juliana Gutiérrez Zapata',@fake_hash,'active'),
 (115,'manuela.restrepo.016','Manuela','Restrepo Zapata','Manuela Restrepo Zapata',@fake_hash,'active'),
 (116,'sofia.cardenas.017','Sofía','Cárdenas López','Sofía Cárdenas López',@fake_hash,'active'),
 (117,'emiliano.zapata.018','Emiliano','Zapata Bermúdez','Emiliano Zapata Bermúdez',@fake_hash,'active'),
 (118,'david.ramirez.019','David','Ramírez Castro','David Ramírez Castro',@fake_hash,'active'),
 (119,'tomas.perez.020','Tomás','Pérez Zapata','Tomás Pérez Zapata',@fake_hash,'active'),
 (120,'paula.zapata.021','Paula','Zapata Romero','Paula Zapata Romero',@fake_hash,'active'),
 (121,'salome.bermudez.022','Salomé','Bermúdez González','Salomé Bermúdez González',@fake_hash,'active'),
 (122,'emiliano.acosta.023','Emiliano','Acosta Rodríguez','Emiliano Acosta Rodríguez',@fake_hash,'active'),
 (123,'nicolas.suarez.024','Nicolás','Suárez Ortiz','Nicolás Suárez Ortiz',@fake_hash,'active'),
 (124,'sara.garcia.025','Sara','García Hernández','Sara García Hernández',@fake_hash,'active'),
 (125,'felipe.perez.026','Felipe','Pérez Rodríguez','Felipe Pérez Rodríguez',@fake_hash,'active'),
 (126,'felipe.hernandez.027','Felipe','Hernández Restrepo','Felipe Hernández Restrepo',@fake_hash,'active'),
 (127,'sebastian.bermudez.028','Sebastián','Bermúdez Ortiz','Sebastián Bermúdez Ortiz',@fake_hash,'active'),
 (128,'antonella.bermudez.029','Antonella','Bermúdez Zapata','Antonella Bermúdez Zapata',@fake_hash,'active'),
 (129,'santiago.munoz.030','Santiago','Muñoz Castro','Santiago Muñoz Castro',@fake_hash,'active'),
 (130,'martina.zapata.031','Martina','Zapata López','Martina Zapata López',@fake_hash,'active'),
 (131,'mariana.gonzalez.032','Mariana','González García','Mariana González García',@fake_hash,'active'),
 (132,'david.suarez.033','David','Suárez García','David Suárez García',@fake_hash,'active'),
 (133,'camila.ospina.034','Camila','Ospina Moreno','Camila Ospina Moreno',@fake_hash,'active'),
 (134,'juliana.castro.035','Juliana','Castro Pineda','Juliana Castro Pineda',@fake_hash,'active'),
 (135,'lucas.gutierrez.036','Lucas','Gutiérrez Vargas','Lucas Gutiérrez Vargas',@fake_hash,'active'),
 (136,'juliana.rojas.037','Juliana','Rojas Castro','Juliana Rojas Castro',@fake_hash,'active'),
 (137,'jeronimo.gonzalez.038','Jerónimo','González Arango','Jerónimo González Arango',@fake_hash,'active'),
 (138,'emilia.moreno.039','Emilia','Moreno Ramírez','Emilia Moreno Ramírez',@fake_hash,'active'),
 (139,'gabriela.castro.040','Gabriela','Castro Restrepo','Gabriela Castro Restrepo',@fake_hash,'active');

INSERT IGNORE INTO user_roles (id, user_id, school_id, role, coordinator_type, granted_by_user_id) VALUES
 (101,101,1,'student',NULL,14),
 (102,102,1,'student',NULL,14),
 (103,103,1,'student',NULL,14),
 (104,104,1,'student',NULL,14),
 (105,105,1,'student',NULL,14),
 (106,106,1,'student',NULL,14),
 (107,107,1,'student',NULL,14),
 (108,108,1,'student',NULL,14),
 (109,109,1,'student',NULL,14),
 (110,110,1,'student',NULL,14),
 (111,111,1,'student',NULL,14),
 (112,112,1,'student',NULL,14),
 (113,113,1,'student',NULL,14),
 (114,114,1,'student',NULL,14),
 (115,115,1,'student',NULL,14),
 (116,116,1,'student',NULL,14),
 (117,117,1,'student',NULL,14),
 (118,118,1,'student',NULL,14),
 (119,119,1,'student',NULL,14),
 (120,120,1,'student',NULL,14),
 (121,121,1,'student',NULL,14),
 (122,122,1,'student',NULL,14),
 (123,123,1,'student',NULL,14),
 (124,124,1,'student',NULL,14),
 (125,125,1,'student',NULL,14),
 (126,126,1,'student',NULL,14),
 (127,127,1,'student',NULL,14),
 (128,128,1,'student',NULL,14),
 (129,129,1,'student',NULL,14),
 (130,130,1,'student',NULL,14),
 (131,131,1,'student',NULL,14),
 (132,132,1,'student',NULL,14),
 (133,133,1,'student',NULL,14),
 (134,134,1,'student',NULL,14),
 (135,135,1,'student',NULL,14),
 (136,136,1,'student',NULL,14),
 (137,137,1,'student',NULL,14),
 (138,138,1,'student',NULL,14),
 (139,139,1,'student',NULL,14);

-- Documento: marcador ficticio unico por estudiante, como en seed_dev.sql.
INSERT IGNORE INTO students (id, school_id, user_id, student_code, document_type, document_number_enc, document_number_hash, birth_date, sex, created_by_user_id) VALUES
 (101,1,101,'900002','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900002',256)),'2017-08-18','F',14),
 (102,1,102,'900003','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900003',256)),'2017-10-27','F',14),
 (103,1,103,'900004','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900004',256)),'2017-10-28','F',14),
 (104,1,104,'900005','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900005',256)),'2018-11-22','F',14),
 (105,1,105,'900006','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900006',256)),'2017-01-22','F',14),
 (106,1,106,'900007','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900007',256)),'2018-03-05','F',14),
 (107,1,107,'900008','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900008',256)),'2017-08-06','F',14),
 (108,1,108,'900009','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900009',256)),'2018-05-23','F',14),
 (109,1,109,'900010','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900010',256)),'2017-06-16','M',14),
 (110,1,110,'900011','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900011',256)),'2018-09-17','M',14),
 (111,1,111,'900012','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900012',256)),'2017-05-06','M',14),
 (112,1,112,'900013','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900013',256)),'2017-05-13','M',14),
 (113,1,113,'900014','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900014',256)),'2018-09-09','M',14),
 (114,1,114,'900015','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900015',256)),'2017-01-12','F',14),
 (115,1,115,'900016','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900016',256)),'2018-02-10','F',14),
 (116,1,116,'900017','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900017',256)),'2017-04-20','F',14),
 (117,1,117,'900018','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900018',256)),'2018-11-27','M',14),
 (118,1,118,'900019','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900019',256)),'2018-03-27','M',14),
 (119,1,119,'900020','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900020',256)),'2017-04-11','M',14),
 (120,1,120,'900021','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900021',256)),'2017-11-13','F',14),
 (121,1,121,'900022','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900022',256)),'2017-02-09','F',14),
 (122,1,122,'900023','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900023',256)),'2017-02-04','M',14),
 (123,1,123,'900024','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900024',256)),'2018-10-10','M',14),
 (124,1,124,'900025','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900025',256)),'2018-11-24','F',14),
 (125,1,125,'900026','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900026',256)),'2017-01-12','M',14),
 (126,1,126,'900027','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900027',256)),'2018-03-15','M',14),
 (127,1,127,'900028','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900028',256)),'2017-11-05','M',14),
 (128,1,128,'900029','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900029',256)),'2018-06-27','F',14),
 (129,1,129,'900030','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900030',256)),'2018-05-16','M',14),
 (130,1,130,'900031','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900031',256)),'2018-12-03','F',14),
 (131,1,131,'900032','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900032',256)),'2018-07-13','F',14),
 (132,1,132,'900033','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900033',256)),'2017-01-12','M',14),
 (133,1,133,'900034','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900034',256)),'2018-06-15','F',14),
 (134,1,134,'900035','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900035',256)),'2018-09-22','F',14),
 (135,1,135,'900036','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900036',256)),'2017-09-19','M',14),
 (136,1,136,'900037','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900037',256)),'2018-06-07','F',14),
 (137,1,137,'900038','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900038',256)),'2017-09-11','M',14),
 (138,1,138,'900039','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900039',256)),'2018-10-24','F',14),
 (139,1,139,'900040','TI',UNHEX('00'),UNHEX(SHA2('DEV-ONLY-NOT-A-REAL-DOCUMENT-900040',256)),'2017-06-05','F',14);

INSERT IGNORE INTO enrollments (id, school_id, student_id, academic_year_id, class_group_id, list_number, enrolled_on, created_by_user_id) VALUES
 (101,1,101,1,6,1,'2026-01-12',14),
 (102,1,102,1,6,2,'2026-01-12',14),
 (103,1,103,1,6,3,'2026-01-12',14),
 (104,1,104,1,6,4,'2026-01-12',14),
 (105,1,105,1,6,5,'2026-01-12',14),
 (106,1,106,1,6,6,'2026-01-12',14),
 (107,1,107,1,6,8,'2026-01-12',14),
 (108,1,108,1,6,9,'2026-01-12',14),
 (109,1,109,1,6,10,'2026-01-12',14),
 (110,1,110,1,6,11,'2026-01-12',14),
 (111,1,111,1,6,12,'2026-01-12',14),
 (112,1,112,1,6,13,'2026-01-12',14),
 (113,1,113,1,6,14,'2026-01-12',14),
 (114,1,114,1,6,15,'2026-01-12',14),
 (115,1,115,1,6,16,'2026-01-12',14),
 (116,1,116,1,6,17,'2026-01-12',14),
 (117,1,117,1,6,18,'2026-01-12',14),
 (118,1,118,1,6,19,'2026-01-12',14),
 (119,1,119,1,6,20,'2026-01-12',14),
 (120,1,120,1,6,21,'2026-01-12',14),
 (121,1,121,1,6,22,'2026-01-12',14),
 (122,1,122,1,6,23,'2026-01-12',14),
 (123,1,123,1,6,24,'2026-01-12',14),
 (124,1,124,1,6,25,'2026-01-12',14),
 (125,1,125,1,6,26,'2026-01-12',14),
 (126,1,126,1,6,27,'2026-01-12',14),
 (127,1,127,1,6,28,'2026-01-12',14),
 (128,1,128,1,6,29,'2026-01-12',14),
 (129,1,129,1,6,30,'2026-01-12',14),
 (130,1,130,1,5,1,'2026-01-12',14),
 (131,1,131,1,5,2,'2026-01-12',14),
 (132,1,132,1,5,3,'2026-01-12',14),
 (133,1,133,1,5,4,'2026-01-12',14),
 (134,1,134,1,5,5,'2026-01-12',14),
 (135,1,135,1,5,6,'2026-01-12',14),
 (136,1,136,1,5,7,'2026-01-12',14),
 (137,1,137,1,5,8,'2026-01-12',14),
 (138,1,138,1,5,9,'2026-01-12',14),
 (139,1,139,1,5,10,'2026-01-12',14);
