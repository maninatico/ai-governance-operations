# Phase 7. Database

**Project:** AI Governance in Operations: KPIs, ROI and process control with Power BI
**Case:** Cumbre Andina Building Supplies (fictional company, synthetic data)
**Version:** 1, approved 2026-11-05

---

## In brief

| | |
|---|---|
| **Input** | The clean data from Phase 5, the inventory and access matrix from Phase 2, the policies from Phase 3 and the TO-BE processes from Phase 6 |
| **What it does** | Creates a Postgres database in 3 zones, users with least-privilege permissions per flow, KPI views for Power BI, and loads the history with masked texts |
| **Output** | 5 SQL scripts, the load script, a docker-compose file that starts everything with one command, and this document |

**Core idea:** governance rules do not depend on someone remembering them: the database itself enforces them.

---

## 1. Three zones

| Zone | Schema | What it stores | Who has access |
|---|---|---|---|
| Vault | `boveda` (vault) | Real personal data of customers, tax ID and name of individual suppliers, bank account number, placeholder mapping | Only A02 and A13, and the Manager to register a bank account number |
| Business | `negocio` (business) | Suppliers, customers (ID only), purchase orders, supplier documents (invoices), complaints with masked text | The flows, according to their process |
| Control | `control` | A01 to A14 inventory, executions, audit, approvals, review queue, re-identifications, incidents, switches | The flows write records; monitoring reads |
| Reports | `reportes` (reports) | KPI views with pseudonymized or aggregated data | Power BI and monitoring |

17 tables: 4 in the vault, 5 in business and 8 in control.

**Individual suppliers:** a single master table with the `tipo_persona` (person type) flag. If the supplier is an individual, their tax ID (which contains the national ID number) and their name go to the vault. The database rejects loading it any other way.

## 2. Rules enforced by the database

| Rule | How |
|---|---|
| The audit log cannot be edited or deleted | A trigger rejects UPDATE, DELETE and TRUNCATE, also for the administrator |
| A self-employed supplier cannot have their tax ID in the master table | Constraint `datos_segun_tipo` (data according to type) |
| Payment of more than 5,000,000 local currency units requires dual control | Constraint `doble_control` (dual control): without a second approver it cannot be approved |
| Manual re-identification only with approval | Constraint `manual_aprobada` (manual approved) |
| Only one active bank account number per supplier; the history is not overwritten | Partial unique index; the Manager can only close the previous bank account number and load a new one |
| A review queue case cannot be closed without a decision and a responsible person | Constraint `resolucion_completa` (complete resolution) |
| Every approval has an expiry; silence does not approve | `vence` (expires) is mandatory, `decision` stays empty until a person decides |

## 3. Users with least-privilege permissions

| User | Can | Cannot (tested) |
|---|---|---|
| n8n_facturas | Read suppliers and purchase orders, register supplier documents, request approvals | View or change bank account numbers, view customers |
| n8n_reclamos | Read customers (ID) and manage complaints | View invoices, enter the vault |
| n8n_boveda | Pseudonymize, mask, re-identify | View bank account numbers |
| n8n_cola | Resolve cases and update the document status | Anything outside the review queue |
| n8n_monitoreo | Read control, switch off flows, register incidents | Delete the audit log |
| powerbi_lector | Read the reports views | View business or vault tables |
| gerente_adm | Register a new verified bank account number | Overwrite an existing bank account number |

**Bridge functions:** they allow using a vault value without being able to read it. `cbu_coincide` (bank account number matches) answers only yes or no; `buscar_cliente` (find customer) and `buscar_proveedor` (find supplier) return only the ID.

**Passwords:** randomly generated in a local `.env` file, which is not shared or uploaded to GitHub. If any is missing, the database is not created (fail safe).

## 4. History load

| Table | Rows |
|---|---|
| Suppliers and bank account numbers | 120 |
| Customers (business and vault) | 8,000 |
| Purchase orders | 9,849 |
| Supplier documents (invoices) | 11,124 (10,800 originals + 324 duplicates) |
| Complaints | 4,200 |

**Complaint masking:** 2,551 complaints contained personal data (60%). 6,328 values were replaced by placeholders in 2 layers: matching against the database itself and patterns. The third layer, name detection, is implemented in A02 (Phase 8). If any customer data remains after masking, the load stops and saves nothing.

**Verification:** the reports views produce exactly the same KPIs as the Phase 5 baseline (difference 0 in all 12 months), for example 166 invoices paid twice.

## 5. Installation

Everything runs in Docker, on the local machine, without modifying n8n:

| Container | Function |
|---|---|
| cumbre_andina_db | Postgres 16. Port 5433, accessible only from the local machine |
| cumbre_archivos | File server that simulates the mailbox: publishes only `lote_prueba` (test batch), read-only. The `verdad` folder is not published |
| cargador | Single-use container (loader) that loads the history |

The first two join the n8n network (`migracion-docker_default`). n8n is not restarted or changed. The 9 switches (8 flows plus the general one) start switched off.

**Verified on the local machine on 2026-11-05:** passwords defined for 7 users, load confirmed, KPI = 166, 9 switches off, n8n reads the files and reaches the database.

## 6. Files

| File | Content |
|---|---|
| sql/01_esquema.sql | Schemas, tables and constraints |
| sql/02_roles.sql | Bridge functions, roles and users |
| sql/03_vistas.sql | KPI and governance views for Power BI |
| sql/04_inventario.sql | A01 to A14 inventory and switches |
| sql/06_politicas.sql | Policy and approval engine (added in Phase 8.3) |
| sql/09_contrasenas.sh | Passwords from the `.env` file |
| scripts/cargar_base.py | History load with masking |
| docker-compose.yml, .env.example, .gitignore | Installation |

## 7. For the publication (assembled at the end of the project)

**Summary:** the database does not trust people to follow the rules: it enforces them. Nobody can delete the audit log, approve a large payment without dual control or see a bank account number that is not theirs, not even by mistake. Power BI sees only pseudonymized data.

---

## Pending
- [x] Review and approval by the project author (2026-11-05).
