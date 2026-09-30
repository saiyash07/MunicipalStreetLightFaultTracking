# Subquery vs Join - Comparison Note

Case Study 17 - Municipal Street Light Fault Tracking (PostgreSQL)

Three requirements were written **twice**: once with a subquery and once with a join.
All SQL and outputs are in `queries.sql`, Part D. After each pair there is a proof query
`(A EXCEPT B) UNION ALL (B EXCEPT A)`, and all three return **0 rows**, meaning the two
versions return exactly the same rows.

## Pair 1 - "Which contractors hold at least one open fault?" (IN  vs  JOIN)

| | Subquery (`IN`) | Join |
|---|---|---|
| Query | `WHERE contractor_id IN (SELECT ... open faults)` | `contractor JOIN fault_assignment JOIN fault_report` |
| Result | 6 contractors | 6 contractors, **only after adding `DISTINCT`** |
| Readability | Reads like the question: "contractor is in the list of people with open faults" | Reader must notice `DISTINCT` and ask why it is there |
| Intent | Says "existence check" - we only want to know *whether* a match exists | Says "combine rows" - but we don't want the combined rows, only the contractor |
| Risk | None | Without `DISTINCT`, contractor 1 appears 10 times (shown in `queries.sql`, D1-b second query) |
| Plan in PostgreSQL | Hash Join + HashAggregate on the inner list | Hash Join + HashAggregate for the `DISTINCT` |

**Verdict: the subquery is clearer.** The join fans out rows and needs `DISTINCT` to undo it.
PostgreSQL produces almost the same plan for both, so there is no speed reason to prefer the join.

## Pair 2 - "Which contractors have NO pending faults?" (NOT EXISTS  vs  LEFT JOIN ... IS NULL)

| | Subquery (`NOT EXISTS`) | Join (`LEFT JOIN ... WHERE x IS NULL`) |
|---|---|---|
| Result | Contractors 7 and 8 | Contractors 7 and 8 |
| Readability | "there does not exist an open fault for this contractor" - matches the English | The "anti-join" trick: join, then keep rows where the join found nothing. Needs a comment to be understood |
| Intent | Clear | Hidden behind a NULL test |
| Risk | None. NULLs cannot break it | The `status = 'OPEN'` filter must be in the `ON` clause / inner query. Put it in `WHERE` and the NULL rows are discarded and **0 rows** come back - silently wrong |
| Plan in PostgreSQL | Anti Join | Anti Join (the planner recognises the pattern) |

**Verdict: `NOT EXISTS` is clearer and safer.** Both compile to the same plan, so the join buys nothing.
(The third way, `NOT IN`, gives the right answer on this data but is unsafe - see the NULL trap below.)

## Pair 3 - "Oldest open fault in each ward" (correlated subquery  vs  join to a grouped table)

| | Correlated subquery | Join to `GROUP BY` derived table |
|---|---|---|
| Result | 8 rows | 8 rows (identical) |
| Readability | "the fault whose date equals the minimum date *of its own ward*" - short, reads in one go | Longer: one extra derived table, two join conditions |
| Intent | Clear - but a beginner must understand correlation | Clear - "first compute oldest date per ward, then find the fault" |
| How it runs | PostgreSQL keeps it as a **SubPlan**: the inner aggregate is re-run for each outer row | The `GROUP BY` runs **once** for all wards, then one hash join |
| Cost as data grows | Grows with (open faults x work per inner run) | Grows roughly with table size |
| Ties | Returns all faults that share the oldest date | Same |

**Verdict: genuinely a judgement call.** On 204 rows both are instant. With millions of rows the
join (or a window function `ROW_NUMBER() OVER (PARTITION BY ward ORDER BY reported_on)`) would be the safer choice
because the aggregate is computed once. For a short report query the correlated subquery is easier to read.

## Where a subquery cannot simply be replaced by a join

Q1 ("wards above the city average") compares a group total with **one number computed from the whole table**.
A join would need a `CROSS JOIN` to a one-row derived table - legal, but harder to read than the scalar subquery in `HAVING`.
Here the subquery is the better tool.

## The NULL trap (why `NOT EXISTS` over `NOT IN`)

`x NOT IN (1, 2, NULL)` means `x<>1 AND x<>2 AND x<>NULL`. The last part is UNKNOWN, so the whole test can
never be TRUE and **every row is rejected, with no error**. `queries.sql` Part E shows `NOT IN` returning 0 rows
and `NOT EXISTS` returning the correct 6 rows on the same list. On our schema `fault_assignment.contractor_id` is
`NOT NULL`, so `NOT IN` happens to work today - but one future schema change (making that column nullable)
would silently break it. `NOT EXISTS` has no such failure mode.

## Rule of thumb used in this project

| Situation | Prefer |
|---|---|
| Only need to know whether a match exists | `EXISTS` / `IN` subquery (no duplicate rows to clean up) |
| Need "no match exists" | `NOT EXISTS` (never `NOT IN` on a nullable column) |
| Need columns from the other table in the output | Join |
| Compare to a single overall value (average, max) | Scalar subquery |
| "Best row per group" on a big table | Join to grouped table, or a window function |
