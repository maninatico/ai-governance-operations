-- =====================================================================
-- 07. Proveedores monotributistas (Fase 8.4b)
-- Un monotributista es persona humana y emite Factura C, sin IVA.
-- Se amplía la base para aceptarlo y se cargan 2 proveedores de prueba.
-- Datos ficticios. Se puede correr más de una vez.
-- =====================================================================

-- 1. Tipos de comprobante: se suman los C
ALTER TABLE negocio.comprobantes DROP CONSTRAINT IF EXISTS comprobantes_tipo_comprobante_check;
ALTER TABLE negocio.comprobantes ADD CONSTRAINT comprobantes_tipo_comprobante_check CHECK (tipo_comprobante IN
    ('Factura A', 'Nota de crédito A', 'Nota de débito A', 'Factura C', 'Nota de crédito C', 'Nota de débito C'));

-- 2. Alícuota 0 solo para monotributistas
ALTER TABLE negocio.proveedores ADD COLUMN IF NOT EXISTS condicion_iva text NOT NULL DEFAULT 'Responsable Inscripto';
ALTER TABLE negocio.proveedores DROP CONSTRAINT IF EXISTS proveedores_condicion_iva_check;
ALTER TABLE negocio.proveedores ADD CONSTRAINT proveedores_condicion_iva_check
    CHECK (condicion_iva IN ('Responsable Inscripto', 'Monotributo'));
ALTER TABLE negocio.proveedores DROP CONSTRAINT IF EXISTS proveedores_alicuota_iva_check;
ALTER TABLE negocio.proveedores ADD CONSTRAINT proveedores_alicuota_iva_check CHECK (
    (condicion_iva = 'Responsable Inscripto' AND alicuota_iva IN (0.21, 0.105)) OR
    (condicion_iva = 'Monotributo' AND alicuota_iva = 0 AND tipo_persona = 'humana'));

-- 3. Un comprobante C no lleva IVA; uno A sí
ALTER TABLE negocio.comprobantes DROP CONSTRAINT IF EXISTS iva_segun_letra;
ALTER TABLE negocio.comprobantes ADD CONSTRAINT iva_segun_letra CHECK (
    (tipo_comprobante LIKE '% C' AND iva = 0 AND alicuota_iva = 0) OR
    (tipo_comprobante LIKE '% A' AND alicuota_iva IN (0.21, 0.105)));

-- 4. Proveedores de prueba. Nombre y CUIT (contiene el DNI) solo en la bóveda
INSERT INTO negocio.proveedores (proveedor_id, tipo_persona, razon_social, cuit, rubro, alicuota_iva,
                                 condicion_pago_dias, activo, condicion_iva) VALUES
    ('PRV-121', 'humana', NULL, NULL, 'Sanitarios', 0, 30, true, 'Monotributo'),
    ('PRV-122', 'humana', NULL, NULL, 'Pinturas',   0, 30, true, 'Monotributo')
ON CONFLICT (proveedor_id) DO NOTHING;

INSERT INTO boveda.proveedores_personas (proveedor_id, nombre, cuit) VALUES
    ('PRV-121', 'Tomás Ezequiel Barrionuevo (ficticio)', '20-21524864-0'),
    ('PRV-122', 'Valeria Soledad Quintana (ficticia)',   '27-36422304-3')
ON CONFLICT (proveedor_id) DO NOTHING;

INSERT INTO boveda.cuentas_bancarias (proveedor_id, banco, cbu, vigente_desde, verificado_por, canal_verificacion)
SELECT v.* FROM (VALUES
    ('PRV-121', 'Banco de la Nación', '0113822557617344074725', DATE '2026-09-01', 'Gerente de Administración', 'Llamada al teléfono del legajo'),
    ('PRV-122', 'Credicoop',          '1918123124042492728569', DATE '2026-09-01', 'Gerente de Administración', 'Llamada al teléfono del legajo')
) AS v(proveedor_id, banco, cbu, vigente_desde, verificado_por, canal_verificacion)
WHERE NOT EXISTS (SELECT 1 FROM boveda.cuentas_bancarias c WHERE c.proveedor_id = v.proveedor_id);

-- 5. Órdenes de compra abiertas para sus facturas
INSERT INTO negocio.ordenes_compra (oc_id, proveedor_id, fecha_oc, monto_neto_oc, estado_oc) VALUES
    ('OC-L0901', 'PRV-121', DATE '2026-10-05', 412500.00, 'Abierta'),
    ('OC-L0902', 'PRV-122', DATE '2026-10-07', 187340.00, 'Abierta')
ON CONFLICT (oc_id) DO NOTHING;
