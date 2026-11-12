# Phase 2. Catalog, Inventory and Risk

**Project:** AI Governance in Operations: KPIs, ROI and process control with Power BI
**Case:** Cumbre Andina Building Supplies (fictional company)
**Version:** 1.2, 2026-11-09 (automation statuses and versions aligned with the database after building and testing A01 to A14). Previously: 1.1, 2026-11-03 (approved adjustment: personal data vault, pseudonymization, local model and tax authority QR code)

> Fictional case. Roles, processes and automations are designed for the project.

---

## 1. How risk is classified

Each process and each automation is evaluated with four questions. If an error occurred:

1. **Economic impact:** could it cause an improper payment, a loss or a fine?
2. **Personal data:** does it expose or handle personal data protected by the applicable national personal data protection law?
3. **Customer or supplier impact:** does it affect them directly?
4. **Autonomy:** does the action run on its own or go through a person?

| Risk | Criterion |
|---|---|
| **Low** | Error is easy to detect and correct, with no economic impact and no personal data. |
| **Medium** | Affects customers or handles personal data, but the economic impact is limited and reversible. |
| **High** | Can cause financial loss, fraud or exposure of data that is hard to reverse. |

Reference: the risk-based approach of ISO/IEC 42001 and the NIST AI RMF. A priori, no process in the case falls under the high-risk categories of the EU AI Act (employment, credit, etc.); it is used as a methodological reference, not as a legal framework.

## 2. Control levels (L0 to L4)

Defined specifically for this project.

| Level | Name | What it means | Example |
|---|---|---|---|
| **L0** | Automatic | Runs on its own and is logged. | Classifying an incoming email. |
| **L1** | Automatic with notification | Runs on its own and the owner is notified. | Routing a complaint to the corresponding area. |
| **L2** | Automatic with later review | Runs, and a person reviews a sample or the exceptions. | Recording an invoice that passed all validations. |
| **L3** | Prior approval | Does not run without human approval. If nobody responds, it does not run. | Approving an invoice for payment. |
| **L4** | Prohibited for automation | Only a person does it, through a verified channel. The automation can only raise an alert. | Changing a supplier's bank account. |

**Golden rule:** silence is never a yes. Any L3 action without a response stays on hold and is escalated.

## 3. Process catalog

### P0. Security and data (cross-cutting)
- **Objective:** ensure every automation handles data according to the law, leaves a trail and cannot be used for fraud.
- **Owner:** Systems Manager.
- **Personal data owner:** Administration Manager.
- **Scope:** vault and pseudonymization of personal data, controlled re-identification, human review queue, audit log, bank account change fraud detection, control of suspicious documents, permissions, monitoring, master switch.
- **Risk:** **High** (if it fails, the controls of every process fail).
- **KPIs:** see 01_Scope_and_Glossary.md, section P0 and Automation health.

### P1. Supplier invoices
- **Objective:** record each supplier document correctly and on time and leave it ready for payment, with no duplicates or fraud.
- **Owner:** Administration Manager.
- **Participants:** accounts payable analysts, Purchasing, Treasury.
- **Trigger:** a supplier document arrives in the Administration mailbox.
- **Inputs:** PDF or image of the supplier document, purchase order, supplier master.
- **Outputs:** recorded supplier document, exceptions routed, invoice approved for payment.
- **Systems:** email, n8n, Postgres, ERP (simulated).
- **Critical data:** tax ID, amounts, supplier bank account number.
- **Risk:** **High** (direct economic impact and fraud risk).
- **Internal SLA:** supplier document recorded within 2 business days of receipt.
- **KPIs:** see 01_Scope_and_Glossary.md, section P1.

### P2. Customer complaints
- **Objective:** ensure each complaint reaches the right area, is answered on time and is measured.
- **Owner:** Customer Service Manager.
- **Participants:** customer service agents, branch managers, Logistics, Administration.
- **Trigger:** a complaint arrives via WhatsApp, email or a branch.
- **Inputs:** complaint text, photos, customer data, order number.
- **Outputs:** complaint classified, routed, answered and closed.
- **Systems:** WhatsApp Business, email, n8n, Postgres.
- **Critical data:** customer personal data (name, national ID number, phone, address, email).
- **Risk:** **Medium** (personal data and customer impact; limited economic impact).
- **SLA:** first response within 24 business hours, resolution within 5 business days.
- **KPIs:** see 01_Scope_and_Glossary.md, section P2.

## 4. Automation inventory

Statuses as of 2026-11-09 (they match the database inventory, sql/19 and sql/20): A01 to A03 **in testing** (built and tested, switch never turned on) and A04 to A14 **active** (switch on). Version 1.0 for all 14.

| ID | Name | Process | What it does | Uses AI | Data it touches | Level | Risk | Owner | Version | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| A01 | Event logging | P0 | Records start, end, status, human intervention and cost of each execution | No | Execution metadata | L0 | Low | Systems Mgr. | 1.0 | In testing |
| A02 | Vault and pseudonymization | P0 | Stores the real personal data in a restricted table and replaces it with IDs (`cliente_id` (customer ID), `proveedor_id` (supplier ID)). Masks free text in 3 layers: patterns, matching against the own database and name detection. If it fails, nothing is sent to the AI | Local only | Personal data | L0 | High | Systems Mgr. | 1.0 | In testing |
| A03 | Policy engine and approvals | P0 | Decides whether an action is allowed, blocked or requires approval according to the level matrix (policy decision point and policy enforcement point) | No | Requested action and its level | L0 | High | Systems Mgr. | 1.0 | In testing |
| A04 | Supplier document intake and classification | P1 | Reads the mailbox, separates attachments and classifies them (invoice, credit note, debit note, other). Detects hidden text and injection phrases; anything suspicious and anything classified as "other" goes to the queue (A14) | Yes | Supplier document | L0 | Low | Admin. Mgr. | 1.0 | Active |
| A05 | Invoice extraction and validation | P1 | Reads the supplier document in order (PDF text, tax authority QR code, local OCR; if there is a QR code, it sends the QR code), validates tax ID, dates and amounts, matches against the purchase order and detects duplicates | Yes | Supplier document, PO, supplier master | L2 | Medium | Admin. Mgr. | 1.0 | Active |
| A06 | Bank account change detection | P0 / P1 | Detects requests to change the bank account number or a bank account number different from the registered one, blocks and alerts | Yes | Bank account number, supplier email | L4 | High | Admin. Mgr. | 1.0 | Active |
| A07 | Invoice approval for payment | P1 | Requests human approval before marking an invoice as ready to pay | No | Validated invoice | L3 | High | Admin. Mgr. | 1.0 | Active |
| A08 | Complaint intake and classification | P2 | Receives complaints from the channels, masks data (A02) and classifies by category and urgency. Detects requests for access, rectification or deletion of data and routes them to the Personal Data Owner | Yes | Complaint text (masked) | L0 | Medium | Customer Service Mgr. | 1.0 | Active |
| A09 | Routing and deadline tracking | P2 | Routes to the right area, monitors the SLA and escalates overdue items | No | Classified complaint | L1 | Medium | Customer Service Mgr. | 1.0 | Active |
| A10 | Suggested customer reply | P2 | Writes a draft reply that an agent reviews before sending | Yes | Complaint and resolution | L3 | Medium | Customer Service Mgr. | 1.0 | Active |
| A11 | Monitoring, circuit breaker and switch | P0 | Watches for failures, shuts down a flow after 3 consecutive errors and allows shutting down everything | No | Execution metadata | L0 | Medium | Systems Mgr. | 1.0 | Active |
| A12 | Weekly report | P0 | Builds the weekly summary of KPIs, incidents and costs for Management | Yes | Aggregated KPIs (no personal data) | L1 | Low | Process Analyst | 1.0 | Active |
| A13 | Controlled unmasker | P0 | Returns the real data from the ID or placeholder. Within an approved flow (for example, filling in the name in an already reviewed reply) it is automatic and logged. A manual lookup requires a reason and approval | No | Vault | L1 / L3 | High | Admin. Mgr. | 1.0 | Active |
| A14 | Human review queue | P0 / P1 / P2 | Receives whatever does not reconcile (unreadable QR code, tax ID or national ID number with no match, amounts, suspicious documents), shows it in a form and records the decision | No | Routed case (pseudonymized) | L0 (routes; a person decides) | Medium | Process Analyst | 1.0 | Active |

Relationship to Phase 8: A01 = 8.1, A02 = 8.2, A03 and A07 = 8.3, A04 to A06 = 8.4, A08 to A10 = 8.5, A11 = 8.6, A12 = 8.7, A13 and A14 = 8.8.

## 5. Data access matrix

**R** = reads · **M** = modifies · **A** = approves · **·** = no access

| Data | AP Analyst | Admin. Mgr. | Treasurer | Purchasing | Service agents | Service Mgr. | Branch manager | Systems Mgr. | n8n (automation) | External AI model |
|---|---|---|---|---|---|---|---|---|---|---|
| Supplier invoice | R, M | R, A | R | R | · | · | · | · | R, M | R (no bank account number) |
| Tax ID and legal name | R, M | R, A | R | R | · | · | · | · | R | R |
| Supplier bank account number | R | R, A, M | R | · | · | · | · | · | R (compare only) | · |
| Purchase order | R | R | · | R, M | · | · | · | · | R | R |
| Customer personal data | · | R | · | · | R, M | R | R | · | R, M | · (masked only) |
| Complaint text | · | · | · | · | R, M | R, A | R | · | R, M | R (masked) |
| Payment log | · | R, A | R, M | · | · | · | · | · | R | · |
| Audit log | · | R | · | · | · | · | · | R | M (append only) | · |
| Vault (real personal data) | · | R, A | · | · | R (own complaints only, via A13) | R (via A13) | · | · (administers the server, not the data) | R, M (A02 and A13 only) | · |

Rules that follow from the matrix:
1. The **AI model never sees** the bank account number or unmasked personal data.
2. The **bank account number can only be modified** by the Administration Manager, after verifying through a channel different from the one that requested the change (L4).
3. The **audit log** is append only, never edited or deleted.
4. Systems administers the infrastructure but **does not access business data**.
5. The **local model** (own server) is the only model that can see unmasked data, and only within A02 and A05. It does not keep copies.
6. **Re-identifying** data outside an approved flow requires a reason and approval from the Administration Manager (L3), and is logged.
7. **Power BI** and the reports work only with pseudonymized or aggregated data.

## 6. RACI by process

**R** = performs · **A** = accountable for the outcome · **C** = consulted · **I** = informed

| Activity | AP Analyst | Admin. Mgr. | Treasurer | Purchasing | Agents | Service Mgr. | Systems Mgr. | Process Analyst |
|---|---|---|---|---|---|---|---|---|
| P1: review invoice exceptions | R | A | · | C | · | · | · | I |
| P1: approve invoice for payment | C | R, A | I | · | · | · | · | I |
| P1: verify bank account change | · | R, A | I | C | · | · | I | I |
| P2: review and send reply | · | · | · | · | R | A | · | I |
| P2: escalate overdue complaints | · | · | · | · | C | R, A | · | I |
| P0: maintain automations | · | I | · | · | · | I | R, A | C |
| P0: measure KPIs and report | · | I | · | · | · | I | C | R, A |
| P0: respond to incidents | · | A | · | · | · | C | R | C |
| P0: approve manual re-identification | · | R, A | · | · | · | C | I | I |
| Review queue: resolve invoice cases | R | A | · | C | · | · | · | I |
| Review queue: resolve complaint cases | · | · | · | · | R | A | · | I |

---

## Pending to close Phase 2
- [x] Review and approval by the project author (2026-11-03).
