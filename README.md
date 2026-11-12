# AI Governance in Operations: KPIs, ROI and Process Control with Power BI

Portfolio project. It shows, through a complete and measurable case, how administrative processes can be automated with AI **under governance**: an inventory of automations, an owner for every piece of data, risk ratings, controls, measurement with KPIs and ROI, and a Power BI dashboard.

> **Everything is fictional.** The company (Cumbre Andina Building Supplies, a construction materials distributor), the people and the data are synthetic. The figures demonstrate the method and how the outcome behaves when assumptions change. They are not results from a real company. The reference frameworks (ISO/IEC 42001 and 27001, NIST AI RMF, EU AI Act and the applicable national personal data protection law) are used as general guidance ("aligned with"), not as certification or legal advice.

## What it automates

- **P1. Supplier invoices:** email intake, classification, data extraction (PDF text, tax authority QR code, local OCR), validations, bank account verification, registration and payment approval.
- **P2. Customer complaints:** intake, classification, routing to the right team, deadline tracking and a draft reply.
- **P0. Security and data (cross-cutting):** event logging and kill switches, vault and pseudonymization of personal data, policy and approval engine, monitoring with a circuit breaker, weekly report, human review queue and controlled re-identification.

There are 14 automations (A01 to A14), built in n8n.

## Design principles

1. Code handles everything that cannot be wrong (amounts, tax IDs, bank account numbers, dates). The AI only classifies or drafts.
2. Anything that does not add up goes to a human review queue with the reason written down. Silence never counts as approval.
3. Fail safe: if something breaks, the system stops and leaves a record.
4. Least privilege: every flow has its own database user with only the permissions it needs.
5. The AI models run on a self-hosted server (Ollama, local model). Real personal data lives in a restricted vault, and the rest of the flows only see placeholders.

## Measured results on the test batch

A batch of 153 supplier emails and 100 customer complaints (details and assumptions in `10_KPI_and_ROI.md`):

- **Invoices:** 136 registered, 11 sent to the review queue, 4 blocked by the bank account check and 2 flagged as suspicious for hidden text. All 17 seeded traps reached a person. Flow errors: 0.
- **Complaints:** correct category in 100 of 100, 96 routed through a fixed table, and 4 requests for personal data diverted to the designated responsible person.
- **Projected annual net benefit (base scenario):** 98.8 million, in nominal local currency units. Of that, 84.4 million comes from duplicate payments avoided. The most sensitive assumption is how many duplicates get stopped: if detection matches the manual process, ROI drops to 88% and payback stretches to 6.4 months. In the worst combined case the investment is not recovered.

## Repository structure

| Folder or file | Contents |
|---|---|
| `01` to `07` | Scope, fictional company, catalog and risk inventory, policies, baseline, processes before and after, database schema |
| `09_Test_Plan_and_Results.md` | Test plan, results and forced failures |
| `10_KPI_and_ROI.md` | KPIs before and after, ROI, sensitivity analysis and limits |
| `sql/` | Schema, roles, views, inventory, policies and each build phase (01 to 19), in order |
| `scripts/` | Data generation and cleaning, baseline, ROI calculation, permission tests, switches |
| `datos/` | Synthetic data: history, cleaned data, test batch, ground truth, dashboard data and data dictionary |
| `lector/` | Service that reads supplier documents without any external AI |
| `n8n_codigo/flujos/` | n8n flows exported as JSON, without credentials |
| `notebooks/` | Baseline notebook |
| `docker-compose.yml`, `.env.example` | Environment: database, batch file server and reader |

## How to run it

Requirements: Docker, a running n8n instance and the passwords defined in `.env`.

1. Copy `.env.example` to `.env` and set the passwords. That file is never shared or committed.
2. From the project folder run `docker compose up -d` (database with schema, users and views, file server and reader).
3. Load the cleaned history: `docker compose --profile carga run --rm cargador`.
4. Import the flows from `n8n_codigo/flujos/` into n8n and create the Postgres credentials (the exports do not include them).

The database is reachable only from the local machine (port 5433, `127.0.0.1`). From n8n it connects through the Docker network (host `cumbre_andina_db`).

## How to repeat the tests and calculations

- **Flows:** every flow has its own test in n8n (`CA_<phase>_PRUEBA`). Open it and run it: it returns PASS or FAIL with the details. Test data carries the `PRUEBA-` prefix and real queries exclude it.
- **Database permissions and rules:** `scripts/pruebas_permisos_y_reglas.sql` (59 cases, rolled back at the end).
- **After-state measurement:** `sql/17_medicion_despues.sql` (read-only).
- **ROI and sensitivity:** `python3 scripts/calcular_roi.py`. The assumptions sit at the top of the script, in one place. With `--csv` it regenerates the two files that feed the dashboard.

## Power BI dashboard

The Power BI report file is not included in this repository. It connects to the database through a read-only user (`powerbi_lector`) that can only see the `reportes` schema, and to two ROI CSV files in `datos/tablero/`. It has six pages: Summary, Invoices, Complaints, Governance (switches and inventory), ROI and sensitivity, and Queue and incidents.

## Declared limitations

What the project does not do or does not test, stated plainly:

- Synthetic data and a fictional company: the method is defensible, the figures are not. No inflation adjustment: amounts are nominal for one year.
- The batch has 17 seeded traps among 153 emails. The share of cases that reach a person could differ in a real operation. Duplicate detection was measured on only 3 cases.
- "Who decides" in the approval forms is a dropdown, not a login.
- The sender of an attacked document and its origin are not recorded. A real company would store sender, domain and fingerprint, and keep a blocklist.
- The final reply to the customer is not sent: it stays as a draft. The approval form link is fictional.
- Complaint benefits are not converted to money because the baseline has no hours or costs for complaints.
- Human waiting times (approvals and queue) were not measured: there are no real people deciding.
- Assumptions without a source (server, maintenance, contracted development, payroll burden factor) are project decisions and are marked as such in `10_KPI_and_ROI.md`.
- The review queue has 70 pending cases and may include old test cases that do not carry the `PRUEBA-` prefix. Cleanup pending.
- Switches 8.1, 8.2 and 8.3 have been off since the initial load and no real flow queries them.
