// CA_8.4b: extracción por código (sin IA). QR primero; texto u OCR para lo que el QR no trae.
function numAR(s) {                       // "1.234.567,89" -> 1234567.89
  if (s == null) return null;
  const t = String(s).replace(/[^\d.,]/g, '');
  if (!t) return null;
  const n = Number(t.replace(/\./g, '').replace(',', '.'));
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : null;
}
function fechaISO(s) {
  if (!s) return null;
  let m = s.match(/(\d{4})-(\d{2})-(\d{2})/); if (m) return `${m[1]}-${m[2]}-${m[3]}`;
  m = s.match(/(\d{2})[./-](\d{2})[./-](\d{4}|\d{2})\b/);
  if (m) return `${m[3].length === 2 ? '20' + m[3] : m[3]}-${m[2]}-${m[1]}`;
  return null;
}
function cuitFmt(x) { const d = String(x || '').replace(/\D/g, ''); return d.length === 11 ? `${d.slice(0,2)}-${d.slice(2,10)}-${d[10]}` : null; }
function cuitValido(c) {
  const d = String(c || '').replace(/\D/g, ''); if (d.length !== 11) return false;
  const w = [5,4,3,2,7,6,5,4,3,2]; let s = 0; for (let i = 0; i < 10; i++) s += +d[i] * w[i];
  let v = 11 - (s % 11); if (v === 11) v = 0; if (v === 10) v = 9; return v === +d[10];
}
const CUIT_PROPIO = '30-71234567-0';   // Materiales Cumbre Andina (receptor), nunca es el emisor
function cuitEmisor(t) {                // primer CUIT del documento que no sea el propio; tolera OCR (CUJT, CU1T)
  for (const m of t.matchAll(/CU\S{1,2}:?\s*([\d-]{11,13})/g)) { const c = cuitFmt(m[1]); if (c && c !== CUIT_PROPIO) return c; }
  return null;
}
function ocNorm(x) {                   // OCR confunde O y 0: OC-L0O049 -> OC-L0049. La base después confirma que la OC exista, sea del proveedor y cierre el monto
  if (!x) return null;
  const m = String(x).toUpperCase().match(/^OC-L([0-9O]+)$/);
  return m ? 'OC-L' + m[1].replace(/O/g, '0').slice(-4) : String(x).toUpperCase();
}
function extraer(lectura) {
  const q = lectura.qr && lectura.qr.datos;
  const t = lectura.escaneado ? (lectura.ocr || '') : (lectura.texto || '');
  const fuenteTexto = lectura.escaneado ? 'ocr' : 'texto';
  const campo = (valor, fuente) => ({ valor, fuente: valor == null ? null : fuente });
  const g = (re) => { const m = t.match(re); return m ? m[1] : null; };
  const nro = t.match(/N\S{0,2}\s*(\d{4})\s*-\s*(\d{8})/);
  const TIPOS_QR = { 1: 'Factura A', 2: 'Nota de débito A', 3: 'Nota de crédito A', 11: 'Factura C', 12: 'Nota de débito C', 13: 'Nota de crédito C' };
  const tTipo = t.match(/\b(FACTURA|NOTA DE CR[EÉ]DITO|NOTA DE D[EÉ]BITO)\s*([ABC])\s*N/i);
  const tipoTexto = tTipo ? ({ FACTURA: 'Factura', 'NOTA DE CREDITO': 'Nota de crédito', 'NOTA DE CRÉDITO': 'Nota de crédito', 'NOTA DE DEBITO': 'Nota de débito', 'NOTA DE DÉBITO': 'Nota de débito' }[tTipo[1].toUpperCase()] + ' ' + tTipo[2].toUpperCase()) : null;
  const d = {
    tipo:   q && TIPOS_QR[q.tipoCmp] ? campo(TIPOS_QR[q.tipoCmp], 'qr') : campo(tipoTexto, fuenteTexto),
    cuit:   q ? campo(cuitFmt(q.cuit), 'qr') : campo(cuitEmisor(t), fuenteTexto),
    punto_venta: q ? campo(String(q.ptoVta).padStart(4, '0'), 'qr') : campo(nro ? nro[1] : null, fuenteTexto),
    numero: q ? campo(String(q.nroCmp).padStart(8, '0'), 'qr') : campo(nro ? nro[2] : null, fuenteTexto),
    fecha:  q ? campo(q.fecha, 'qr') : campo(fechaISO(g(/Fecha de emisi\S*n:?\s*([\d./-]{8,10})/i)), fuenteTexto),
    total:  q ? campo(Math.round(q.importe * 100) / 100, 'qr') : campo(numAR(g(/TOTAL:?\s*\$?\s*([\d.,]+)/)), fuenteTexto),
    total_texto: campo(numAR(g(/TOTAL:?\s*\$?\s*([\d.,]+)/)), fuenteTexto),
    neto:   campo(numAR(g(/neto gravado:?\s*\$?\s*([\d.,]+)/i)), fuenteTexto),
    alicuota: campo((() => { const a = g(/IVA\s*(\d+(?:[.,]\d+)?)\s*%/); return a ? Number(a.replace(',', '.')) / 100 : null; })(), fuenteTexto),
    iva:    campo(numAR(g(/IVA\s*\d+(?:[.,]\d+)?\s*%:?\s*\$?\s*([\d.,]+)/)), fuenteTexto),
    oc_id:  campo(ocNorm(g(/Orden de compra:?\s*(OC-[A-Z0-9]+)/i)), fuenteTexto),
    cbu:    campo(g(/CBU\s*(\d{22})/), fuenteTexto),
    cuit_impreso: campo(cuitEmisor(t), fuenteTexto),
    cae:    campo(q ? String(q.codAut) : null, 'qr'),
  };
  // Comprobante C (monotributista): no discrimina IVA. Neto = total, IVA 0
  if (d.tipo.valor && d.tipo.valor.endsWith(' C') && d.total.valor != null) {
    d.neto = campo(d.total.valor, 'letra C'); d.iva = campo(0, 'letra C'); d.alicuota = campo(0, 'letra C');
  }
  // IVA ilegible (OCR): se calcula total - neto y solo se acepta si coincide con una alícuota válida
  if (d.iva.valor == null && d.neto.valor != null && d.total.valor != null) {
    const ivaCalc = Math.round((d.total.valor - d.neto.valor) * 100) / 100;
    for (const a of [0.21, 0.105]) if (Math.abs(d.neto.valor * a - ivaCalc) <= 0.05) { d.iva = campo(ivaCalc, 'calculado'); d.alicuota = campo(a, 'calculado'); }
  }
  const motivos = [];
  for (const k of ['tipo', 'cuit', 'numero', 'fecha', 'total', 'neto', 'iva']) if (d[k].valor == null) motivos.push(`No se pudo leer: ${k}`);
  if (d.cuit.valor && !cuitValido(d.cuit.valor)) motivos.push('CUIT inválido (dígito verificador)');
  if (d.neto.valor != null && d.iva.valor != null && d.total.valor != null && Math.abs(d.neto.valor + d.iva.valor - d.total.valor) > 0.05)
    motivos.push(`El total no cierra: neto + IVA = ${(d.neto.valor + d.iva.valor).toFixed(2)} y el total es ${d.total.valor.toFixed(2)}`);
  if (q && d.cuit_impreso.valor && d.cuit_impreso.valor !== d.cuit.valor)
    motivos.push(`El CUIT impreso (${d.cuit_impreso.valor}) no coincide con el del QR de ARCA`);
  if (d.cuit_impreso.valor && !cuitValido(d.cuit_impreso.valor) && !(d.cuit.valor && !cuitValido(d.cuit.valor)))
    motivos.push('CUIT impreso inválido (dígito verificador)');
  if (q && d.total_texto.valor != null && Math.abs(d.total_texto.valor - d.total.valor) > 0.05)
    motivos.push('El total del texto no coincide con el del QR de ARCA');
  return { datos: d, motivos };
}
if (typeof module !== 'undefined') module.exports = { extraer, cuitValido, numAR, fechaISO };
