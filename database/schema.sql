-- =====================================================================
-- Control de visitas - Edificio COFIEC
-- Base de datos MySQL 8 (compatible con MariaDB 10.5 o superior)
-- Autora del diseño: Carmen Violeta Tapia Sotamba (backend y datos)
--
-- Cómo usarlo en MySQL Workbench: abrir este archivo y ejecutarlo
-- completo (icono del rayo). Es seguro volver a ejecutarlo: borra y
-- recrea la base, así que NO usarlo cuando ya haya datos reales.
-- =====================================================================

DROP DATABASE IF EXISTS control_visitas;
CREATE DATABASE control_visitas
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE control_visitas;

-- ---------------------------------------------------------------------
-- 1. Roles y usuarios
-- Roles: administrador, recepcionista y guardia.
-- Cada persona usa su propia cuenta (trazabilidad de quién atendió).
-- El primer usuario administrador se crea desde el backend, con la
-- contraseña cifrada con bcrypt. Aquí NO se guardan contraseñas.
-- ---------------------------------------------------------------------
CREATE TABLE roles (
  id     INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE usuarios (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  nombre        VARCHAR(100) NOT NULL,
  usuario       VARCHAR(50)  NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  rol_id        INT NOT NULL,
  activo        BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (rol_id) REFERENCES roles(id)
);

-- ---------------------------------------------------------------------
-- 2. Pisos, empresas y su ubicación
-- numero: -4 a -2 = subsuelos de parqueadero, -1 = subsuelo 1 (oficinas),
--         0 = planta baja, 1 a 18 = pisos.
-- Una empresa puede ocupar varios pisos y un piso puede tener
-- varias empresas (relación muchos a muchos en empresa_pisos).
-- ---------------------------------------------------------------------
CREATE TABLE pisos (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  numero      INT NOT NULL UNIQUE,
  descripcion VARCHAR(50) NOT NULL
);

CREATE TABLE empresas (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  nombre       VARCHAR(120) NOT NULL UNIQUE,
  razon_social VARCHAR(150) NULL,          -- pendiente: nombre completo oficial
  tipo         VARCHAR(20)  NOT NULL DEFAULT 'empresa',
  activa       BOOLEAN NOT NULL DEFAULT TRUE,
  CHECK (tipo IN ('empresa', 'administracion'))
);

CREATE TABLE empresa_pisos (
  empresa_id INT NOT NULL,
  piso_id    INT NOT NULL,
  PRIMARY KEY (empresa_id, piso_id),
  FOREIGN KEY (empresa_id) REFERENCES empresas(id),
  FOREIGN KEY (piso_id)    REFERENCES pisos(id)
);

-- ---------------------------------------------------------------------
-- 3. Visitantes y visitas (formato "Control de visitantes")
-- Documento: cédula, pasaporte o licencia de conducir.
-- "Persona a quien visita" y "persona que autoriza" se guardan como
-- texto, porque suelen ser la recepcionista de la empresa visitada.
-- puesto: 1 = recepción, 2 = parqueadero (de dónde se registró).
-- La salida la puede registrar cualquier usuario: se guardan los dos.
-- ---------------------------------------------------------------------
CREATE TABLE visitantes (
  id                INT AUTO_INCREMENT PRIMARY KEY,
  tipo_documento    VARCHAR(10)  NOT NULL DEFAULT 'cedula',
  documento         VARCHAR(20)  NOT NULL,
  apellidos_nombres VARCHAR(150) NOT NULL,
  creado_en         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (tipo_documento, documento),
  CHECK (tipo_documento IN ('cedula', 'pasaporte', 'licencia'))
);

CREATE TABLE visitas (
  id                 INT AUTO_INCREMENT PRIMARY KEY,
  visitante_id       INT NOT NULL,
  empresa_id         INT NOT NULL,
  piso_id            INT NOT NULL,
  persona_visitada   VARCHAR(100) NOT NULL,   -- persona a quien visita
  persona_autoriza   VARCHAR(100) NOT NULL,   -- persona que autoriza el ingreso
  puesto             TINYINT NOT NULL DEFAULT 1,
  fecha_entrada      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  fecha_salida       DATETIME NULL,
  usuario_entrada_id INT NOT NULL,
  usuario_salida_id  INT NULL,
  FOREIGN KEY (visitante_id)       REFERENCES visitantes(id),
  FOREIGN KEY (empresa_id)         REFERENCES empresas(id),
  FOREIGN KEY (piso_id)            REFERENCES pisos(id),
  FOREIGN KEY (usuario_entrada_id) REFERENCES usuarios(id),
  FOREIGN KEY (usuario_salida_id)  REFERENCES usuarios(id),
  CHECK (puesto IN (1, 2)),
  INDEX idx_visitas_entrada (fecha_entrada),
  INDEX idx_visitas_salida (fecha_salida),
  INDEX idx_visitas_empresa (empresa_id)
);

-- ---------------------------------------------------------------------
-- 4. Vehículos (formato "Control de parqueaderos")
-- Se anota: nombre de quien ingresa, placa, piso, horas y observaciones.
-- No se registra el color ni el número de espacio.
-- piso_id es opcional: "Piso N°" del formato puede ser el subsuelo o el
-- piso de destino (pendiente de confirmar con la administración).
-- ---------------------------------------------------------------------
CREATE TABLE registros_vehiculos (
  id                 INT AUTO_INCREMENT PRIMARY KEY,
  nombre_persona     VARCHAR(150) NOT NULL,
  placa              VARCHAR(10)  NOT NULL,
  piso_id            INT NULL,
  observaciones      VARCHAR(200) NULL,
  puesto             TINYINT NOT NULL DEFAULT 2,
  hora_entrada       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  hora_salida        DATETIME NULL,
  usuario_entrada_id INT NOT NULL,
  usuario_salida_id  INT NULL,
  FOREIGN KEY (piso_id)            REFERENCES pisos(id),
  FOREIGN KEY (usuario_entrada_id) REFERENCES usuarios(id),
  FOREIGN KEY (usuario_salida_id)  REFERENCES usuarios(id),
  CHECK (puesto IN (1, 2)),
  INDEX idx_veh_placa (placa),
  INDEX idx_veh_entrada (hora_entrada),
  INDEX idx_veh_salida (hora_salida)
);

-- ---------------------------------------------------------------------
-- 5. Configuración y auditoría
-- ---------------------------------------------------------------------
CREATE TABLE configuracion (
  clave VARCHAR(50)  PRIMARY KEY,
  valor VARCHAR(100) NOT NULL,
  nota  VARCHAR(200) NULL
);

CREATE TABLE log_auditoria (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  usuario_id  INT NULL,
  accion      VARCHAR(50)  NOT NULL,          -- login, crear, editar, salida...
  entidad     VARCHAR(50)  NULL,              -- visitas, usuarios, empresas...
  entidad_id  INT NULL,
  detalle     VARCHAR(255) NULL,
  puesto      TINYINT NULL,
  fecha       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
  INDEX idx_audit_fecha (fecha)
);

-- =====================================================================
-- DATOS INICIALES
-- =====================================================================

INSERT INTO roles (nombre) VALUES ('administrador'), ('recepcionista'), ('guardia');

INSERT INTO configuracion (clave, valor, nota) VALUES
  ('capacidad_espacio_visitantes', '1',
   'Espacios de parqueadero para visitantes del edificio. Pendiente confirmar cuál es.'),
  ('meses_conservacion_historial', '6',
   'Recomendación: 3 a 6 meses. El plazo final lo define la administración.');

-- Pisos: subsuelos -4 a -1, planta baja (0) y pisos 1 a 18
INSERT INTO pisos (numero, descripcion) VALUES
  (-4, 'Subsuelo 4'), (-3, 'Subsuelo 3'), (-2, 'Subsuelo 2'), (-1, 'Subsuelo 1'),
  (0, 'Planta baja'),
  (1, 'Piso 1'),  (2, 'Piso 2'),  (3, 'Piso 3'),  (4, 'Piso 4'),  (5, 'Piso 5'),
  (6, 'Piso 6'),  (7, 'Piso 7'),  (8, 'Piso 8'),  (9, 'Piso 9'),  (10, 'Piso 10'),
  (11, 'Piso 11'), (12, 'Piso 12'), (13, 'Piso 13'), (14, 'Piso 14'), (15, 'Piso 15'),
  (16, 'Piso 16'), (17, 'Piso 17'), (18, 'Piso 18');

-- Empresas (16) y la administración del edificio
-- Los nombres están tal como los dio la administración; la razón social
-- completa se actualiza cuando la confirmen (columna razon_social).
INSERT INTO empresas (nombre, tipo) VALUES
  ('Bustamante Fabara', 'empresa'),
  ('America Call Center S.A.', 'empresa'),
  ('Grupo Aries', 'empresa'),
  ('Recycob S.A.', 'empresa'),
  ('Esacontrol S.A.', 'empresa'),
  ('Esain S.A.', 'empresa'),
  ('Tecnoesa S.A.', 'empresa'),
  ('Vepagas EC S.A.', 'empresa'),
  ('Productos Paraíso del Ecuador C. I.', 'empresa'),
  ('BFS Ecuador S.A.', 'empresa'),
  ('Comply S.A.', 'empresa'),
  ('Milenio S.A.', 'empresa'),
  ('Seguiresa Cía. Ltda.', 'empresa'),
  ('Servicobranzas S.A.', 'empresa'),
  ('Valladares y Valladares', 'empresa'),
  ('Liserpe S.A.', 'empresa'),
  ('Administración del edificio', 'administracion');

-- Ubicación de cada empresa (piso 0 = planta baja, -1 = subsuelo 1)
INSERT INTO empresa_pisos (empresa_id, piso_id)
SELECT e.id, p.id
FROM (
  SELECT 'Bustamante Fabara' AS empresa, 18 AS piso UNION ALL
  SELECT 'Bustamante Fabara', 17 UNION ALL SELECT 'Bustamante Fabara', 16 UNION ALL
  SELECT 'Bustamante Fabara', 11 UNION ALL SELECT 'Bustamante Fabara', 10 UNION ALL
  SELECT 'Bustamante Fabara', 5  UNION ALL SELECT 'Bustamante Fabara', 4  UNION ALL
  SELECT 'America Call Center S.A.', 15 UNION ALL
  SELECT 'America Call Center S.A.', 3  UNION ALL SELECT 'America Call Center S.A.', 2 UNION ALL
  SELECT 'Grupo Aries', 14 UNION ALL
  SELECT 'Recycob S.A.', 13 UNION ALL SELECT 'Recycob S.A.', 12 UNION ALL
  SELECT 'Esacontrol S.A.', 9 UNION ALL
  SELECT 'Esain S.A.', 9 UNION ALL
  SELECT 'Tecnoesa S.A.', 9 UNION ALL
  SELECT 'Vepagas EC S.A.', 9 UNION ALL SELECT 'Vepagas EC S.A.', 8 UNION ALL
  SELECT 'Productos Paraíso del Ecuador C. I.', 7 UNION ALL
  SELECT 'Productos Paraíso del Ecuador C. I.', 6 UNION ALL
  SELECT 'BFS Ecuador S.A.', 5 UNION ALL
  SELECT 'Comply S.A.', -1 UNION ALL
  SELECT 'Milenio S.A.', -1 UNION ALL
  SELECT 'Seguiresa Cía. Ltda.', -1 UNION ALL
  SELECT 'Servicobranzas S.A.', -1 UNION ALL
  SELECT 'Administración del edificio', -1 UNION ALL
  SELECT 'Valladares y Valladares', 0 UNION ALL
  SELECT 'Liserpe S.A.', 0
) AS m
JOIN empresas e ON e.nombre = m.empresa
JOIN pisos    p ON p.numero = m.piso;

-- =====================================================================
-- CONSULTAS ÚTILES PARA EL BACKEND (referencia, no se ejecutan aquí)
-- =====================================================================
-- Visitas activas (sin salida) de todo el edificio:
--   SELECT v.id, vi.apellidos_nombres, e.nombre AS empresa, p.descripcion AS piso, v.fecha_entrada
--   FROM visitas v
--   JOIN visitantes vi ON vi.id = v.visitante_id
--   JOIN empresas e ON e.id = v.empresa_id
--   JOIN pisos p ON p.id = v.piso_id
--   WHERE v.fecha_salida IS NULL ORDER BY v.fecha_entrada;
--
-- Aviso de espacio de visitantes ocupado (vehículos dentro >= capacidad):
--   SELECT COUNT(*) >= (SELECT CAST(valor AS UNSIGNED) FROM configuracion
--                       WHERE clave = 'capacidad_espacio_visitantes') AS ocupado
--   FROM registros_vehiculos WHERE hora_salida IS NULL;
--
-- Reporte quincenal (últimos 15 días):
--   SELECT v.fecha_entrada, vi.tipo_documento, vi.documento, vi.apellidos_nombres,
--          p.descripcion AS piso, v.persona_autoriza, v.fecha_salida
--   FROM visitas v
--   JOIN visitantes vi ON vi.id = v.visitante_id
--   JOIN pisos p ON p.id = v.piso_id
--   WHERE v.fecha_entrada >= DATE_SUB(NOW(), INTERVAL 15 DAY)
--   ORDER BY v.fecha_entrada;
--
-- Conservación del historial (borrar lo anterior al plazo configurado):
--   DELETE FROM visitas
--   WHERE fecha_entrada < DATE_SUB(NOW(), INTERVAL
--     (SELECT CAST(valor AS UNSIGNED) FROM configuracion
--      WHERE clave = 'meses_conservacion_historial') MONTH);
-- =====================================================================
