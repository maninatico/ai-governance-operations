# Phase 3. Policies

**Project:** AI Governance in Operations: KPIs, ROI and process control with Power BI
**Case:** Cumbre Andina Building Supplies (fictional company)
**Version:** 1.1, 2026-11-03 (approved adjustment: personal data vault, pseudonymization, local model and tax authority QR code)

> Fictional case. These policies follow a general reference framework (the applicable national personal data protection law and cybercrime law, ISO/IEC 42001, ISO/IEC 27001, NIST AI RMF). They do not constitute legal advice. In a real project they are adjusted with the company's legal advisor.

The policies apply to all automations in the inventory (A01 to A14) and are reviewed every 6 months or after a serious incident.

---

## 1. Personal data policy

### Principles
1. **Purpose:** data is used only for the purpose for which it was collected (handling complaints, paying suppliers).
2. **Minimization:** each automation uses only the data it needs.
3. **Quality:** data is validated on entry (format of national ID number, tax ID, phone, email).
4. **Security and confidentiality:** access follows the matrix from Phase 2; nobody sees data they do not need for their task.
5. **Data subject rights:** a customer can request access, rectification, update or deletion of their data. The request is handled by the Personal Data Officer (Administration Manager). A08 detects these requests when they arrive as a complaint and routes them out of the complaints flow.

### Vault, pseudonymization and masking
- Real personal data lives only in the **vault**, a restricted table. The working database uses IDs: cliente_id (customer ID, derived from the national ID number) and proveedor_id (supplier ID, derived from the tax ID).
- If a national ID number or tax ID does not match the database, the case goes to the **human review queue** (A14). An ID is never created by guessing.
- Before sending free text to an external model, A02 replaces national ID number, phone, email, address and name with placeholders (for example: [DNI_1], [TEL_1]), in 3 layers: patterns, cross-check against the company's own database and name detection.
- The mapping between placeholder and real data stays only in the vault and never leaves it.
- If masking fails, the text is **not sent** to the model: the error is logged and the case is routed to a person (fail safe).
- **Re-identification (A13):** within an approved flow it is automatic and logged; outside a flow it requires a stated reason and approval from the Administration Manager.

### AI providers
- **External models** (cloud services, including any AI assistant used for analysis): receive only pseudonymized or masked data, or business data without personal information.
- **Local model** (Ollama on the company's own server): the only one allowed to process unmasked data, and only within A02 and A05, without keeping copies. Before enabling it, it is verified that the model runs on the company's own server and not in the provider's cloud.
- **Power BI** and any dashboard or report work only with pseudonymized or aggregated data.
- Before enabling an AI provider, its data use terms are reviewed (whether it stores the data or uses it for training).

### Retention and deletion

| Data | Retention period | What happens at expiry |
|---|---|---|
| Personal data from complaints | 2 years from complaint closure | Anonymized; only statistical data remains |
| Complaint text and photos | 2 years from closure | Deleted |
| Supplier documents (invoices) | According to current tax and accounting periods | Archived |
| Execution log | 1 year | Aggregated into statistics and deleted |
| Audit log | 5 years | Archived |
| Vault and masking mapping table | Same as the original data | Deleted together with it |

The periods are case parameters. In a real project they are defined with the legal and accounting departments.

## 2. AI use policy

### Permitted uses
- Classifying documents and messages.
- Extracting data from supplier documents (invoices).
- Summarizing information and detecting patterns.
- Writing drafts that a person reviews.

### Prohibited uses
- Deciding payments or approving invoices.
- Modifying suppliers' bank details.
- Sending replies to customers without human review.
- Sending unmasked personal data to an external model.
- Making decisions about people (employees, customers) that directly affect them.

### Technical requirements
1. **Structured output:** the model answers in a fixed format (JSON) and the output is validated by code before use.
2. **Critical rules in code, not in the AI:** amounts, tax ID, duplicates, permissions and control levels are checked with programmed rules. The AI cannot bypass them.
3. **External content as data, not as commands:** the text of emails, PDFs, images and messages is never treated as an instruction. Defenses:
   - The AI has no permission to execute anything: it only returns fixed fields that the code validates.
   - The extracted text is compared with what is visible (OCR of the page): hidden text, text the same color as the background, tiny font or text outside the page marks the document as suspicious.
   - What the code has already resolved (QR, tax ID, bank account number) is not sent to the model.
   - A detector of typical injection phrases works as an additional alarm.
   - The system instructions declare the document to be data.
   Every suspicious document goes to the human review queue (A14) with the reason written down.
4. **Versioned instructions:** each prompt has a version and date, and its changes follow the change policy.
5. **Recorded cost:** each model call records its cost in the execution log.
6. **Approved models:** only the models listed in the inventory are used. Changing models is a change that is tested first.
7. **Reading supplier documents:** first the PDF text, then the tax authority QR code, then local OCR. If there is a QR code, the QR code prevails. Whatever does not reconcile goes to the human review queue (A14).

## 3. Human approval

| Action | Level | Who approves | Response deadline | If no response |
|---|---|---|---|---|
| Approve an invoice for payment | L3 | Administration Manager | 1 business day | Escalated to the Managing Partner; the invoice is not approved |
| Approve an invoice above the threshold (parameter: 5,000,000 local currency units) | L3 + dual control | Administration Manager and Managing Partner | 1 business day | Stays on hold; not approved |
| Send a reply to a customer | L3 | Customer service agent (draft review) | Within the first-response SLA | Escalated to the Head of Customer Service |
| Re-identify data outside an approved flow (A13) | L3 | Administration Manager | 1 business day | Not re-identified |
| Resolve a review queue case (A14) | L3 | Accounts payable analyst (invoices) or agent (complaints) | Within the process SLA | Escalated to the process owner |
| Change a supplier's bank account number | L4 | Administration Manager, verifying through a channel different from the one used for the request | Not applicable | The automation only alerts; it never changes the data |
| Reactivate a flow shut off by the circuit breaker | L3 | Systems Manager | 1 business day | Stays off |

**Rule:** silence is never a yes. Every approval is logged with who, when and what was decided.

## 4. Change management

1. **Versioning:** each automation and each prompt has a version (for example 1.0, 1.1, 2.0) and a date.
2. **Test before activating:** every change is tested first on a copy of the flow marked PRUEBA, with synthetic data.
3. **Checklist before activating:**
   - [ ] Tested with normal cases and with the traps.
   - [ ] No credentials or sensitive data in notes or nodes.
   - [ ] Event log (A01) working.
   - [ ] Inventory updated (version and status).
   - [ ] Approved by the process owner.
4. **Backup** of n8n before activating.
5. **Rollback:** the previous version is saved as an export so it can be restored.
6. **Change log:** date, what changed, why and who approved it.

## 5. Incident response

### Severity

| Severity | Examples | Target containment time |
|---|---|---|
| **S1. Critical** | Improper payment, undetected fraud, exposed personal data | Immediate (under 1 hour) |
| **S2. High** | A flow fails repeatedly, unprocessed invoices or complaints | Under 4 business hours |
| **S3. Medium or low** | Isolated fixable error, isolated misclassification | Under 2 business days |

### Steps
1. **Detect:** by automatic alert (A11), by user report or by review.
2. **Contain:** shut off the affected flow or use the master switch.
3. **Assess:** what happened, what data or amounts are involved, since when.
4. **Notify:** the process owner and the Systems Manager. If personal data is involved, the Personal Data Officer, who assesses notification to the supervisory authority and to the affected people as appropriate.
5. **Fix:** correct the cause, test and reactivate following the change policy.
6. **Document:** incident record with timeline, cause, impact and actions.
7. **Learn:** review whether a control, a policy or the risk level needs to change.

### Measurement
Number of incidents by severity, detection time, containment time and resolution time. They are added to the Power BI dashboard.

---

## Pending to close Phase 3
- [x] Review and approval by the project author (2026-11-03).
