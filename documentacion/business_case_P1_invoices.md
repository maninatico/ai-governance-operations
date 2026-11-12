# Business Case. P1: Supplier Invoices

Project: AI Governance in Operations. Fictional company: Cumbre Andina Building Supplies (a building materials distributor).
Version 1, 2026-11-09.

> The data is synthetic. This document shows the method and how the result behaves when assumptions change. These are not figures from a real company. Every number comes from the baseline (document 05_Data_Quality_and_Baseline.md), from the test batch (documents 09_Test_Plan_and_Results.md and 10_KPI_and_ROI.md) or from an assumption written in document 10_KPI_and_ROI.md.

## 1. The problem

Today an accounts payable analyst opens the shared mailbox, takes the invoices one by one, checks tax ID, date, amounts and purchase order by eye, and enters them by hand into the ERP. Over 12 months, across 10,800 invoices:

- 46% are entered late (2.7 business days on average).
- 12.8% end up with some incorrect data.
- Manual entry consumes 142 hours per month (1,702 over the year).
- The process caught 42% of the duplicates. 187 of 324 slipped through, and 166 were paid twice, for 168.8 million local currency units.
- There is no bank account number change control before paying.

## 2. What the automation does

The flow goes up to "invoice approved for payment". The payment itself is still made by the treasurer.

1. It reads the mailbox as soon as the email arrives, separates attachments and classifies them (invoice, credit or debit note, other).
2. It reads the invoice from the PDF text, the tax authority QR code or local OCR. Tax ID and bank account number are extracted by code, not by the AI.
3. It validates with code: tax ID check digit, date, net + VAT = total, purchase order (±2%) and match with the QR code.
4. It looks for duplicates by number and by supplier + date + amount.
5. It compares the bank account number with the one on record. If it differs, it blocks and alerts. It never changes a bank account number.
6. It registers whatever passed all the controls. Everything else goes to the review queue with the reason written down.
7. It requests payment approval from a person.

The AI only classifies. It does not pay, does not approve and does not touch the bank account number.

## 3. How risk is controlled

| Risk | Control | Automation |
|---|---|---|
| Incorrectly entered data | Validations by code. Whatever does not reconcile goes to the queue | A02, A05, A14 |
| Late entry | Immediate mailbox reading and automatic registration | A04, A05 |
| Duplicates | Double duplicate criterion. A possible duplicate is not registered | A05 |
| Bank account number change (fraud) | Block and verification through another channel, level L4 | A06 |
| Hidden instructions in a PDF | 5 defenses (document 06_Processes_AS-IS_TO-BE.md, section 3). The AI has no decision power | A04, A05 |
| Payment without approval | Human approval within 1 business day. Over 5,000,000 local currency units requires dual control. Silence never counts as a yes | A07, A03 |
| System failure | Record of every step, shutdown after 3 consecutive errors and weekly report | A01, A11, A12 |

Decisions that move money are made by a person.

## 4. What was measured

Test batch of 153 supplier emails, with 17 seeded trap cases:

| Result | Value |
|---|---|
| Registered | 136 |
| In the review queue | 11 |
| Blocked by bank account number | 4 |
| Suspicious due to hidden text (not registered) | 2 |
| Traps that reached a person | 17 of 17 |
| Flow errors | 0 |
| Reading errors against the batch ground truth | 0 of 153 |
| Duplicates stopped | 3 of 3 (small sample) |
| Processing time | 3 min 29 s for the 153 emails |

## 5. What it is worth in money

Assumptions are written in document 10_KPI_and_ROI.md. Base scenario, over 12 months, with development contracted on the market as the investment (7,687,395 local currency units):

| Item | Value |
|---|---|
| Hours saved per year | 1,502 |
| Savings from hours | 19.2 million local currency units |
| Savings from avoided duplicate payments (with 50% recoverable) | 84.4 million local currency units |
| Annual operating cost (server and maintenance) | 4.8 million local currency units |
| Annual net benefit | 98.8 million local currency units |
| 12-month ROI | 1,185% |
| Payback | 0.9 months |

A single number drives the result: how many duplicates are stopped. Of the 98.8 million, 84.4 million come from avoided duplicate payments.

- **If detection were equal to that of the manual process (42%):** net benefit of 14.4 million local currency units, ROI of 88% and payback in 6.4 months. The project pays for itself with the manual entry saved alone.
- **Combined worst case:** a net loss of 7.3 million local currency units per year and the investment is not recovered.

Duplicate detection was measured with 3 cases.

## 6. What changes for people

The analyst stops typing and resolves only the exceptions. The Administration Manager approves with a deadline. Nobody touches a bank account number without verifying it through another channel.

## 7. Limits

- Synthetic data and a fictional company. No inflation: nominal amounts for one year.
- The batch has 17 traps among 153 emails. In a real operation the proportion of cases that go to a person may be different.
- Human minutes per case are an assumption, because `intervencion_humana` (human intervention) stays false in all executions.
- Human waiting times (approvals and queue) were not measured.
- Payment approvals existed before and are left out of the ROI on both sides.
- The actual payment is out of scope.
- Who decides in the forms is chosen from a dropdown, without login.
- The queue has 70 pending cases and may include cases from old tests without the PRUEBA prefix.

## 8. Where everything is

Baseline: `05_Data_Quality_and_Baseline.md`. Process before and after: `06_Processes_AS-IS_TO-BE.md`. Tests: `09_Test_Plan_and_Results.md`. KPIs, ROI and sensitivity: `10_KPI_and_ROI.md`. Calculation: `scripts/calcular_roi.py`.
