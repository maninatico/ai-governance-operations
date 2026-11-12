# Business Case. P2: Customer Complaints

Project: AI Governance in Operations. Fictional company: Cumbre Andina Building Supplies (a building materials distributor).
Version 1, 2026-11-09.

> The data is synthetic. This document shows the method and how the result behaves when assumptions change. These are not figures from a real company. Every number comes from the baseline (document 05_Data_Quality_and_Baseline.md) or from the test batch (documents 09_Test_Plan_and_Results.md and 10_KPI_and_ROI.md).

## 1. The problem

A complaint arrives through a messaging app, email or at the branch. A customer service agent reads it, notes it in a spreadsheet and routes it by hand to the department they think is responsible. Over 12 months, across 4,200 complaints:

- 15% go to the wrong department (measured by audit).
- 21.5% of customers wait more than one day for the first response (16.8 business hours on average).
- 20% are resolved outside the 5 business days. Nobody tracks the deadline.
- 7.7% are reopened, because the closure is not confirmed with the customer.
- Name, national ID number, phone and address travel in the text over the messaging app and email, with no control.
- Requests such as "delete my data" are classified as "Other" and may miss the legal deadline.

The most frequent reasons are delayed delivery (29%) and damaged material (18%).

## 2. What the automation does

The flow sends nothing to the customer. It leaves a draft for an agent to review.

1. It receives the complaint from the three channels and looks up the customer by national ID number or phone. If there is no match, it goes to the review queue.
2. It masks the text in three layers (patterns, cross-check against the internal database and name detection). If masking fails, the text does not go to the AI.
3. The AI classifies category and urgency. The output is a JSON that the code validates.
4. It detects requests for access, rectification or erasure of data and routes them to the Personal Data Officer, outside the complaints circuit.
5. It routes to the department using a fixed category-to-department table. The AI classifies and the rule routes.
6. It controls deadlines: it warns at 16 business hours and escalates overdue ones to the Customer Service Manager.
7. It drafts a reply with placeholders. The agent reviews and sends it.
8. On closing, it sends a confirmation with a fixed template, without AI. If the customer says it was not resolved, it is reopened with the same responsible person.

## 3. How risk is controlled

| Risk | Control | Automation |
|---|---|---|
| Wrong department | AI classification and routing by fixed rule | A08, A09 |
| Late response | Deadline alert and suggested draft | A09, A10 |
| Late resolution | Escalation of overdue cases to the Customer Service Manager | A09 |
| Reopenings | Confirmation to the customer on closing | A09 |
| Exposed personal data | Vault, pseudonymization and masking with fail safe | A02, A13 |
| Data subject rights requests | Detection and routing to the Personal Data Officer | A08 |
| Hidden instructions in a text | Defenses from document 06_Processes_AS-IS_TO-BE.md, section 3. The AI cannot execute anything | A08, A14 |
| Reply without review | Every draft is reviewed by an agent before sending (L3) | A10 |

## 4. What was measured

Test batch of 100 complaints:

| Result | Value |
|---|---|
| Correct category | 100 of 100 |
| Routed by the fixed table | 96 |
| Personal data requests diverted to the Officer | 4 of 4 |
| Drafts waiting for an agent's review | 92 |
| Drafts discarded for promising a deadline | 4 |
| Complaint with hidden instructions | 1, routed to the security queue (RL-001) |
| Drafts with a link placeholder to fill in ([LINK_FORMULARIO], form link) | 28 |

Time: the draft is ready in a little over 1 minute per complaint. This is an inference: the last run took 86.6 minutes and I assume it processed the 87 complaints that were missing. The actual first response depends on the agent's approval, and that time was not measured.

## 5. What it is worth in money

It is not converted into currency. The baseline has no complaint hours or costs to compare against, and putting a figure would be inventing it. What can be said with data: routing, today at a 15% error rate, moves to a fixed rule that got the category right in 100 of 100 complaints in the batch.

Complaints resolved on time and those that get reopened could not be measured in the prototype. Those two indicators need real customers and agents.

## 6. What changes for people

The agent stops deciding which department each complaint goes to and moves on to reviewing drafts. The Customer Service Manager sees overdue cases before the customer complains again. Requests about personal data reach the Officer automatically.

## 7. Limits

- Synthetic data and a fictional company.
- The final reply to the customer is not sent: it stays as a draft. The form link is fictitious.
- Resolution deadlines and reopenings were not measured.
- The batch has seeded trap cases. The proportion of cases that reach a person may be different in a real operation.
- With the AI down, the case goes to the queue with an unclear reason and may fill it with medium-priority cases.
- Who decides in the forms is chosen from a dropdown, without login.
- The sender of a malicious complaint and its origin are not recorded.
- Noted improvement: use an n8n form as the intake channel, with national ID number and phone in separate fields.

## 8. Where everything is

Baseline: `05_Data_Quality_and_Baseline.md`. Process before and after: `06_Processes_AS-IS_TO-BE.md`. Tests: `09_Test_Plan_and_Results.md`. After measurements: `10_KPI_and_ROI.md`.
