# Phase 5. Data quality and baseline

**Project:** AI Governance in Operations: KPIs, ROI and process control with Power BI
**Case:** Cumbre Andina Building Supplies (fictional company, synthetic data)
**Version:** 1, approved 2026-11-03

---

## In a nutshell

| | |
|---|---|
| **Input** | 12 months of history from the manual process (Oct 2025 to Sep 2026): 11,124 invoices entered, 4,200 complaints, 8,000 customers, 120 suppliers and 9,849 purchase orders |
| **What it does** | Measures what is wrong, fixes it with written rules, checks the fix against the correct values and calculates the "before" KPIs |
| **Output** | Clean data in `datos/limpio/` (clean data), monthly KPIs ready for Power BI and this report |

**Main result:** almost half of the invoices were entered late, one in eight had some wrong data, and the manual process let through 166 duplicate invoices that were paid twice, for 168.8 million local currency units in one year.

---

## 1. Diagnosis

It was done **without looking at the correct values**, as it would be in a real company.

### Invoices
| Problem | Count | How it is detected |
|---|---|---|
| Duplicates (same supplier document entered twice) | 324 pairs | same supplier, point of sale, number and type |
| Legal name different from the supplier master | 570 | comparison with the master |
| Issue date in another format | 457 | does not follow yyyy-mm-dd (dd-mm-yy, dd.mm.yyyy, dd/mm/yyyy) |
| Invalid tax ID | 241 | check digit |
| Total does not add up (net + VAT different from total) | 208 | calculation |

No problems: VAT always matches the net amount, there are no out-of-order dates and all purchase orders exist. Empty fields are expected: the 1,134 invoices without a purchase order are credit or debit notes, and the 137 without a registration date are those rejected as duplicates.

### Complaints and customers
- Complaints: no missing data, consistent dates and no repeated identifiers. Their problems are process problems (routing, deadlines, reopenings) and are measured as KPIs.
- Customers: 1 national ID number repeated across two different customers. It was not seeded; it appeared by chance from the generator and the diagnosis detected it.

## 2. Correction rules

Each correction keeps the original value, the corrected value and a flag. The original files are not modified.

| # | Problem | Rule | Flag |
|---|---|---|---|
| 1 | Date in another format | Converted to yyyy-mm-dd, day first; 2-digit year = 20yy. If it ends up after the receipt date or more than 90 days before it, it goes to review | `fecha_normalizada` (normalized date), `revisar_fecha` (review date) |
| 2 | Invalid tax ID | The tax ID from the master is used, based on proveedor_id (supplier ID) | `cuit_corregido` (corrected tax ID) |
| 3 | Different legal name | The master's name is used if it is 80% or more similar; otherwise it goes to review | `razon_estandarizada` (standardized legal name), `revisar_razon` (review legal name) |
| 4 | Total does not add up | For analysis, net + VAT is used. In real life it is an exception for review: an amount is not changed by rule | `excepcion_monto` (amount exception) |
| 5 | Duplicates | They are not deleted. The copy is flagged, along with which one it is a copy of and whether the manual process detected it. To count volume, only the original (the one that arrived first) is used | `es_duplicada` (is duplicate), `duplicada_de` (duplicate of), `detectada_manual` (detected manually) |
| 6 | Repeated national ID number | Not corrected; both customers are flagged | `revisar_dni` (review national ID) |

## 3. Validation against the correct values

| Rule | Flagged | Seeded | Corrected value equal to the correct one |
|---|---|---|---|
| Date | 457 | 446 | 100% |
| Tax ID | 241 | 228 | 100% |
| Legal name | 570 | 555 | 100% |
| Amount | 208 | 201 | 100% |
| Duplicates | 324 | 324 | 100%, with the original correctly identified |

**Why there are more flagged than seeded:** duplicates are copies of an original invoice. If the original had an error, the copy has it too, and the cleaning fixes it. The ground truth file labels those copies only as "duplicate". The 46 extra flags are all of that type: there were no undetected errors and no correct data was modified.

**Limit:** the 100% accuracy exists because the errors were seeded by the project itself and the rules know them. With real data, unforeseen errors appear; that is what the "review" flags and the human review queue (A14) are for.

## 4. Baseline: the "before" KPIs

Assumptions: business day = Monday to Friday from 8 to 17, no holidays. The month of each invoice is its issue month. Values in local currency are calculated in Phase 10, except for the invoices paid twice.

### Supplier invoices (10,800 invoices + 324 duplicate copies)
| Publication name | Technical name | Before (12 months) |
|---|---|---|
| How long does an invoice take to be entered? | Processing time | 2.7 business days |
| Invoices entered late (more than 2 business days) | SLA compliance | 46% outside the deadline |
| Hours per month entering invoices by hand | Manual effort | 142 per month (1,702 in the year) |
| Invoices with some wrong data | Data error rate | 12.8% |
| Duplicates that slipped through | Undetected duplicates | 187 of 324 (the manual process detected 42%) |
| Invoices paid twice | Duplicate payment | 166, for 168.8 million local currency units |

The other 21 undetected duplicates (August and September, 15.3 million local currency units) still appear as registered, unpaid: they can still be stopped. That is why September shows 0 paid twice, and not because the process improved.

### Customer complaints (4,200)
| Publication name | Technical name | Before (12 months) |
|---|---|---|
| How long does a customer wait for the first response? | First response time | 16.8 business hours |
| Customers who wait more than one day | Response SLA (24 business hours) | 21.5% |
| Complaints resolved on time | Resolution SLA (5 business days) | 80% |
| Complaints sent to the wrong department | Routing error | 15% (measured by audit) |
| Complaints that are reopened | Reopening rate | 7.7% |
| Where and why do they complain? | Complaint distribution | balanced branches (660 to 730 each); main reason: delayed delivery (29%), then damaged material (18%) |

The ranking of reasons uses the category assigned by the agent, which matches the correct one in 94% of cases.

## 5. Readings and limits

1. **The high season shows in volume, not in percentages.** October to December and March exceed 930 invoices per month; January and February drop to 700-800. The error rate and deadlines barely change because the generator did not model the team getting worse under heavier load. In real data this would be the first thing to investigate.
2. **"Wrong department" is measured by audit.** The history does not record it; in a real company a sample of complaints is audited.
3. **Hours are not money yet.** Converting them to currency requires an hourly staff cost, which is defined as an assumption in Phase 10.

## 6. Files

| File | Content |
|---|---|
| scripts/limpiar_historico.py | Applies the 6 rules. Reproducible |
| scripts/linea_base.py | Calculates the KPIs per month and in total |
| datos/limpio/*_limpio.csv | Clean tables with original values and flags |
| datos/limpio/kpi_linea_base_facturas.csv | Invoice KPIs per month (for Power BI) |
| datos/limpio/kpi_linea_base_reclamos.csv | Complaint KPIs per month (for Power BI) |
| datos/limpio/kpi_linea_base_reclamos_donde_y_por_que.csv | Complaints by branch and reason |
| notebooks/05_linea_base.ipynb | The step-by-step analysis, with the code visible |

## 7. For the publication (Phase 13)

**Summary:** I received 12 months of a manual invoice and complaint process. I measured what was wrong, fixed it with written, verifiable rules, and calculated how the process performed before automating anything. Without this "before", no improvement can be demonstrated.

**Image:** carousel with the question in large type and the result. Featured slide: invoices paid twice per month, in stacked bars ("already paid" and "can still be stopped").

---

## Pending to close Phase 5
- [x] Review and approval by the project author (2026-11-03).
