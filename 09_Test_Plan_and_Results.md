# 09. Test Plan and Results (Phase 9)

Project: AI Governance in Operations, fictional company Cumbre Andina Building Supplies.
Scope: automations A01 to A14 built in Phase 8, the database and its permissions.

## 1. What was tested and how

Testing was done at four levels:

1. **Automated tests per flow.** Each flow has a test flow in n8n (named `CA_<phase>_PRUEBA`, where PRUEBA means test) that runs known cases and returns PASS or FAIL with the detail.
2. **Database tests.** Functions and permissions were tested with SQL inside a transaction that is rolled back (ROLLBACK), so no data is left behind.
3. **Trap tests.** Each problem from the diagnosis (document 06) is matched against the control that covers it, and the defenses against instructions hidden in texts were tested.
4. **Forced failures.** Something was deliberately broken to check whether the system fails safe and leaves a record.

Design rule that guides the tests: code handles what cannot be wrong, the AI only classifies or drafts, and anything that does not reconcile goes to the review queue with the reason written down. Silence never counts as a yes.

Test data carries the prefix `PRUEBA-` (test), and real queries exclude it.

## 2. Results per flow

| Flow | What it tests | Result |
|---|---|---|
| 8.1 Event log and switches | General and per-flow switch, fail safe | 4 of 4 PASS |
| 8.2 Vault and pseudonymization | Sensitive data replaced by placeholders | 6 of 6 PASS |
| 8.3 Policy engine and approvals | Approval levels by amount and rules | 7 of 7 PASS |
| 8.4a Supplier document intake | Registration of supplier documents and duplicates | 7 of 7 PASS |
| 8.4b Reading and validation | Reading and validation of the invoice | 11 of 11 PASS |
| 8.4c Bank account number verification | Match of the bank account number with the supplier | 6 of 6 PASS |
| 8.4d Payment approval | Request and update of approvals | 4 of 4 PASS |
| 8.5a Complaint intake and classification | Batch of 100 complaints | Full run completed, see section 3 |
| 8.5b Routing and deadlines | Routing to the right person and deadlines | 10 of 10 PASS |
| 8.5c Draft response | Draft written by the AI without sending anything | 4 of 4 PASS |
| 8.6 Monitoring and alerts | Circuit breaker cuts a flow after 3 consecutive errors | 8 of 8 PASS |
| 8.6b Alert delivery | Email alerts | 3 of 3 PASS, plus case C4 |
| 8.7 Weekly report | Report assembly | 6 of 6 PASS |
| 8.8a Review queue | Cases that do not reconcile go to a person | 8 of 8 PASS in n8n, 25 of 25 in SQL |
| 8.8b Unmasker | Request for real data with approval | 8 of 8 PASS in n8n, 24 of 24 in SQL |
| 8.8c Manual lookup | Viewing a real data point with Manager approval | 16 of 16 in SQL, plus a full manual walkthrough |
| Central error log (Phase 9) | A failure leaves a row in `control.ejecuciones` (control.executions) | 4 of 4 PASS |
| Batch with a broken item (Phase 9) | The batch continues and the failure is logged | 5 of 5 PASS |

Database permissions and rules (`scripts/pruebas_permisos_y_reglas.sql`, 59 cases, rolled back when finished): permissions 49 of 49, rules 10 of 10.

## 3. Batch of 100 complaints

Run with the test batch of 100 complaints:

- 17 trap cases reached a person (none was resolved automatically).
- 0 flow errors.

## 4. Traps and defenses

The traceability from problem to control is in document 06, section 4. Each problem in the diagnosis has an assigned control and a test that exercises it.

Defenses against instructions hidden in a text (injection): five were tested, and in all of them the system kept its behavior and sent the case to review when appropriate. The detail of each one is in the test flows 8.4a and 8.5.

## 5. Forced failures of Phase 9

**5.1 Database permissions.** The test battery found a real gap: the invoice flow user could write the decision into `control.aprobaciones` (control.approvals). It was fixed with `sql/16_ajuste_permisos_aprobaciones.sql` (permissions adjustment for approvals; removes INSERT and UPDATE from `rol_flujo_facturas`, the invoice flow role). After the fix, the battery gave 49 of 49.

**5.2 Backup restore.** The dump was restored into an empty database (`restore_test`) and compared with the real database: 23 tables out of 23. The row differences were the expected ones, because the real database kept receiving records after the dump (approvals, audit, queue, executions and supplier documents). The test database was then deleted.

**5.3 Switch off.** With the 8.8 switch off, the three forms (queue, request lookup, view data) answered "off" and neither showed nor did anything. When it was switched back on, they resumed. The change is audited with `scripts/cambiar_interruptor_8.8.sql` (change switch 8.8).

**5.4 AI down.** An AI service outage was simulated with a dead address. Finding: the flow stopped with an error and left partial traces (a complaint saved without a category and loose records). Fix: the four nodes that call the AI (`CA84a_Clasificar_IA`, `CA85a_Clasificar_IA`, `CA85c_Redactar_IA` and its copy) now continue with normal output when the AI fails, and the case is routed to the queue. Regression after the fix: 8.4a 7 of 7, 8.5c 4 of 4.

**5.5 Central error log.** A single flow (`CA_9_Registro_de_errores`, error log) receives the failure from any of the 21 real flows and writes an `error` row in `control.ejecuciones`, linked to its automation. It stores only the name of the last node and the first line of the message (maximum 300 characters), with no document data. Tested with a forced failure: 4 of 4.

**5.6 Broken document in the middle of a batch.** A batch of 3 items with the middle one failing on purpose: the batch finished all 3, items 1 and 3 came out fine, item 2 was marked as an error, and the central log added exactly one new row with only the failure message. Result 5 of 5.

Scope of this test: it uses a simulated batch with the same pattern as orchestrator 8.4 (each call to a subflow continues with normal output if it fails). It did not run the real orchestrator with a broken document. It was verified by configuration that the four subflow calls of orchestrator 8.4 have that behavior.

## 6. Findings

1. Permissions gap in `control.aprobaciones` (fixed, section 5.1).
2. An AI outage left partial traces (fixed, section 5.4).
3. A central error log was missing: failures left no row in `control.ejecuciones` (built, section 5.5).

## 7. Declared limits

What this project does not do or does not test, stated plainly:

- The sender of a malicious complaint or invoice and its origin are not recorded.
- "Who decides" is a dropdown, not a login. In a real company it would be the authenticated user.
- The review queue (A14) does not log its executions in `control.ejecuciones`.
- The final response to the customer is not actually sent: it stays as a draft.
- The approval form link is fictional (`.example` domain) and form 8.3 is still in draft mode.
- The 8.4a tests without the `PRUEBA-` prefix count as real in the weekly report.
- The users `n8n_facturas` (n8n invoices) and `n8n_reclamos` (n8n complaints) can still modify their own business tables directly.
- With the AI down, the case goes to the queue with an unclear reason ("the AI answered: nothing") and can fill the queue with medium-priority cases.
- 8.8c has no automated test in n8n: it was tested in SQL (16 of 16) and with a full manual walkthrough.
- Rows in the central error log from real flows are left with an empty `documento_id` (document id). Only test rows carry the prefix `PRUEBA-ERR-`.
- Pending: the queue scheduler (8.8b Scheduler) and the approval expirations, which remain off until Phase 10 is closed.

## 8. How to repeat the tests

1. n8n test flows: open the `CA_<phase>_PRUEBA` flow and click Execute workflow. The 8.8b ones first need `scripts/preparar_prueba_8.8b.sql` (prepare test 8.8b) with a new prefix (`-v p="PRUEBA-8B-<date>-"`).
2. Permissions and rules battery: `scripts/pruebas_permisos_y_reglas.sql` from the terminal, with the database container running. It rolls back on its own.
3. Error log: `CA_9_PRUEBA_Registro_de_errores` and `CA_9_PRUEBA_Lote_con_falla`. Wait 3 minutes between runs, because they count rows from the last 3 minutes.
