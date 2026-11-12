-- =====================================================================
-- Fase 7. Carga inicial del inventario (03_Catalogo_Inventario_y_Riesgo.md) e interruptores
-- Se puede volver a correr: actualiza si ya existe.
-- =====================================================================
INSERT INTO control.automatizaciones (automatizacion_id, nombre, proceso, usa_ia, nivel, riesgo, dueno, version, estado) VALUES
 ('A01', 'Registro de eventos', 'P0', 'No', 'L0', 'Bajo', 'Resp. Sistemas', '0.1', 'A construir'),
 ('A02', 'Bóveda y seudonimización', 'P0', 'Solo local', 'L0', 'Alto', 'Resp. Sistemas', '0.1', 'A construir'),
 ('A03', 'Motor de políticas y aprobaciones', 'P0', 'No', 'L0', 'Alto', 'Resp. Sistemas', '0.1', 'A construir'),
 ('A04', 'Recepción y clasificación de comprobantes', 'P1', 'Sí', 'L0', 'Bajo', 'Gte. Administración', '0.1', 'A construir'),
 ('A05', 'Extracción y validación de facturas', 'P1', 'Sí', 'L2', 'Medio', 'Gte. Administración', '0.1', 'A construir'),
 ('A06', 'Detección de cambio de cuenta bancaria', 'P0 / P1', 'Sí', 'L4', 'Alto', 'Gte. Administración', '0.1', 'A construir'),
 ('A07', 'Aprobación de factura para pago', 'P1', 'No', 'L3', 'Alto', 'Gte. Administración', '0.1', 'A construir'),
 ('A08', 'Recepción y clasificación de reclamos', 'P2', 'Sí', 'L0', 'Medio', 'Jefe de Atención', '0.1', 'A construir'),
 ('A09', 'Derivación y seguimiento de plazos', 'P2', 'No', 'L1', 'Medio', 'Jefe de Atención', '0.1', 'A construir'),
 ('A10', 'Respuesta sugerida al cliente', 'P2', 'Sí', 'L3', 'Medio', 'Jefe de Atención', '0.1', 'A construir'),
 ('A11', 'Monitoreo, cortacircuitos e interruptor', 'P0', 'No', 'L0', 'Medio', 'Resp. Sistemas', '0.1', 'A construir'),
 ('A12', 'Reporte semanal', 'P0', 'Sí', 'L1', 'Bajo', 'Analista de Procesos', '0.1', 'A construir'),
 ('A13', 'Desenmascarador controlado', 'P0', 'No', 'L1 / L3', 'Alto', 'Gte. Administración', '0.1', 'A construir'),
 ('A14', 'Cola de revisión humana', 'P0 / P1 / P2', 'No', 'L0 (deriva; decide una persona)', 'Medio', 'Analista de Procesos', '0.1', 'A construir')
ON CONFLICT (automatizacion_id) DO UPDATE SET
  nombre = EXCLUDED.nombre, proceso = EXCLUDED.proceso, usa_ia = EXCLUDED.usa_ia, nivel = EXCLUDED.nivel,
  riesgo = EXCLUDED.riesgo, dueno = EXCLUDED.dueno, version = EXCLUDED.version, estado = EXCLUDED.estado,
  actualizado = now();

-- Interruptores: uno por flujo de la Fase 8 y uno general. Arrancan apagados hasta pasar las pruebas.
INSERT INTO control.interruptores (flujo, activo, cambiado_por, motivo) VALUES
 ('GENERAL', false, 'carga inicial', 'Sin flujos probados todavía'),
 ('8.1 Registro de eventos', false, 'carga inicial', 'A construir'),
 ('8.2 Bóveda y seudonimización', false, 'carga inicial', 'A construir'),
 ('8.3 Motor de políticas y aprobaciones', false, 'carga inicial', 'A construir'),
 ('8.4 Facturas', false, 'carga inicial', 'A construir'),
 ('8.5 Reclamos', false, 'carga inicial', 'A construir'),
 ('8.6 Monitoreo', false, 'carga inicial', 'A construir'),
 ('8.7 Reporte semanal', false, 'carga inicial', 'A construir'),
 ('8.8 Desenmascarador y cola', false, 'carga inicial', 'A construir')
ON CONFLICT (flujo) DO NOTHING;
