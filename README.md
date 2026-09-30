# Municipal Street Light Fault Tracking Database

A PostgreSQL database for a municipality that logs street light faults reported by citizens, assigns them to electrical
contractors by ward, and closes them only after verification by the ward engineer.

This is DBMS Case Study 17 (B.Tech CSE 2025-29, Semester III, Database Management System). The project is database-only:
schema, seed data, queries with outputs, an ER diagram, and written design documentation.

## Table of contents

1. [Problem statement](#problem-statement)
2. [Objectives and outcomes](#objectives-and-outcomes)
3. [Tech stack](#tech-stack)
4. [Repository contents](#repository-contents)
5. [Setup and how to run](#setup-and-how-to-run)
6. [Seed data summary](#seed-data-summary)
7. [Query index](#query-index)
8. [Design](#design-7-tables)
9. [Design decisions and rejected alternatives](#design-decisions-and-the-alternative-rejected)
10. [Requirement cross-check](#requirement-cross-check)
11. [Viva notes](#outcomes---short-answers-to-be-ready-for-the-viva)
12. [Known limits](#known-limits-honest-list)

## Problem statement

A municipality logs street light faults reported by citizens, assigns them to electrical contractors by ward, and closes
them after verification. The database must support the day-to-day working of the ward engineer and produce the reporting
needed at the close of every week. It must answer:

1. Which wards have more faults than the city average?
2. Are there any faults closed without verification?
3. Which contractors have no pending faults?
4. Which poles had more than two faults this year?
5. What is the oldest open fault in each ward?

## Objectives and outcomes

Objectives:
- Model poles, wards, fault reports, contractor assignments and closure verification so that no fault can be closed without verification.
- Write scalar, multi-row and correlated subqueries covering IN, NOT IN, EXISTS, NOT EXISTS, ANY and ALL.
- Rewrite at least two subqueries as joins and compare result, readability and intent.
- Apply core SQL in PostgreSQL: filtering, sorting, aggregates with GROUP BY and HAVING, joins and subqueries.
- Seed the database with realistic data volume.
- Record every design decision and the alternative that was rejected.

Outcomes the project is built to support: distinguishing correlated from uncorrelated subqueries, explaining the NULL trap in
NOT IN, deciding between subquery and join, and defending the design against a reasonable alternative.

## Tech stack

| Area | Choice |
|---|---|
| Database | PostgreSQL 18 (tested on macOS, installed with Homebrew) |
| Languages | Standard SQL and PL/pgSQL (trigger functions, DO blocks) |
| Client | pgAdmin 4 Query Tool; psql used for command-line testing |
| PostgreSQL features used | Identity columns, CHECK and UNIQUE constraints, composite primary keys, foreign keys, BEFORE triggers, regex CHECK, EXPLAIN, VALUES lists, EXCEPT / UNION ALL, ANY / ALL |
| Seed data | Generated once with a Python script using a fixed random seed, then stored as plain INSERT statements so results are repeatable |
| ER diagram | Drawn as SVG and rendered to PDF and PNG with headless Chrome |

There is no application or server code in this repository.

## Repository contents

| File | Purpose |
|---|---|
| `schema.sql` | Drops and recreates 7 tables, 3 trigger functions with 3 triggers, and 4 indexes. Safe to re-run |
| `seed.sql` | Loads the sample data, resets identity counters with `setval`, and runs `ANALYZE` |
| `queries.sql` | Every query with its real output pasted below it in a `/* OUTPUT ... */` comment. The file still runs top to bottom |
| `ER_diagram.pdf`, `ER_diagram.png` | The ER diagram in two formats |
| `subquery_vs_join.md` | Comparison note on subquery versus join for the same requirements |
| `README.md` | This file |

## Setup and how to run

Prerequisites: PostgreSQL 14 or later (developed on 18) and either pgAdmin 4 or psql.

### pgAdmin 4

1. Right-click **Databases** under your server, choose **Create > Database**, name it `streetlight`, and save.
2. Right-click `streetlight` and open **Query Tool**. Confirm the tab title shows `streetlight`.
3. Use **Open File** and run, in this order: `schema.sql`, `seed.sql`, `queries.sql`.
4. Verify with `SELECT COUNT(*) FROM fault_report;` which must return 204.
5. pgAdmin shows only the last result of a long script. To check a query, select that one query and press F5.
   The expected output is already printed under each query. Trigger messages from the Part F demos
   (`BLOCKED: ...`) appear in the Messages tab.

### psql

```
createdb streetlight
psql -d streetlight -f schema.sql -f seed.sql -f queries.sql
```

Re-running `schema.sql` wipes and rebuilds all tables, so run `seed.sql` again afterwards.

## Seed data summary

| Table | Rows |
|---|---|
| ward | 8 |
| contractor | 8 |
| contractor_ward | 12 |
| pole | 60 |
| fault_report | 204 (42 open, 162 closed) |
| fault_assignment | 199 |
| fault_verification | 162 |

Reports span 2025-09-01 to 2026-09-28. The data's "today" is 30 September 2026, and "this year" in the queries means 2026.
Faults are loaded as OPEN, then verifications are inserted, then the verified faults are closed in a single UPDATE. This
follows the real workflow and is required because the trigger rejects closing an unverified fault.

Deliberately planted so every question has a meaningful answer:
- City average is 25.5 faults per ward. Wards above it: Ganeshpeth 36, Itwari 34, Dharampeth 32, Sitabuldi 28.
- Contractor 7 (Metro Illumination) has only closed work and contractor 8 (NovaGrid Services) has never been assigned anything.
- 17 poles had more than 2 faults in 2026 (some have 8).
- Every ward has open faults of different ages. The oldest open fault overall is fault 1 in Itwari, reported 2025-09-01.
- 8 poles never had a fault.
- Open faults 200 to 204 are not yet assigned and are used by the demos.

## Query index

| Part | Content |
|---|---|
| A (A1-A5) | Core SQL: filtering and sorting, JOIN with GROUP BY, HAVING, LEFT JOIN, AVG/MIN/MAX |
| B (Q1-Q5) | The five questions from the problem statement, each with a check query where useful |
| C (C1-C9) | One example of each subquery kind: scalar, multi-row, correlated, IN, NOT IN, EXISTS, NOT EXISTS, ANY, ALL, plus an EXPLAIN plan |
| D (D1-D3) | Three subquery-to-join rewrites, each with a proof query that returns 0 rows when both versions agree |
| E (E1-E2) | The NULL trap: NOT IN returns nothing, NOT EXISTS returns the right answer |
| F (F1-F6) | Rule demos: blocked unverified closure, blocked wrong-ward assignment, blocked verification delete, blocked bad date, the correct workflow in a rolled-back transaction, and table row counts |

The Part D comparison is written up in `subquery_vs_join.md`.

## Design (7 tables)

```
ward 1---N pole 1---N fault_report 1---0..1 fault_assignment N---1 contractor
                          |                                          |
                          1---0..1 fault_verification      contractor N---N ward  (via contractor_ward)
```

| Table | Purpose | Key constraints |
|---|---|---|
| `ward` | Municipal ward + its engineer | PK, `ward_name` UNIQUE, `zone` CHECK |
| `contractor` | Electrical contractor | PK, name UNIQUE, phone UNIQUE + CHECK 10 digits |
| `contractor_ward` | Which contractor serves which ward | composite PK, 2 FKs |
| `pole` | Street light pole, inside one ward | PK, `pole_code` UNIQUE, FK ward |
| `fault_report` | Citizen's report | PK, FK pole, `status` CHECK, `chk_status_closed_on` CHECK |
| `fault_assignment` | Fault handed to a contractor | PK, `fault_id` UNIQUE + FK, FK contractor |
| `fault_verification` | Engineer's sign-off | `fault_id` is PK and FK |

### How "no fault can be closed without verification" is guaranteed
1. `fault_report` trigger `fault_close_needs_verification` refuses `status = 'CLOSED'` when no row exists in `fault_verification`.
2. `fault_verification` trigger `verification_delete_guard` refuses deleting the verification of a closed fault
   (otherwise a closed fault could be made unverified afterwards).
3. No `ON DELETE CASCADE` anywhere, so a verified fault cannot be wiped by deleting a parent row.
4. `chk_status_closed_on` CHECK: CLOSED has a `closed_on` date not earlier than `reported_on`; OPEN has none.

Proved in `queries.sql`: Q2 returns 0 rows, closed faults (162) = verifications (162), and Part F tries to break each rule.

## Design decisions and the alternative rejected

| # | Decision | Alternative rejected | Why |
|---|---|---|---|
| 1 | `fault_report` stores only `pole_id`; the ward is found through `pole` | Also store `ward_id` on the fault | A duplicate ward could disagree with the pole's ward. One fact, one place. Cost: Q1/Q3/Q5 need one extra join |
| 2 | Separate `contractor_ward` table (many-to-many) | `ward.contractor_id` (one contractor per ward) | Contractors here cover several wards and some wards have two. A single column cannot hold that |
| 3 | Verification is its **own table** with a trigger | `verified_by` / `verified_on` columns on `fault_report` with `CHECK (status <> 'CLOSED' OR verified_by IS NOT NULL)` | The CHECK version is simpler and needs no trigger - it is a fair choice. I chose the table because verification is a real event (who, when, remarks), Q2 becomes a meaningful question, and the exercise asks to "model closure verification". Cost: a trigger, which a superuser can disable |
| 4 | Two statuses only: `OPEN`, `CLOSED`. "Assigned" is derived from `fault_assignment` | Status values `REPORTED / ASSIGNED / IN_PROGRESS / CLOSED` | A stored "ASSIGNED" status can disagree with the assignment table. Fewer states = fewer ways to be inconsistent |
| 5 | `UNIQUE(fault_id)` in `fault_assignment`: one contractor per fault | Allow several rows per fault to keep re-assignment history | Keeps Q3 and "pending" unambiguous. Cost: no history of re-assignment (would be a future extension) |
| 6 | Trigger: a contractor may only get faults in a ward it serves | No check, trust the ward engineer | "Assigned by ward" is a business rule of the problem; a typo would otherwise hide a fault from the right contractor |
| 7 | Surrogate integer keys (`GENERATED ... AS IDENTITY`); `pole_code` kept as UNIQUE | Use `pole_code` as primary key | Codes can be re-labelled by the municipality; ids never change. Seed file resets the counters with `setval` |
| 8 | `DATE` columns | `TIMESTAMP` | Weekly reporting and "oldest fault" work at day level. Timestamps would add time-of-day noise. Cost: cannot rank two faults reported the same day |
| 9 | Closed faults are kept forever (no deletes) | Delete old faults | Audit trail and year-wise reporting |
| 10 | Seed loads faults as OPEN, inserts verifications, then closes them in one UPDATE | Insert faults already CLOSED | The trigger (correctly) rejects that. The seed follows the real workflow |
| 11 | "This year" written as `2026-01-01 <= date < 2027-01-01` | `EXTRACT(YEAR FROM reported_on) = 2026` or `CURRENT_DATE` | Range form can use an index and keeps the output repeatable. Change the year for next year |
| 12 | `NOT EXISTS` as the main answer to "no pending faults" | `NOT IN` | NULL trap (below). Both shown; only `NOT EXISTS` is always safe |
| 13 | Wards get faults through poles that are assigned unevenly in the seed | Uniform random data | Uniform data gives no ward "above average" and no poles with more than two faults, so the questions would return nothing interesting |

### Deliberately planted in the seed data (so every question has a real answer)
* Wards 1, 3, 4, 7 are above the city average (25.5 faults/ward) - Q1.
* Zero closed-without-verification faults - Q2 (and the triggers make it impossible).
* Contractor 7 has only closed work; contractor 8 has never been assigned anything - Q3.
* 17 poles with more than 2 faults in 2026 (some with 8) - Q4.
* Every ward has open faults with different ages; oldest is 2025-09-01 in Itwari - Q5.
* 8 poles never had a fault - `NOT IN` example C3.
* 5 open faults are not yet assigned (200-204) - used by C4 and the Part F demos.

## Requirement cross-check

| Requirement from the case study | Where it is met |
|---|---|
| Q1 wards above city average | `queries.sql` Q1 (scalar uncorrelated subquery) |
| Q2 faults closed without verification | Q2 (NOT EXISTS), 0 rows; prevented by trigger; Part F1, F3 |
| Q3 contractors with no pending faults | Q3 (NOT EXISTS and NOT IN), D2 |
| Q4 poles with more than two faults this year | Q4 (GROUP BY/HAVING and IN version) |
| Q5 oldest open fault in each ward | Q5 (correlated), D3 |
| Model poles, wards, faults, assignments, verification | 7 tables in `schema.sql`; ER diagram |
| No fault closed without verification | 2 triggers + CHECK; Q2; Part F |
| Scalar subquery | Q1, C1 |
| Multi-row subquery | C2, C3, Q4-alt |
| Correlated subquery | Q2, Q3, Q5, C4 |
| IN | C2, Q4-alt |
| NOT IN | Q3 (2nd query), C3, Part E1 |
| EXISTS | C4 |
| NOT EXISTS | Q2, Q3, D2-a, E2 |
| ANY | C6 |
| ALL | C7, C8 |
| Rewrite at least two subqueries as joins and compare | Part D (three pairs with proof of equal results) + `subquery_vs_join.md` |
| Core SQL: filtering, sorting | A1, A4 |
| Aggregates, GROUP BY, HAVING | A2, A3, A5, Q4, C7 |
| Joins (inner, left) | A2-A5, D1-b, D2-b, D3-b |
| PostgreSQL | Identity columns, `DO` blocks, triggers in plpgsql, `::numeric`, `EXPLAIN` |
| Realistic data volume | 204 fault reports etc. (F6 counts every table) |
| Design decisions and rejected alternative | Table above |
| ER diagram PDF/image | `ER_diagram.pdf`, `ER_diagram.png` |
| schema.sql / seed.sql / queries.sql with output / README | Present |
| Focus deliverable: subquery vs join note | `subquery_vs_join.md` |

## Outcomes - short answers to be ready for the viva

**Correlated vs uncorrelated.** An uncorrelated subquery does not refer to the outer query, so it has one answer and
is evaluated once (Q1: the city average). A correlated one refers to a column of the current outer row (Q5: `p.ward_id`)
so its answer depends on the row and, logically, it is evaluated for each outer row. PostgreSQL's planner often rewrites
`EXISTS` / `IN` into a join internally (see the `EXPLAIN` in C9 and `subquery_vs_join.md`), but Q5's correlated `MIN` stays a per-row SubPlan.

**The NULL trap.** `NOT IN` over a list containing one NULL returns no rows, because `x <> NULL` is UNKNOWN. `NOT EXISTS`
just asks whether a matching row exists, and NULL never matches, so it stays correct. Demonstrated live in Part E.

**Subquery clearer than join, and when not.** Clearer when you only need "does a match exist" (IN / EXISTS / NOT EXISTS) or
compare with one overall value (Q1) - a join would duplicate rows or need a cross join. Join is better when you need columns from
the other table or the subquery is correlated on a large table ("best row per group").

**Defending the design.** The strongest alternative is the `CHECK` on `fault_report` instead of a verification table (decision 3).
It is simpler and safer against someone disabling a trigger. The chosen design wins on modelling the verification as a real
event with its own data and on making Q2 a real question; it loses on needing a trigger.

## Known limits (honest list)
* Triggers can be disabled by a superuser (`ALTER TABLE ... DISABLE TRIGGER`). For a real system, restrict privileges.
* A closed fault is not forced to have an assignment (the problem statement only requires verification). A trigger could add that.
* Reassignment history is not kept (decision 5).
* Q5 returns all faults that tie on the oldest date in a ward (the seed has none).
