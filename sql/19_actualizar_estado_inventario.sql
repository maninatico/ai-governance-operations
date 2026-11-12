-- =====================================================================
-- Fase 11. El inventario seguia con estado 'A construir' (carga inicial de sql/04).
-- Estados permitidos por la tabla: A construir, En prueba, Activa, Apagada, Retirada.
-- Criterio: Activa = su interruptor esta encendido (8.4 a 8.8, A04 a A14).
--           En prueba = construida y probada, pero su interruptor nunca se encendio (A01 a A03).
-- Solo cambia estado y actualizado. Una sola transaccion: antes, cambio, despues.
-- =====================================================================
BEGIN;

SELECT automatizacion_id, nombre, estado FROM control.automatizaciones ORDER BY automatizacion_id;

UPDATE control.automatizaciones
   SET estado = 'En prueba', actualizado = now()
 WHERE automatizacion_id IN ('A01','A02','A03') AND estado = 'A construir';

UPDATE control.automatizaciones
   SET estado = 'Activa', actualizado = now()
 WHERE automatizacion_id IN ('A04','A05','A06','A07','A08','A09','A10','A11','A12','A13','A14') AND estado = 'A construir';

SELECT automatizacion_id, nombre, estado FROM control.automatizaciones ORDER BY automatizacion_id;

COMMIT;
