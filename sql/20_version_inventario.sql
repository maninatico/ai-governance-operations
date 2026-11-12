BEGIN;
SELECT automatizacion_id, version, estado FROM control.automatizaciones ORDER BY automatizacion_id;
UPDATE control.automatizaciones SET version = '1.0', actualizado = now()
WHERE automatizacion_id IN ('A01','A02','A03','A04','A05','A06','A07','A08','A09','A10','A11','A12','A13','A14') AND version = '0.1';
SELECT automatizacion_id, version, estado FROM control.automatizaciones ORDER BY automatizacion_id;
COMMIT;
