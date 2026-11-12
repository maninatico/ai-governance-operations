# Phase 0. Scope, glossary and preliminary KPIs

**Project:** AI Governance in Operations: KPIs, ROI and process control with Power BI
**Case:** Cumbre Andina Building Supplies (fictional company)
**Version:** 1.1, 03/11/2026 (approved adjustment: personal data vault, pseudonymization, local model and tax authority QR code)

---

## 1. Scope

### Objective
To demonstrate, with a complete case, how to automate a company's administrative and customer service processes using AI **with governance**: knowing which automations exist, who is responsible for each piece of data, what risk each process carries, which controls protect it and how much value it generates, measured with KPIs and ROI.

### What it includes
- **P0. Security and data** (cross-cutting): vault and pseudonymization of personal data, controlled re-identification, human review queue, fraud detection, control of suspicious documents, audit.
- **P1. Supplier invoices:** reception by email, classification, data extraction, validations, registration and approval.
- **P2. Customer complaints:** reception, classification, routing to the right department, deadline tracking and response.
- Automation inventory, data access matrix and risk classification.
- Policies on data, AI use, human approval, changes and incidents.
- Synthetic data, cleaning, baseline, before and after measurement, ROI.
- Governance dashboard and documentation for dissemination.

### What it does not include
- Real data about people or companies. Everything is synthetic.
- Implementation in a real company or connection to real systems (ERP, banks, tax authority).
- Real payments: the flow ends at "invoice approved for payment".
- Legal advice: the work follows a general reference framework.

### Technical assumptions
- Orchestration in n8n (own environment).
- Postgres database.
- Python and pandas to generate and clean data.
- External AI models via OpenRouter or Gemini (to be defined by cost in Phase 8), only with pseudonymized data.
- Local model (Ollama on an own server) for the only steps that touch unmasked personal data.
- Local OCR (Tesseract) for scanned supplier documents.
- Dashboard: Power BI.

### Success criteria
The project is finished when:
1. Each process has its catalog entry, with owner, data, risk and controls.
2. The flows work end to end with the synthetic data.
3. The planted traps (fraud, document with hidden instructions, duplicates) are detected and stopped.
4. There are before and after KPIs, and an ROI calculated with written assumptions.
5. Everything can be shown in a 5-minute demo.

---

## 2. Glossary

- **Automation:** a flow that executes tasks without manual intervention, fully or partially.
- **AI governance:** the set of rules, roles, controls and measurements that ensure AI is used safely, legally, traceably and with measurable value.
- **Automation inventory:** a list of all active automations, with what they do, who the owner is, what data they touch and which version they are on.
- **Process catalog:** an ordered record of the company's processes, with their entry (owner, steps, data, risks, controls and KPIs).
- **Process owner:** the person who is accountable for the result of the process and approves its changes.
- **RACI matrix:** a table that defines, per task or data item, who executes it (R), who is accountable (A), who is consulted (C) and who is informed (I).
- **AS-IS:** the process as it works today.
- **TO-BE:** the process as it should work after the improvement.
- **Swimlane diagram:** a diagram where each actor has their own lane and it shows who does what.
- **Baseline:** measurement of the process before improving it. Without it, the improvement cannot be demonstrated.
- **KPI (key performance indicator):** a number that shows whether a process meets its objective.
- **ROI (return on investment):** the ratio between what is gained and what was invested.
- **Payback:** the number of months the improvement takes to pay back the investment.
- **SLA (service level agreement):** the committed deadline for a task, for example answering a complaint within 48 hours.
- **Risk classification:** a level (low, medium, high) according to the damage an error in the process can cause.
- **Control level (L0 to L4):** how much human control an action requires, from fully automatic to prohibited.
- **Human approval (human-in-the-loop):** a step where a person reviews and decides before the action is executed.
- **Personal data:** information that identifies a person (name, national ID number, phone, address, email).
- **Minimization:** using only the data necessary for each task.
- **Pseudonymization:** replacing the identity of a person or company with an ID (cliente_id, proveedor_id, i.e. customer ID, supplier ID). With the vault, the real data can be recovered; without it, it cannot.
- **Masking:** replacing personal data inside free text with placeholders ([DNI_1], [TEL_1]) before sending it to an external model.
- **Vault:** a restricted table where the real personal data lives. The working database only stores IDs.
- **Unmasker (re-identification):** a controlled step that returns the real data from the ID or the placeholder. Every use is logged.
- **Fail safe (fail-closed):** if a control fails, the process stops instead of continuing without control.
- **Local model:** an AI model that runs on an own server, without sending data to an external provider.
- **Human review queue:** a list of cases that the automation could not resolve with certainty and that a person decides.
- **Tax authority QR code:** a code printed on the electronic invoice with date, tax ID, number, amount and authorization code. If it can be read, it is the most reliable source for the supplier document.
- **Authorization code:** a code that the tax authority assigns to each electronic invoice.
- **OCR:** text recognition in an image, for example a scanned supplier document.
- **Prompt injection:** text hidden in a document or email that tries to give orders to the AI.
- **Account change fraud:** a fake message pretending to be from a supplier in order to divert a payment to another bank account.
- **Audit log:** a history of who did what, when and with what result.
- **Policy and approval engine:** a component that decides whether an action is allowed, blocked or needs human approval according to written rules (Policy Decision Point), and that enforces that decision (Policy Enforcement Point).
- **Kill switch:** a way to turn off all automations immediately.
- **Circuit breaker:** automatic shutdown of a flow when it fails several times in a row.
- **Synthetic data:** invented data that imitates the structure and problems of real data.

---

## 3. Preliminary KPIs

Targets are set after measuring the baseline (Phase 5). This list is adjusted as the project advances.

### P1. Supplier invoices
| KPI | Definition | Formula |
|---|---|---|
| Processing time | Time from invoice arrival until it is registered | average(registration − reception) |
| Extraction accuracy | Fields extracted correctly | correct fields / total fields |
| Exception rate | Invoices that need human review | invoices sent to review / total invoices |
| Duplicates detected | Repeated invoices stopped before payment | duplicates detected / existing duplicates |
| Invalid data detected | Invoices with invalid tax ID, date or amount that were detected | invalid detected / existing invalid |
| Cost per invoice | AI and infrastructure cost per document | monthly cost / invoices processed |

### P2. Customer complaints
| KPI | Definition | Formula |
|---|---|---|
| First response time | Time until the first response to the customer | average(first response − reception) |
| Deadline compliance | Complaints resolved within the SLA | resolved on time / total complaints |
| Correct routing | Complaints sent to the right department on the first attempt | correctly routed / total complaints |
| Reopened complaints | Closed complaints that are opened again | reopened / closed |
| Complaints by branch and category | Where and why complaints are made | count by branch and category |

### P0. Security and data
| KPI | Definition | Formula |
|---|---|---|
| Masking before AI | Personal data masked before reaching an external model | masked data / personal data detected |
| Re-identifications logged | Uses of the unmasker with reason and log entry | logged uses / total uses (target: 100%) |
| Cases sent to human review | Cases the automation could not resolve | cases in queue / cases processed |
| Fraud detected | Account change attempts stopped | attempts stopped / existing attempts |
| Suspicious documents stopped | Documents with hidden instructions detected | detected / planted |
| Detection time | Time from when the risk enters until it is detected | average(detection − entry) |
| Out-of-permission access | Attempts to access data without authorization | count per period |

### Automation health
| KPI | Definition | Formula |
|---|---|---|
| Success rate | Executions that finish correctly | successful / total |
| Human intervention | Executions that required a person | with intervention / total |
| Retries | Executions that needed to retry | with retry / total |
| Monthly AI cost | Spending on AI models | sum of cost per execution |

### Business and ROI
| KPI | Definition | Formula |
|---|---|---|
| Hours saved per month | Manual time no longer spent | (time before − time after) × volume |
| Cost avoided from errors | Losses avoided (duplicates, fraud, fines) | sum of cases avoided × estimated cost |
| Monthly net benefit | Savings minus operating cost | monthly savings − monthly cost |
| ROI | Return on what was invested | (net benefit for the period − investment) / investment |
| Payback | Months to recover the investment | investment / monthly net benefit |

---

## Pending to close Phase 0
- [x] Review and approval by the project author (2026-11-03).
