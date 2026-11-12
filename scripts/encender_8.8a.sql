-- Fase 8.8a. Enciende la cola de revision humana (flujo "8.8 Desenmascarador y cola") despues de pasar CA_8.8a_PRUEBA (8 de 8 PASA, 09/11/2026) y SQL 13 (25 de 25 en la base de la nube).
-- Este interruptor cubre A13 y A14. Hoy solo existe A14 (el formulario de la cola); el desenmascarador (8.8b) se construye despues.
-- El motivo queda escrito en el interruptor y en la auditoria. No toca GENERAL ni los demas flujos.
UPDATE control.interruptores
   SET activo = true, errores_seguidos = 0, cambiado = now(),
       cambiado_por = 'Jorge (Analista de Procesos)',
       motivo = 'Cola de revision probada: CA_8.8a_PRUEBA 8 de 8 PASA y SQL 13 25 de 25 (09/11/2026)'
 WHERE flujo = '8.8 Desenmascarador y cola';

INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
VALUES ('Jorge (Analista de Procesos)', 'interruptor encendido', 'control.interruptores: 8.8 Desenmascarador y cola',
        jsonb_build_object('flujo', '8.8 Desenmascarador y cola', 'activo', true),
        'Cola de revision probada: CA_8.8a_PRUEBA 8 de 8 PASA y SQL 13 25 de 25 (09/11/2026)');

SELECT flujo, activo, cambiado_por, motivo FROM control.interruptores ORDER BY flujo;
