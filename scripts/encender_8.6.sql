-- Fase 8.6. Enciende el monitoreo (flujo "8.6 Monitoreo") despues de pasar CA_8.6_PRUEBA (8 de 8 PASA, 08/11/2026).
-- El motivo queda escrito en el interruptor y en la auditoria. No toca GENERAL ni los demas flujos.
UPDATE control.interruptores
   SET activo = true, errores_seguidos = 0, cambiado = now(),
       cambiado_por = 'Jorge (Analista de Procesos)',
       motivo = 'Monitoreo probado: CA_8.6_PRUEBA 8 de 8 PASA (08/11/2026)'
 WHERE flujo = '8.6 Monitoreo';

INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
VALUES ('Jorge (Analista de Procesos)', 'interruptor encendido', 'control.interruptores: 8.6 Monitoreo',
        jsonb_build_object('flujo', '8.6 Monitoreo', 'activo', true),
        'Monitoreo probado: CA_8.6_PRUEBA 8 de 8 PASA (08/11/2026)');

SELECT flujo, activo, cambiado_por, motivo FROM control.interruptores ORDER BY flujo;
