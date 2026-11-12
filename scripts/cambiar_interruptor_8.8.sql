-- Fase 9. Apaga o enciende el interruptor "8.8 Desenmascarador y cola" para probar la falla segura.
-- Uso, desde la carpeta del proyecto:
--   Apagar:    docker exec -i cumbre_andina_db sh -c 'psql -U "$POSTGRES_USER" -d cumbre_andina -v ON_ERROR_STOP=1 -v estado=false' < scripts/cambiar_interruptor_8.8.sql
--   Encender:  docker exec -i cumbre_andina_db sh -c 'psql -U "$POSTGRES_USER" -d cumbre_andina -v ON_ERROR_STOP=1 -v estado=true'  < scripts/cambiar_interruptor_8.8.sql
-- Queda escrito en el interruptor y en la auditoria. No toca GENERAL ni los demas flujos.
UPDATE control.interruptores
   SET activo = :estado, errores_seguidos = 0, cambiado = now(),
       cambiado_por = 'Jorge (Analista de Procesos)',
       motivo = CASE WHEN :estado THEN 'Reencendido al terminar la prueba de falla segura de la Fase 9 (09/11/2026)'
                     ELSE 'Apagado a proposito para la prueba de falla segura de la Fase 9 (09/11/2026)' END
 WHERE flujo = '8.8 Desenmascarador y cola';

INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
VALUES ('Jorge (Analista de Procesos)', CASE WHEN :estado THEN 'interruptor encendido' ELSE 'interruptor apagado' END,
        'control.interruptores: 8.8 Desenmascarador y cola',
        jsonb_build_object('flujo', '8.8 Desenmascarador y cola', 'activo', :estado),
        'Prueba de falla segura de la Fase 9 (09/11/2026)');

SELECT flujo, activo, cambiado_por, motivo FROM control.interruptores WHERE flujo IN ('GENERAL', '8.8 Desenmascarador y cola') ORDER BY flujo;
