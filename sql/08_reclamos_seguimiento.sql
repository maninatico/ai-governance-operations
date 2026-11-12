-- =====================================================================
-- 08. Reclamos: derivación, plazos y borrador de respuesta (Fase 8.5b y 8.5c)
-- La IA clasifica; la derivación la decide esta tabla fija. Los plazos se
-- calculan en horas hábiles (lunes a viernes de 8 a 17). Se puede correr más de una vez.
-- =====================================================================

-- 1. Tabla fija categoría -> área (la regla, no la IA)
CREATE TABLE IF NOT EXISTS negocio.areas_por_categoria (
    categoria text PRIMARY KEY,
    area      text NOT NULL
);
INSERT INTO negocio.areas_por_categoria (categoria, area) VALUES
    ('Entrega demorada',       'Logística'),
    ('Material dañado',        'Logística'),
    ('Faltante en la entrega', 'Logística'),
    ('Error de facturación',   'Administración'),
    ('Atención en sucursal',   'Ventas'),
    ('Otros',                  'Atención al cliente')
ON CONFLICT (categoria) DO NOTHING;

-- 2. Plazos y seguimiento
ALTER TABLE negocio.reclamos ADD COLUMN IF NOT EXISTS vence_primera_respuesta timestamp;   -- 24 horas hábiles
ALTER TABLE negocio.reclamos ADD COLUMN IF NOT EXISTS vence_resolucion        timestamp;   -- 5 días hábiles (45 horas)
ALTER TABLE negocio.reclamos ADD COLUMN IF NOT EXISTS aviso_enviado           boolean NOT NULL DEFAULT false;  -- aviso a las 16 horas hábiles
ALTER TABLE negocio.reclamos ADD COLUMN IF NOT EXISTS escalado                boolean NOT NULL DEFAULT false;  -- vencido y escalado al Jefe de Atención

-- 3. Borrador de respuesta (8.5c): lo redacta la IA con marcadores, lo aprueba una persona
ALTER TABLE negocio.reclamos ADD COLUMN IF NOT EXISTS respuesta_borrador text;
ALTER TABLE negocio.reclamos ADD COLUMN IF NOT EXISTS respuesta_estado   text;
ALTER TABLE negocio.reclamos DROP CONSTRAINT IF EXISTS reclamos_respuesta_estado_check;
ALTER TABLE negocio.reclamos ADD CONSTRAINT reclamos_respuesta_estado_check
    CHECK (respuesta_estado IS NULL OR respuesta_estado IN ('pendiente_aprobacion', 'aprobada', 'rechazada', 'enviada'));

-- 4. Permisos del flujo de reclamos
GRANT SELECT ON negocio.areas_por_categoria TO rol_flujo_reclamos;
GRANT EXECUTE ON FUNCTION control.sumar_horas_habiles(timestamp, numeric) TO rol_flujo_reclamos;

-- 5. El flujo de reclamos lee sus aprobaciones (8.5c, modo actualizar). Solo lectura.
GRANT SELECT ON control.aprobaciones TO rol_flujo_reclamos;
