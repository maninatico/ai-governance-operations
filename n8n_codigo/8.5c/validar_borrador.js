// El borrador solo pasa si no tiene datos personales, no promete nada y usa solo marcadores del reclamo.
const r = $('CA85c_Leer_reclamo').first().json;
const b = String($input.first().json.borrador || '').trim();
const motivos = [];
if (!b) motivos.push('La IA no devolvió un borrador');
const marcasReclamo = new Set(String(r.texto_enmascarado || '').match(/\[[A-Z]+_\d+\]/g) || []);
const marcasBorrador = b.match(/\[[A-Z]+_\d+\]/g) || [];
const ajenas = marcasBorrador.filter((m) => !marcasReclamo.has(m));
if (ajenas.length) motivos.push('Usa marcadores que no están en el reclamo: ' + [...new Set(ajenas)].join(', '));
if (/[\w.+-]+@[\w-]+\.[\w.-]+|\b\d{7,8}\b|\b\d{2,4}[-\s]\d{4}[-\s]\d{4}\b|\b\d{22}\b|\b\d{2}-\d{8}-\d\b/.test(b)) motivos.push('Contiene un dato personal');
const PROMESAS = [
  [/reintegr|reembols|devoluci[oó]n del (dinero|importe|pago)/i, 'reintegro'],
  [/compensaci|bonificaci|descuento|gratis|sin cargo|sin costo/i, 'compensación o descuento'],
  [/garantiz|le aseguramos|te aseguramos|nos comprometemos a (entregar|enviar|pagar|devolver)/i, 'garantía'],
  [/\b(hoy|mañana|manana|esta semana|el lunes|el martes|el miércoles|el jueves|el viernes)\b|\b\d{1,2}\/\d{1,2}\b|\ben \d+\s*(hs|horas|días|dias)\b|\b\d+\s*(hs|horas)\b/i, 'fecha o plazo'],
  [/\$\s*\d|\bpesos\b|\d+[.,]\d{3}/i, 'monto'],
];
for (const [re, que] of PROMESAS) if (re.test(b)) motivos.push('Promete algo que no puede prometer (' + que + ')');
if (b.length > 700) motivos.push('Demasiado largo (' + b.length + ' caracteres)');
return [{ json: { valido: motivos.length === 0, borrador: b, motivos, fuente: $input.first().json.fuente } }];
