-- Fase 8.7. Enciende el reporte semanal (flujo "8.7 Reporte semanal") despues de pasar CA_8.7_PRUEBA (6 de 6 PASA + correo verificado, 08/11/2026).
-- El motivo queda escrito en el interruptor y en la auditoria. No toca GENERAL ni los demas flujos.
UPDATE control.interruptores
   SET activo = true, errores_seguidos = 0, cambiado = now(),
       cambiado_por = 'Jorge (Analista de Procesos)',
       motivo = 'Reporte semanal probado: CA_8.7_PRUEBA 6 de 6 PASA y correo verificado (08/11/2026)'
 WHERE flujo = '8.7 Reporte semanal';

INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
VALUES ('Jorge (Analista de Procesos)', 'interruptor encendido', 'control.interruptores: 8.7 Reporte semanal',
        jsonb_build_object('flujo', '8.7 Reporte semanal', 'activo', true),
        'Reporte semanal probado: CA_8.7_PRUEBA 6 de 6 PASA y correo verificado (08/11/2026)');

SELECT flujo, activo, cambiado_por, motivo FROM control.interruptores ORDER BY flujo;
