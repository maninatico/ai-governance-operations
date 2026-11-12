-- =====================================================================
-- Fase 7. Esquema de base de datos
-- Proyecto: Gobernanza de IA en Operaciones (Materiales Cumbre Andina, caso ficticio)
-- PostgreSQL 14 o superior. Crear antes la base:  CREATE DATABASE cumbre_andina;
-- Tres zonas: boveda (datos personales reales), negocio (sin datos personales),
-- control (gobernanza). Las vistas para Power BI van en reportes (03_vistas.sql).
-- =====================================================================

-- Hora de Buenos Aires para now() y las marcas de tiempo (el histórico está en hora local)
DO $$ BEGIN EXECUTE format('ALTER DATABASE %I SET timezone TO %L', current_database(), 'America/Argentina/Buenos_Aires'); END $$;
SET timezone TO 'America/Argentina/Buenos_Aires';

CREATE SCHEMA IF NOT EXISTS boveda;
CREATE SCHEMA IF NOT EXISTS negocio;
CREATE SCHEMA IF NOT EXISTS control;
CREATE SCHEMA IF NOT EXISTS reportes;

-- ---------------------------------------------------------------------
-- ZONA 2. NEGOCIO (sin datos personales)
-- ---------------------------------------------------------------------

-- Maestro de proveedores. tipo_persona decide dónde viven CUIT y nombre:
--   juridica (empresa): en esta tabla, no es dato personal.
--   humana (monotributista): en boveda.proveedores_personas, porque su CUIT
--   contiene el DNI y su razón social es su nombre.
CREATE TABLE negocio.proveedores (
    proveedor_id        text PRIMARY KEY,
    tipo_persona        text NOT NULL CHECK (tipo_persona IN ('juridica', 'humana')),
    razon_social        text,
    cuit                text UNIQUE CHECK (cuit ~ '^\d{2}-\d{8}-\d$'),
    rubro               text NOT NULL,
    alicuota_iva        numeric(5,3) NOT NULL CHECK (alicuota_iva IN (0.21, 0.105)),
    condicion_pago_dias int NOT NULL CHECK (condicion_pago_dias > 0),
    activo              boolean NOT NULL DEFAULT true,
    CONSTRAINT datos_segun_tipo CHECK (
        (tipo_persona = 'juridica' AND razon_social IS NOT NULL AND cuit IS NOT NULL) OR
        (tipo_persona = 'humana'   AND razon_social IS NULL     AND cuit IS NULL))
);

-- Clientes: solo el ID y datos comerciales. Los datos personales están en la bóveda.
CREATE TABLE negocio.clientes (
    cliente_id        text PRIMARY KEY,
    tipo_cliente      text NOT NULL CHECK (tipo_cliente IN ('Particular', 'Contratista', 'Constructora')),
    sucursal_habitual text NOT NULL
);

CREATE TABLE negocio.ordenes_compra (
    oc_id         text PRIMARY KEY,
    proveedor_id  text NOT NULL REFERENCES negocio.proveedores,
    fecha_oc      date NOT NULL,
    monto_neto_oc numeric(14,2) NOT NULL CHECK (monto_neto_oc > 0),
    estado_oc     text NOT NULL CHECK (estado_oc IN ('Abierta', 'Cerrada'))
);

-- Comprobantes de proveedores (facturas y notas). Guarda de dónde salió cada dato.
CREATE TABLE negocio.comprobantes (
    comprobante_id   text PRIMARY KEY,
    proveedor_id     text NOT NULL REFERENCES negocio.proveedores,
    tipo_comprobante text NOT NULL CHECK (tipo_comprobante IN ('Factura A', 'Nota de crédito A', 'Nota de débito A')),
    punto_venta      text NOT NULL,
    numero           text NOT NULL,
    fecha_emision    date NOT NULL,
    fecha_recepcion  date NOT NULL,
    fecha_registro   date,
    canal            text NOT NULL CHECK (canal IN ('PDF por correo', 'Papel escaneado', 'Portal del proveedor')),
    fuente_lectura   text CHECK (fuente_lectura IN ('manual', 'texto', 'qr', 'ocr')),
    cae              text,
    oc_id            text REFERENCES negocio.ordenes_compra,
    neto             numeric(14,2) NOT NULL,
    alicuota_iva     numeric(5,3) NOT NULL,
    iva              numeric(14,2) NOT NULL,
    total            numeric(14,2) NOT NULL,
    total_original   numeric(14,2),
    minutos_proceso  numeric(6,1),           -- minutos de trabajo humano (carga manual o revisión)
    con_error_datos  boolean,                -- tuvo algún dato mal (CUIT, fecha, razón social o monto)
    es_duplicada     boolean NOT NULL DEFAULT false,
    duplicada_de     text REFERENCES negocio.comprobantes,
    detectada_manual boolean,                -- solo duplicadas del histórico: si el proceso manual la frenó
    estado           text NOT NULL CHECK (estado IN ('Recibida', 'En cola de revisión', 'Registrada',
                         'Aprobada para pago', 'Pagada', 'En espera', 'Rechazada por duplicada', 'Bloqueada')),
    origen           text NOT NULL CHECK (origen IN ('historico', 'lote_prueba')),
    CONSTRAINT registro_posterior CHECK (fecha_registro IS NULL OR fecha_registro >= fecha_recepcion),
    CONSTRAINT duplicada_coherente CHECK (es_duplicada = (duplicada_de IS NOT NULL))
);
CREATE INDEX ix_comprobantes_clave ON negocio.comprobantes (proveedor_id, punto_venta, numero, tipo_comprobante);
CREATE INDEX ix_comprobantes_monto ON negocio.comprobantes (proveedor_id, fecha_emision, total);

-- Reclamos: el texto se guarda solo enmascarado.
CREATE TABLE negocio.reclamos (
    reclamo_id                   text PRIMARY KEY,
    cliente_id                   text REFERENCES negocio.clientes,
    sucursal                     text NOT NULL,
    canal                        text NOT NULL CHECK (canal IN ('WhatsApp', 'Correo', 'Sucursal')),
    fecha_hora_ingreso           timestamp NOT NULL,
    texto_enmascarado            text NOT NULL,
    categoria                    text,
    urgencia                     text CHECK (urgencia IN ('baja', 'media', 'alta')),
    es_pedido_datos_personales   boolean NOT NULL DEFAULT false,
    area_derivada                text,
    fecha_hora_primera_respuesta timestamp,
    fecha_hora_cierre            timestamp,
    reabierto                    boolean NOT NULL DEFAULT false,
    derivacion_correcta          boolean,    -- medido por auditoría de una muestra; vacío si no se auditó
    agente                       text,
    origen                       text NOT NULL CHECK (origen IN ('historico', 'lote_prueba')),
    CONSTRAINT respuesta_posterior CHECK (fecha_hora_primera_respuesta IS NULL OR fecha_hora_primera_respuesta >= fecha_hora_ingreso),
    CONSTRAINT cierre_posterior CHECK (fecha_hora_cierre IS NULL OR fecha_hora_cierre >= fecha_hora_ingreso)
);

-- ---------------------------------------------------------------------
-- ZONA 1. BÓVEDA (datos personales reales; acceso mínimo, ver 02_roles.sql)
-- ---------------------------------------------------------------------

CREATE TABLE boveda.clientes_datos (
    cliente_id text PRIMARY KEY REFERENCES negocio.clientes,
    nombre     text NOT NULL,
    apellido   text NOT NULL,
    dni        text NOT NULL,          -- sin UNIQUE: un DNI repetido es un caso para revisión, no un error de carga
    telefono   text,
    email      text,
    direccion  text,
    localidad  text,
    revisar_dni boolean NOT NULL DEFAULT false
);
CREATE INDEX ix_clientes_dni ON boveda.clientes_datos (dni);

-- Proveedores persona humana (monotributistas): su CUIT y su nombre son datos personales.
CREATE TABLE boveda.proveedores_personas (
    proveedor_id text PRIMARY KEY REFERENCES negocio.proveedores,
    nombre       text NOT NULL,
    cuit         text NOT NULL UNIQUE CHECK (cuit ~ '^\d{2}-\d{8}-\d$')
);

-- CBU de cada proveedor. Nunca lo modifica una automatización (L4).
-- Un cambio se guarda como fila nueva: la anterior se cierra con vigente_hasta.
CREATE TABLE boveda.cuentas_bancarias (
    cuenta_id       bigserial PRIMARY KEY,
    proveedor_id    text NOT NULL REFERENCES negocio.proveedores,
    banco           text NOT NULL,
    cbu             text NOT NULL CHECK (cbu ~ '^\d{22}$'),
    vigente_desde   date NOT NULL,
    vigente_hasta   date,
    verificado_por  text NOT NULL,
    canal_verificacion text NOT NULL,   -- distinto del canal por el que se pidió el cambio
    CONSTRAINT vigencia_valida CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde)
);
CREATE UNIQUE INDEX ux_una_cuenta_vigente ON boveda.cuentas_bancarias (proveedor_id) WHERE vigente_hasta IS NULL;

-- Correspondencia entre marcador ([DNI_1]) y dato real, por documento.
CREATE TABLE boveda.marcadores (
    documento_id text NOT NULL,
    marcador     text NOT NULL CHECK (marcador ~ '^\[[A-Z]+_\d+\]$'),
    tipo         text NOT NULL CHECK (tipo IN ('NOMBRE', 'DNI', 'CUIT', 'TEL', 'EMAIL', 'DIRECCION', 'CBU')),
    valor_real   text NOT NULL,
    creado       timestamp NOT NULL DEFAULT now(),
    PRIMARY KEY (documento_id, marcador)
);

-- ---------------------------------------------------------------------
-- ZONA 3. CONTROL (gobernanza)
-- ---------------------------------------------------------------------

-- Inventario de automatizaciones A01 a A14 (Fase 2).
CREATE TABLE control.automatizaciones (
    automatizacion_id text PRIMARY KEY CHECK (automatizacion_id ~ '^A\d{2}$'),
    nombre      text NOT NULL,
    proceso     text NOT NULL,
    usa_ia      text NOT NULL,
    nivel       text NOT NULL,
    riesgo      text NOT NULL CHECK (riesgo IN ('Bajo', 'Medio', 'Alto')),
    dueno       text NOT NULL,
    version     text NOT NULL,
    estado      text NOT NULL CHECK (estado IN ('A construir', 'En prueba', 'Activa', 'Apagada', 'Retirada')),
    modelo_ia   text,
    actualizado timestamp NOT NULL DEFAULT now()
);

-- Cada corrida de cada automatización (A01).
CREATE TABLE control.ejecuciones (
    ejecucion_id        bigserial PRIMARY KEY,
    automatizacion_id   text NOT NULL REFERENCES control.automatizaciones,
    documento_id        text,
    inicio              timestamp NOT NULL,
    fin                 timestamp,
    estado              text NOT NULL CHECK (estado IN ('ok', 'error', 'derivado_a_cola', 'bloqueado', 'reintento')),
    intervencion_humana boolean NOT NULL DEFAULT false,
    modelo_ia           text,
    tokens_entrada      int,
    tokens_salida       int,
    costo_usd           numeric(10,6) NOT NULL DEFAULT 0,
    detalle_error       text,
    CONSTRAINT fin_posterior CHECK (fin IS NULL OR fin >= inicio)
);
CREATE INDEX ix_ejecuciones_auto_fecha ON control.ejecuciones (automatizacion_id, inicio);

-- Registro de auditoría: solo se agrega. Un trigger impide editar o borrar.
CREATE TABLE control.auditoria (
    auditoria_id bigserial PRIMARY KEY,
    momento      timestamp NOT NULL DEFAULT now(),
    actor        text NOT NULL,          -- persona o automatización
    accion       text NOT NULL,
    objeto       text NOT NULL,          -- tabla e ID afectado
    detalle      jsonb,
    motivo       text
);
CREATE FUNCTION control.auditoria_inmutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'El registro de auditoría no se puede modificar ni borrar';
END $$;
CREATE TRIGGER tg_auditoria_inmutable BEFORE UPDATE OR DELETE ON control.auditoria
    FOR EACH ROW EXECUTE FUNCTION control.auditoria_inmutable();
CREATE TRIGGER tg_auditoria_sin_truncate BEFORE TRUNCATE ON control.auditoria
    FOR EACH STATEMENT EXECUTE FUNCTION control.auditoria_inmutable();

-- Aprobaciones humanas (A03, A07). El silencio nunca es un sí: sin decisión, no avanza.
CREATE TABLE control.aprobaciones (
    aprobacion_id   bigserial PRIMARY KEY,
    automatizacion_id text NOT NULL REFERENCES control.automatizaciones,
    objeto          text NOT NULL,
    accion          text NOT NULL,
    nivel           text NOT NULL CHECK (nivel IN ('L3', 'L3 + doble control')),
    aprobador       text NOT NULL,
    segundo_aprobador text,
    pedido          timestamp NOT NULL DEFAULT now(),
    vence           timestamp NOT NULL,
    decision        text CHECK (decision IN ('aprobado', 'rechazado')),
    decidido        timestamp,
    escalado_a      text,
    motivo          text,
    CONSTRAINT decision_completa CHECK ((decision IS NULL) = (decidido IS NULL)),
    CONSTRAINT doble_control CHECK (nivel <> 'L3 + doble control' OR decision IS DISTINCT FROM 'aprobado' OR segundo_aprobador IS NOT NULL)
);

-- Cola de revisión humana (A14). Todo caso tiene motivo escrito.
CREATE TABLE control.cola_revision (
    caso_id      bigserial PRIMARY KEY,
    origen       text NOT NULL CHECK (origen IN ('facturas', 'reclamos', 'seguridad')),
    automatizacion_id text NOT NULL REFERENCES control.automatizaciones,
    documento_id text NOT NULL,
    motivo       text NOT NULL,
    prioridad    text NOT NULL DEFAULT 'media' CHECK (prioridad IN ('baja', 'media', 'alta')),
    ingreso      timestamp NOT NULL DEFAULT now(),
    asignado_a   text,
    estado       text NOT NULL DEFAULT 'pendiente' CHECK (estado IN ('pendiente', 'en revisión', 'resuelto')),
    decision     text,
    resuelto_por text,
    resuelto     timestamp,
    CONSTRAINT resolucion_completa CHECK (estado <> 'resuelto' OR (decision IS NOT NULL AND resuelto_por IS NOT NULL AND resuelto IS NOT NULL))
);

-- Cada vez que alguien vio un dato real (A13).
CREATE TABLE control.reidentificaciones (
    reidentificacion_id bigserial PRIMARY KEY,
    momento      timestamp NOT NULL DEFAULT now(),
    solicitante  text NOT NULL,
    documento_id text NOT NULL,
    marcador     text,
    tipo_uso     text NOT NULL CHECK (tipo_uso IN ('flujo aprobado', 'consulta manual')),
    motivo       text NOT NULL,
    aprobado_por text,
    CONSTRAINT manual_aprobada CHECK (tipo_uso <> 'consulta manual' OR aprobado_por IS NOT NULL)
);

-- Incidentes (Fase 3, política 5).
CREATE TABLE control.incidentes (
    incidente_id bigserial PRIMARY KEY,
    severidad    text NOT NULL CHECK (severidad IN ('S1', 'S2', 'S3')),
    descripcion  text NOT NULL,
    automatizacion_id text REFERENCES control.automatizaciones,
    ocurrido     timestamp,
    detectado    timestamp NOT NULL,
    contenido    timestamp,
    resuelto     timestamp,
    causa        text,
    acciones     text,
    datos_personales_involucrados boolean NOT NULL DEFAULT false
);

-- Interruptores por flujo y general (A11).
CREATE TABLE control.interruptores (
    flujo            text PRIMARY KEY,   -- 'GENERAL' apaga todo
    activo           boolean NOT NULL DEFAULT true,
    errores_seguidos int NOT NULL DEFAULT 0,
    limite_errores   int NOT NULL DEFAULT 3,
    cambiado         timestamp NOT NULL DEFAULT now(),
    cambiado_por     text NOT NULL,
    motivo           text
);
