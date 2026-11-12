# Executive Report. AI Governance in Operations

Case: Cumbre Andina Building Supplies, a building materials distributor (fictional company).
Version 1, 2026-11-09.

> Everything is synthetic. The report shows the method and how the result changes when assumptions change. These are not figures from a real company.

## In brief

Two administrative processes were automated with AI, supplier invoices and customer complaints, under rules that prevent the AI from deciding on money or personal data. In a test batch of 153 emails and 100 complaints, no trap case was resolved on its own and the flows had 0 errors. In the base scenario, the projected net benefit is 98.8 million local currency units per year. That number depends on a single assumption: how many duplicate invoices are stopped.

## 1. The problem

Before automating, the manual process was measured over 12 months (10,800 invoices and 4,200 complaints):

- 46% of invoices were entered late and 12.8% had some incorrect data.
- 166 invoices were paid twice, for 168.8 million local currency units. The manual process detected 42% of the duplicates.
- Manual entry consumed 142 hours per month.
- 15% of complaints went to the wrong department and 20% were resolved late.
- Personal data travelled in free text, with no control.

## 2. What was built

14 automations in n8n, on a Postgres database, with AI models that run on a self-hosted server:

- **Invoices (P1):** email reading, validations by code, duplicate search, bank account number change control and a payment approval request. The flow goes up to "approved for payment". The payment is made by a person.
- **Complaints (P2):** classification, routing by fixed table, deadline control and a draft reply that an agent reviews.
- **Security and data (P0):** personal data vault, text masking, policy and approval engine, monitoring with circuit breaker, human review queue, controlled re-identification and weekly report.

Design rules: code handles whatever must not be wrong, the AI only classifies or drafts, everything that does not reconcile goes to a person with the reason written down, and silence never counts as a yes.

## 3. What was measured

| Batch result | Value |
|---|---|
| Invoices registered / to the queue / blocked by bank account number / suspicious | 136 / 11 / 4 / 2 |
| Invoice trap cases that reached a person | 17 of 17 |
| Duplicates stopped | 3 of 3 (small sample) |
| Complaints with the correct category | 100 of 100 |
| Personal data requests diverted to the Officer | 4 of 4 |
| Flow errors | 0 |
| Database permission and rule tests | 49 of 49 and 10 of 10 |

The tests found three real failures, already fixed: an extra write permission on approvals, a cutoff leaving partial traces when the AI does not respond, and the lack of a central error log.

## 4. What it is worth in money

Base scenario over 12 months, with the investment valued as development contracted on the market (7,687,395 local currency units):

| Item | Value |
|---|---|
| Savings from 1,502 hours | 19.2 million local currency units |
| Savings from avoided duplicate payments (with 50% recoverable) | 84.4 million local currency units |
| Annual operating cost | 4.8 million local currency units |
| Annual net benefit | 98.8 million local currency units |
| 12-month ROI | 1,185% |
| Payback | 0.9 months |

How it changes with the assumptions:

- If duplicate detection were equal to that of the manual process (42%): net benefit of 14.4 million local currency units, ROI of 88% and payback in 6.4 months.
- In the combined worst case: a loss of 7.3 million local currency units per year and the investment is not recovered.
- Cost assumptions (cost per hour, minutes per case, server) move the result by a few million.

The ROI covers invoices only. Complaints and security were not converted into currency.

## 5. Governance

Each automation has an owner, the data it touches, a risk level and an assigned control. A 6-page Power BI dashboard shows the status: KPIs, measured batch, switches, inventory with risk, review queue, incidents and ROI sensitivity.

## 6. Limits

- Synthetic data and a fictional company. No inflation.
- The batch has 17 seeded traps among 153 emails. In a real operation the proportion of cases that go to a person may be different.
- Duplicate detection was measured with 3 cases.
- Who decides in the forms is chosen from a dropdown, without login.
- The sender of a malicious document and its origin are not recorded.
- The final reply to the customer is not sent: it stays as a draft.
- The review queue has 70 pending cases, to be cleaned up.
- Data retention periods are case parameters, to be defined with the legal and accounting departments. The project follows a general reference framework and is not legal advice.

## 7. What would be needed to take it to a real company

1. Replace the synthetic data with the company's real data and measure the baseline again.
2. Login for those who approve and those who decide, instead of the dropdown.
3. Store the origin of suspicious documents (sender, domain and fingerprint) and define the blocklist with the legal department.
4. Own email credential, with send-only permission.
5. Measure approval and queue times with real people, which were not measured in the prototype.

## 8. Where everything is

Business cases per process: `documentacion/`. Baseline: `05_Data_Quality_and_Baseline.md`. Processes and defenses: `06_Processes_AS-IS_TO-BE.md`. Tests: `09_Test_Plan_and_Results.md`. KPIs, ROI and sensitivity: `10_KPI_and_ROI.md`. Dashboard: a Power BI report, described in the README (the report file is not included in this repository).
