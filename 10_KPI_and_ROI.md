# 10. After-Implementation KPIs, ROI and Sensitivity (Phase 10)

Project: AI Governance in Operations, fictional company Cumbre Andina Building Supplies.

**Reading notice.** The data is synthetic. This document shows the method and how the result behaves when the assumptions change. It is not the result of a real company. Every value comes from one of three sources: the Phase 5 baseline, what was measured in the test batch (`sql/17_medicion_despues.sql`, post-implementation measurement, and the n8n timings) or an assumption written in section 3.

## 1. What was measured

The "after" was measured on the test batch: 153 supplier emails and 100 complaints. The baseline covers 12 months (10,800 invoices and 4,200 complaints). For that reason the annual "after" is a **projection**, and the projection is an assumption.

Measurement sources:

- Statuses and counts: `sql/17_medicion_despues.sql`, read-only, excluding records with the PRUEBA prefix (test data).
- Timings: n8n executions. The table `control.ejecuciones` (control.executions) stores start and end at the same instant, so its duration gives 0.0 seconds and is not used.
- AI cost: 0 dollars, because the models run on an own server. Tokens are not recorded.

## 2. KPIs: before and after

### Supplier invoices

| KPI | Before (12 months) | After (batch of 153 emails) |
|---|---|---|
| Time until loaded | 2.7 business days | 3 min 29 s for the 153 emails, about 1.4 s per email, until registered. The 17 cases that go to a person wait for their review, and that wait was not measured |
| Invoices loaded late | 46% outside the deadline | Not measurable: the whole batch enters on the same day |
| Hours per month of manual loading | 142 | 16.7 projected (200 hours per year of exception review, with 11.1% of cases going to a person and 10 minutes per case, both assumptions) |
| Invoices with some wrong data | 12.8% | 0 reading errors in the 153 against the batch ground truth. The traps for tax ID, amount and duplicate went to the queue |
| Duplicates that slipped through | 187 of 324 (the manual process detected 42%) | 3 of 3 duplicates in the batch reached a person. Sample of 3 cases |
| Invoices paid twice | 166, for 168.8 million local currency units | 0 in the batch. The annual projection depends on the detection assumption (section 5) |

Batch result: 136 invoices registered, 11 in the review queue, 4 blocked by bank account number and 2 suspicious because of hidden text (these two were not registered). The 17 traps in the batch reached a person. Flow errors: 0.

### Customer complaints

| KPI | Before (12 months) | After (batch of 100 complaints) |
|---|---|---|
| First response | 16.8 business hours | The draft is ready in a little over 1 minute per complaint (inference: run 5340 took 86.6 min and I assume it processed the 87 that were missing). The real response depends on the approval of the handling agent: 92 drafts are waiting and that time was not measured |
| Complaints sent to the wrong department | 15% (by audit) | Correct category in 100 of 100. 96 routed by fixed table and 4 requests for personal data diverted to the responsible person (owner) |
| Complaints resolved on time | 80% | Not measurable in the prototype |
| Complaints that are reopened | 7.7% | Not measurable in the prototype |

Complaint benefits are not converted to currency amounts: the baseline has no complaint hours or costs to compare against.

## 3. Assumptions

Everything in this table is an assumption, except what is marked as data. Currency amounts are in local currency units.

| Assumption | Base value | Range in the sensitivity analysis | Source |
|---|---|---|---|
| Reference salary | 1,366,648 per month | fixed | Data: Administrative Clerk A, retail sector, October 2026 pay, consolidated with non-remunerative sums (published salary scale). That invoice loading is done by this category is an assumption |
| Hours per month | 160 | fixed | Assumption |
| Payroll burden and overhead factor | 1.5 | 1.0 and 2.0 | Assumption |
| Cost per hour | 12,812 | 8,542 and 17,083 | Calculated from the three above |
| Cases that go to a person | 11.1% | 20% and 30% | Measured in the batch (17 of 153). The batch has seeded traps, so it may not represent the real flow |
| Human minutes per case | 10 | 5, 15 and 30 | Assumption |
| Duplicates stopped | 100% | 90%, 70% and 42% | Batch: 3 of 3. Small sample. 42% is what the manual process achieved |
| Share of what was paid twice that is recovered anyway | 50% | 0% and 90% | Assumption |
| Server per month | 300,000 | 150,000 and 600,000 | Assumption without a source |
| Maintenance | 8 hours per month | fixed | Assumption |
| Build hours | 15 | 40 and 80 | Declared by the project author as of 2026-11-09 |
| Development hired on the market | 200 hours at triple the cost per hour | fixed | Assumption without a source |
| Currency | Nominal local currency units, 12 months, no inflation | | Assumption |
| Payment approvals | Excluded on both sides | | They existed before and the baseline does not measure them |

Investment: **scenario A** is the 15 build hours valued at the cost per hour (192,185). **Scenario B** is what it would cost to hire the development (7,687,395). Scenario B is the conservative figure and is the one I use as the headline.

Annual cost of operating (base): server 3.6 million plus maintenance 1.2 million, for a total of 4.8 million.

## 4. Base calculation

| Item | Value |
|---|---|
| Manual data entry hours per year before | 1,702 |
| Human hours after (1,200 cases × 10 min) | 200 |
| Hours saved | 1,502 |
| Savings from hours | 19.2 million |
| Duplicate payments avoided | 166 of 166 |
| Savings from avoided errors (with 50% recoverable) | 84.4 million |
| Annual cost of operating | 4.8 million |
| **Annual net benefit** | **98.8 million** |
| Monthly net benefit | 8.2 million |
| 12-month ROI, scenario B | 1,185% |
| Payback, scenario B | 0.9 months |
| 12-month ROI, scenario A | 51,316% |
| Payback, scenario A | less than 1 month |

Formulas: savings = hours saved × cost per hour + cost of avoided errors. Net benefit = savings minus cost of operating. ROI = (net benefit of the period minus investment) / investment. Payback = investment / monthly net benefit.

## 5. Sensitivity

One variable at a time, the rest at the base value. ROI and payback use scenario B.

| Variable | Value | Annual net benefit | ROI (B) | Payback (B) |
|---|---|---|---|---|
| Cost per hour | 8,542 | 92.8 M | 1,711% | 0.7 months |
| | 17,083 | 104.8 M | 923% | 1.2 months |
| Minutes per case | 5 | 100.1 M | 1,202% | 0.9 months |
| | 15 | 97.5 M | 1,169% | 0.9 months |
| | 30 | 93.7 M | 1,119% | 1.0 month |
| Cases to a person | 20% | 96.8 M | 1,159% | 1.0 month |
| | 30% | 94.5 M | 1,129% | 1.0 month |
| Duplicates stopped | 90% | 84.2 M | 995% | 1.1 months |
| | 70% | 54.9 M | 615% | 1.7 months |
| | 42% (same as manual) | 14.4 M | 88% | 6.4 months |
| Recoverable share | 0% | 183.2 M | 2,283% | 0.5 months |
| | 90% | 31.3 M | 307% | 2.9 months |
| Server per month | 150,000 | 100.6 M | 1,209% | 0.9 months |
| | 600,000 | 95.2 M | 1,139% | 1.0 month |
| Build hours (ROI A) | 40 | same | 19,181% | less than 1 month |
| | 80 | same | 9,541% | less than 1 month |

Two extreme cases:

- **No extra duplicate payment avoided** (detection stays at the 42% of the manual process): net benefit of 14.4 million per year, ROI of 88% and payback in 6.4 months with scenario B. The project pays for itself with the manual data entry saved alone.
- **Combined worst case** (cost per hour of 8,542, 30 minutes per case, 30% of cases to a person, detection of 42%, 90% recoverable and server of 600,000): net benefit of negative 7.3 million per year and the investment is not recovered.

## 6. Interpretation

1. **A single number drives the result.** Of the 98.8 million of net benefit, 84.4 million come from the duplicate payments avoided. The hours saved contribute 19.2 million. That is why the most sensitive assumption is how many duplicates are stopped, and then what share of what was paid is recovered anyway.
2. **The cost assumptions barely move the result.** Changing the cost per hour, the minutes per case or the server changes the net benefit by a few million.
3. **The build hours hardly weigh.** With 15 hours the scenario A investment is very small and the ROI comes out enormous. It is a correct number but not very useful. That is why the headline is scenario B.
4. **Duplicate detection was measured with 3 cases.** It is a small sample. The 168.8 million of duplicate payments are synthetic baseline data.

## 7. Declared limits

- Synthetic data and fictional company: the method is what can be defended, not the figures.
- The batch has 17 seeded traps among 153 emails. The proportion of cases that go to a person may be different in a real operation.
- `intervencion_humana` (human intervention) stays false in all executions. Human work is estimated with minutes per case (assumption).
- The review queue shows 70 pending cases and may include 8.4a test cases that do not carry the PRUEBA prefix. Pending cleanup.
- Human waiting times (approvals and queue) were not measured: there are no real people deciding.
- No inflation: the amounts are nominal for one year. With inflation, the cost per hour and the amounts paid twice would change.
- Complaint benefits are not in currency amounts.
- The "without source" assumptions (server, maintenance, hours and multiplier of the hired development, burden factor) are a project decision and should be read as such.

## 8. How to repeat the calculation

1. Batch measurements: `sql/17_medicion_despues.sql` (read-only).
2. Calculation and sensitivity: `python3 scripts/calcular_roi.py` (calculate ROI). The assumptions are at the top of the script, in a single place.
