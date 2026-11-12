-- CA84b_Validar_y_registrar. Entrada: el comprobante leído por código (JSON). Una sola sentencia: valida contra la base y registra.
WITH e AS (SELECT $1::jsonb AS j),
v AS (
  SELECT j->>'comprobante_id' AS id, j->>'proveedor_id' AS prov, j->>'tipo' AS tipo,
         j->>'punto_venta' AS pv, j->>'numero' AS nro, (j->>'fecha')::date AS fecha,
         (j->>'fecha_recepcion')::date AS recepcion, j->>'fuente_lectura' AS fuente, j->>'cae' AS cae,
         nullif(j->>'oc_id', '') AS oc, (j->>'neto')::numeric AS neto, (j->>'alicuota')::numeric AS alicuota,
         (j->>'iva')::numeric AS iva, (j->>'total')::numeric AS total,
         ARRAY(SELECT jsonb_array_elements_text(coalesce(j->'motivos', '[]'))) AS motivos_lectura,
         coalesce(j->>'prefijo', '') AS prefijo   -- pruebas: 'PRUEBA-<corrida>-'. Solo se comparan con su misma corrida
  FROM e),
oc AS (SELECT o.* FROM negocio.ordenes_compra o JOIN v ON o.oc_id = v.oc),
dup AS (   -- posible duplicada: otro comprobante del mismo proveedor con el mismo número, o con la misma fecha y total, o la misma OC
  SELECT c.comprobante_id,
         CASE WHEN c.punto_venta = v.pv AND c.numero = v.nro THEN 'el mismo número'
              WHEN c.fecha_emision = v.fecha AND c.total = v.total THEN 'la misma fecha y el mismo total'
              ELSE 'la misma orden de compra' END AS como
  FROM negocio.comprobantes c JOIN v ON c.proveedor_id = v.prov AND c.comprobante_id <> v.id
  WHERE c.comprobante_id LIKE v.prefijo || '%' AND (v.prefijo <> '' OR c.comprobante_id NOT LIKE 'PRUEBA%')
    AND ((c.punto_venta = v.pv AND c.numero = v.nro) OR (c.fecha_emision = v.fecha AND c.total = v.total)
     OR (v.oc IS NOT NULL AND c.oc_id = v.oc AND c.tipo_comprobante LIKE 'Factura%' AND v.tipo LIKE 'Factura%'))
  ORDER BY 2 LIMIT 1),
m AS (
  SELECT v.*, array_remove(v.motivos_lectura || ARRAY[
      CASE WHEN v.tipo LIKE 'Factura%' AND v.oc IS NULL THEN 'Factura sin orden de compra' END,
      CASE WHEN v.oc IS NOT NULL AND NOT EXISTS (SELECT 1 FROM oc) THEN 'La orden de compra ' || v.oc || ' no existe' END,
      (SELECT 'La orden de compra ' || oc.oc_id || ' es de otro proveedor' FROM oc WHERE oc.proveedor_id <> v.prov),
      (SELECT 'La orden de compra ' || oc.oc_id || ' está cerrada' FROM oc WHERE oc.estado_oc <> 'Abierta'),
      (SELECT format('El neto difiere %s%% de la orden de compra (tolerancia 2%%)', round(abs(v.neto - oc.monto_neto_oc) / oc.monto_neto_oc * 100, 1))
         FROM oc WHERE abs(v.neto - oc.monto_neto_oc) > 0.02 * oc.monto_neto_oc),
      (SELECT 'Posible duplicada de ' || dup.comprobante_id || ': ' || dup.como FROM dup)
    ]::text[], NULL) AS motivos,
    EXISTS (SELECT 1 FROM dup) AS posible_duplicada
  FROM v),
ins AS (
  INSERT INTO negocio.comprobantes (comprobante_id, proveedor_id, tipo_comprobante, punto_venta, numero, fecha_emision,
      fecha_recepcion, canal, fuente_lectura, cae, oc_id, neto, alicuota_iva, iva, total, con_error_datos, estado, origen)
  SELECT id, prov, tipo, pv, nro, fecha, recepcion, 'PDF por correo', fuente, cae,
         CASE WHEN EXISTS (SELECT 1 FROM oc WHERE oc.proveedor_id = m.prov) THEN oc END,
         neto, alicuota, iva, total, cardinality(motivos) > 0,
         CASE WHEN cardinality(motivos) = 0 THEN 'Recibida' ELSE 'En cola de revisión' END, 'lote_prueba'
  FROM m
  ON CONFLICT (comprobante_id) DO NOTHING
  RETURNING comprobante_id, estado),
cola AS (
  INSERT INTO control.cola_revision (origen, automatizacion_id, documento_id, motivo, prioridad)
  SELECT 'facturas', 'A05', ins.comprobante_id, array_to_string(m.motivos, '; '),
         CASE WHEN m.posible_duplicada THEN 'alta' ELSE 'media' END
  FROM ins, m WHERE ins.estado = 'En cola de revisión')
SELECT m.id AS comprobante_id,
       coalesce(ins.estado, 'Ya registrado antes') AS estado,
       (ins.comprobante_id IS NOT NULL) AS registrado,
       CASE WHEN ins.comprobante_id IS NULL THEN '{}'::text[] ELSE m.motivos END AS motivos,
       ins.comprobante_id IS NOT NULL AND m.posible_duplicada AS posible_duplicada
FROM m LEFT JOIN ins ON true;
