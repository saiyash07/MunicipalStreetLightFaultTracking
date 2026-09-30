-- =====================================================================
-- queries.sql  |  Municipal Street Light Fault Tracking  |  PostgreSQL
-- Run AFTER schema.sql and seed.sql.
-- Every query is followed by its real output inside a /* OUTPUT ... */ comment,
-- so the whole file can still be run top to bottom in pgAdmin 4.
-- "Report date" used in the data = 30-Sep-2026, and "this year" = 2026.
-- =====================================================================

-- #####################################################################
-- PART A : CORE SQL  (filtering, sorting, aggregates, GROUP BY, HAVING, joins)
-- #####################################################################

-- A1. Filtering + sorting: the 10 oldest open faults
-- WHERE filters rows, ORDER BY sorts, LIMIT keeps the first 10.
SELECT fault_id, pole_id, fault_type, reported_on
FROM   fault_report
WHERE  status = 'OPEN'
ORDER  BY reported_on ASC
LIMIT  10;
/* OUTPUT
 fault_id | pole_id |    fault_type    | reported_on 
----------+---------+------------------+-------------
        1 |      49 | Flickering       | 2025-09-01
       39 |       7 | Flickering       | 2025-10-31
       40 |      31 | Bulb not working | 2025-11-02
       52 |      51 | Bulb not working | 2025-11-24
       56 |       4 | Bulb not working | 2025-11-27
       64 |      28 | Bulb not working | 2025-12-17
       75 |      46 | Bulb not working | 2025-12-29
       90 |       5 | Bulb not working | 2026-01-15
      121 |      50 | Day burning      | 2026-03-27
      141 |      34 | Flickering       | 2026-05-02
(10 rows)
*/

-- A2. Aggregate + GROUP BY + JOIN: number of faults in each ward
-- fault_report has no ward, so we go fault -> pole -> ward with two joins.
SELECT w.ward_name, COUNT(*) AS total_faults
FROM   fault_report f
JOIN   pole p ON p.pole_id = f.pole_id
JOIN   ward w ON w.ward_id = p.ward_id
GROUP  BY w.ward_name
ORDER  BY total_faults DESC;
/* OUTPUT
 ward_name  | total_faults 
------------+--------------
 Ganeshpeth |           36
 Itwari     |           34
 Dharampeth |           32
 Sitabuldi  |           28
 Sadar      |           24
 Mankapur   |           20
 Nandanvan  |           16
 Hingna     |           14
(8 rows)
*/

-- A3. HAVING: wards with 5 or more OPEN faults
-- WHERE filters single rows BEFORE grouping; HAVING filters groups AFTER grouping.
SELECT w.ward_name, COUNT(*) AS open_faults
FROM   fault_report f
JOIN   pole p ON p.pole_id = f.pole_id
JOIN   ward w ON w.ward_id = p.ward_id
WHERE  f.status = 'OPEN'
GROUP  BY w.ward_name
HAVING COUNT(*) >= 5
ORDER  BY open_faults DESC;
/* OUTPUT
 ward_name  | open_faults 
------------+-------------
 Itwari     |          10
 Ganeshpeth |           8
 Sadar      |           5
(3 rows)
*/

-- A4. Multi-table JOIN + LEFT JOIN: open faults with ward and contractor
-- LEFT JOIN keeps faults that have no contractor yet (contractor shows as NULL).
SELECT f.fault_id, w.ward_name, p.pole_code, f.reported_on,
       COALESCE(c.contractor_name, '-- not assigned --') AS contractor
FROM   fault_report f
JOIN   pole p  ON p.pole_id = f.pole_id
JOIN   ward w  ON w.ward_id = p.ward_id
LEFT   JOIN fault_assignment a ON a.fault_id = f.fault_id
LEFT   JOIN contractor c       ON c.contractor_id = a.contractor_id
WHERE  f.status = 'OPEN'
ORDER  BY f.reported_on DESC
LIMIT  10;
/* OUTPUT
 fault_id | ward_name  | pole_code | reported_on |         contractor         
----------+------------+-----------+-------------+----------------------------
      204 | Dharampeth | W3-P05    | 2026-09-28  | -- not assigned --
      203 | Sadar      | W2-P05    | 2026-09-27  | -- not assigned --
      201 | Ganeshpeth | W1-P04    | 2026-09-24  | -- not assigned --
      202 | Dharampeth | W3-P04    | 2026-09-24  | -- not assigned --
      200 | Ganeshpeth | W1-P04    | 2026-09-23  | -- not assigned --
      199 | Hingna     | W5-P06    | 2026-09-22  | Shree Electricals
      198 | Dharampeth | W3-P04    | 2026-09-16  | Lumina Power Works
      197 | Hingna     | W5-P04    | 2026-09-12  | Shree Electricals
      195 | Itwari     | W7-P03    | 2026-09-11  | Sai Lighting Services
      196 | Nandanvan  | W8-P04    | 2026-09-11  | Gupta and Sons Electricals
(10 rows)
*/

-- A5. Aggregate functions: average / fastest / slowest repair time per ward (days)
SELECT w.ward_name,
       COUNT(*)                                   AS closed_faults,
       ROUND(AVG(f.closed_on - f.reported_on), 1) AS avg_days,
       MIN(f.closed_on - f.reported_on)           AS fastest,
       MAX(f.closed_on - f.reported_on)           AS slowest
FROM   fault_report f
JOIN   pole p ON p.pole_id = f.pole_id
JOIN   ward w ON w.ward_id = p.ward_id
WHERE  f.status = 'CLOSED'
GROUP  BY w.ward_name
ORDER  BY avg_days DESC;
/* OUTPUT
 ward_name  | closed_faults | avg_days | fastest | slowest 
------------+---------------+----------+---------+---------
 Nandanvan  |            12 |     11.3 |       4 |      15
 Ganeshpeth |            28 |      9.8 |       1 |      15
 Sadar      |            19 |      9.6 |       3 |      17
 Mankapur   |            16 |      9.3 |       2 |      16
 Itwari     |            24 |      8.9 |       2 |      16
 Dharampeth |            29 |      8.3 |       1 |      15
 Hingna     |            10 |      7.7 |       2 |      17
 Sitabuldi  |            24 |      6.5 |       1 |      14
(8 rows)
*/

-- #####################################################################
-- PART B : THE FIVE QUESTIONS FROM THE PROBLEM STATEMENT
-- #####################################################################

-- Q1. Which wards have more faults than the city average?
-- SCALAR + UNCORRELATED subquery. The inner query returns ONE number (the average
-- faults per ward). It does not use anything from the outer query, so PostgreSQL
-- runs it ONCE and reuses the number.
SELECT w.ward_name, COUNT(*) AS total_faults
FROM   fault_report f
JOIN   pole p ON p.pole_id = f.pole_id
JOIN   ward w ON w.ward_id = p.ward_id
GROUP  BY w.ward_name
HAVING COUNT(*) > (SELECT COUNT(*)::numeric / COUNT(DISTINCT p2.ward_id)
                   FROM   fault_report f2
                   JOIN   pole p2 ON p2.pole_id = f2.pole_id)
ORDER  BY total_faults DESC;
/* OUTPUT
 ward_name  | total_faults 
------------+--------------
 Ganeshpeth |           36
 Itwari     |           34
 Dharampeth |           32
 Sitabuldi  |           28
(4 rows)
*/

-- Q1 (check). The city average itself, to see the threshold
SELECT ROUND(COUNT(*)::numeric / (SELECT COUNT(*) FROM ward), 2) AS avg_faults_per_ward
FROM   fault_report;
/* OUTPUT
 avg_faults_per_ward 
---------------------
               25.50
(1 row)
*/

-- Q2. Are there any faults closed without verification?
-- NOT EXISTS (CORRELATED: the inner query uses f.fault_id from the outer row).
-- Expected result: 0 rows, because the trigger in schema.sql makes it impossible.
SELECT f.fault_id, f.pole_id, f.closed_on
FROM   fault_report f
WHERE  f.status = 'CLOSED'
  AND  NOT EXISTS (SELECT 1
                   FROM   fault_verification v
                   WHERE  v.fault_id = f.fault_id);
/* OUTPUT
 fault_id | pole_id | closed_on 
----------+---------+-----------
(0 rows)
*/

-- Q2 (check). Closed faults vs verified faults must be equal
SELECT (SELECT COUNT(*) FROM fault_report WHERE status = 'CLOSED') AS closed_faults,
       (SELECT COUNT(*) FROM fault_verification)                   AS verifications;
/* OUTPUT
 closed_faults | verifications 
---------------+---------------
           162 |           162
(1 row)
*/

-- Q3. Which contractors have no pending faults?
-- NOT EXISTS (CORRELATED). "Pending" = assigned to a fault whose status is OPEN.
SELECT c.contractor_id, c.contractor_name
FROM   contractor c
WHERE  NOT EXISTS (SELECT 1
                   FROM   fault_assignment a
                   JOIN   fault_report f ON f.fault_id = a.fault_id
                   WHERE  a.contractor_id = c.contractor_id
                     AND  f.status = 'OPEN')
ORDER  BY c.contractor_id;
/* OUTPUT
 contractor_id |  contractor_name   
---------------+--------------------
             7 | Metro Illumination
             8 | NovaGrid Services
(2 rows)
*/

-- Q3 (same question with NOT IN). Works here ONLY because
-- fault_assignment.contractor_id is NOT NULL. See the NULL trap in Part E.
SELECT c.contractor_id, c.contractor_name
FROM   contractor c
WHERE  c.contractor_id NOT IN (SELECT a.contractor_id
                               FROM   fault_assignment a
                               JOIN   fault_report f ON f.fault_id = a.fault_id
                               WHERE  f.status = 'OPEN')
ORDER  BY c.contractor_id;
/* OUTPUT
 contractor_id |  contractor_name   
---------------+--------------------
             7 | Metro Illumination
             8 | NovaGrid Services
(2 rows)
*/

-- Q4. Which poles had more than two faults this year (2026)?
-- Plain GROUP BY + HAVING. This one needs no subquery at all.
SELECT p.pole_code, w.ward_name, COUNT(*) AS faults_2026
FROM   fault_report f
JOIN   pole p ON p.pole_id = f.pole_id
JOIN   ward w ON w.ward_id = p.ward_id
WHERE  f.reported_on >= DATE '2026-01-01'
  AND  f.reported_on <  DATE '2027-01-01'
GROUP  BY p.pole_code, w.ward_name
HAVING COUNT(*) > 2
ORDER  BY faults_2026 DESC, p.pole_code;
/* OUTPUT
 pole_code | ward_name  | faults_2026 
-----------+------------+-------------
 W1-P04    | Ganeshpeth |           8
 W3-P05    | Dharampeth |           8
 W4-P06    | Sitabuldi  |           8
 W2-P05    | Sadar      |           7
 W3-P04    | Dharampeth |           6
 W4-P07    | Sitabuldi  |           6
 W1-P03    | Ganeshpeth |           5
 W7-P02    | Itwari     |           5
 W1-P05    | Ganeshpeth |           4
 W2-P04    | Sadar      |           3
 W3-P01    | Dharampeth |           3
 W3-P07    | Dharampeth |           3
 W5-P04    | Hingna     |           3
 W6-P02    | Mankapur   |           3
 W6-P07    | Mankapur   |           3
 W7-P05    | Itwari     |           3
 W7-P06    | Itwari     |           3
(17 rows)
*/

-- Q4 (alternative with a multi-row IN subquery). Gives pole details for the same poles.
SELECT p.pole_code, p.location, p.installed_on
FROM   pole p
WHERE  p.pole_id IN (SELECT f.pole_id
                     FROM   fault_report f
                     WHERE  f.reported_on >= DATE '2026-01-01'
                       AND  f.reported_on <  DATE '2027-01-01'
                     GROUP  BY f.pole_id
                     HAVING COUNT(*) > 2)
ORDER  BY p.pole_code;
/* OUTPUT
 pole_code |           location            | installed_on 
-----------+-------------------------------+--------------
 W1-P03    | Station Road, near plot 277   | 2019-06-02
 W1-P04    | Lake View Road, near plot 57  | 2012-04-20
 W1-P05    | Market Lane, near plot 197    | 2021-02-21
 W2-P04    | Garden Avenue, near plot 42   | 2017-09-08
 W2-P05    | Hospital Road, near plot 73   | 2019-08-27
 W3-P01    | Ring Road, near plot 27       | 2020-06-07
 W3-P04    | Main Road, near plot 208      | 2014-09-05
 W3-P05    | Temple Street, near plot 286  | 2014-05-25
 W3-P07    | Main Road, near plot 137      | 2012-09-20
 W4-P06    | Lake View Road, near plot 172 | 2012-02-09
 W4-P07    | Main Road, near plot 179      | 2012-03-19
 W5-P04    | Ring Road, near plot 269      | 2019-09-10
 W6-P02    | Temple Street, near plot 109  | 2012-07-24
 W6-P07    | Garden Avenue, near plot 246  | 2012-11-03
 W7-P02    | Market Lane, near plot 116    | 2017-12-20
 W7-P05    | Hospital Road, near plot 202  | 2021-03-30
 W7-P06    | Hospital Road, near plot 114  | 2018-03-19
(17 rows)
*/

-- Q5. What is the oldest open fault in each ward?
-- CORRELATED subquery: for every candidate fault f, the inner query is evaluated for
-- f's ward and returns the earliest open date in that ward. Keep f if it matches.
-- (If two faults in a ward share the oldest date, both are returned - a tie.)
SELECT w.ward_name, f.fault_id, p.pole_code, f.reported_on
FROM   fault_report f
JOIN   pole p ON p.pole_id = f.pole_id
JOIN   ward w ON w.ward_id = p.ward_id
WHERE  f.status = 'OPEN'
  AND  f.reported_on = (SELECT MIN(f2.reported_on)
                        FROM   fault_report f2
                        JOIN   pole p2 ON p2.pole_id = f2.pole_id
                        WHERE  f2.status = 'OPEN'
                          AND  p2.ward_id = p.ward_id)       -- <- correlation
ORDER  BY w.ward_name;
/* OUTPUT
 ward_name  | fault_id | pole_code | reported_on 
------------+----------+-----------+-------------
 Dharampeth |      198 | W3-P04    | 2026-09-16
 Ganeshpeth |       39 | W1-P07    | 2025-10-31
 Hingna     |      141 | W5-P02    | 2026-05-02
 Itwari     |        1 | W7-P04    | 2025-09-01
 Mankapur   |      150 | W6-P06    | 2026-05-27
 Nandanvan  |      165 | W8-P05    | 2026-07-06
 Sadar      |      170 | W2-P05    | 2026-07-10
 Sitabuldi  |       40 | W4-P07    | 2025-11-02
(8 rows)
*/

-- #####################################################################
-- PART C : ONE EXAMPLE OF EVERY SUBQUERY KIND REQUIRED
--          (scalar, multi-row, correlated, IN, NOT IN, EXISTS, NOT EXISTS, ANY, ALL)
-- #####################################################################

-- C1. SCALAR subquery (returns exactly one value), uncorrelated
-- Closed faults that took longer to repair than the overall average.
SELECT fault_id, reported_on, closed_on, (closed_on - reported_on) AS days_taken
FROM   fault_report
WHERE  status = 'CLOSED'
  AND  (closed_on - reported_on) > (SELECT AVG(closed_on - reported_on)
                                    FROM   fault_report
                                    WHERE  status = 'CLOSED')
ORDER  BY days_taken DESC, fault_id
LIMIT  10;
/* OUTPUT
 fault_id | reported_on | closed_on  | days_taken 
----------+-------------+------------+------------
       51 | 2025-11-23  | 2025-12-10 |         17
       74 | 2025-12-29  | 2026-01-15 |         17
       68 | 2025-12-19  | 2026-01-04 |         16
       86 | 2026-01-10  | 2026-01-26 |         16
      127 | 2026-04-05  | 2026-04-21 |         16
      158 | 2026-06-10  | 2026-06-26 |         16
       13 | 2025-09-18  | 2025-10-03 |         15
       28 | 2025-10-10  | 2025-10-25 |         15
       29 | 2025-10-16  | 2025-10-31 |         15
       34 | 2025-10-24  | 2025-11-08 |         15
(10 rows)
*/

-- C2. MULTI-ROW subquery with IN (returns a list), uncorrelated
-- Contractors who currently hold at least one open fault.
SELECT contractor_id, contractor_name
FROM   contractor
WHERE  contractor_id IN (SELECT a.contractor_id
                         FROM   fault_assignment a
                         JOIN   fault_report f ON f.fault_id = a.fault_id
                         WHERE  f.status = 'OPEN')
ORDER  BY contractor_id;
/* OUTPUT
 contractor_id |      contractor_name       
---------------+----------------------------
             1 | Bright Spark Electricals
             2 | Lumina Power Works
             3 | Shree Electricals
             4 | VoltEdge Contractors
             5 | Sai Lighting Services
             6 | Gupta and Sons Electricals
(6 rows)
*/

-- C3. NOT IN (safe here because the subquery column is NOT NULL)
-- Poles that have never had a fault reported.
SELECT pole_code, location
FROM   pole
WHERE  pole_id NOT IN (SELECT pole_id FROM fault_report)
ORDER  BY pole_code;
/* OUTPUT
 pole_code |           location           
-----------+------------------------------
 W1-P01    | Canal Road, near plot 213
 W1-P06    | Garden Avenue, near plot 130
 W1-P08    | Canal Road, near plot 32
 W2-P03    | Temple Street, near plot 36
 W2-P06    | Garden Avenue, near plot 260
 W4-P02    | Canal Road, near plot 67
 W4-P08    | Hospital Road, near plot 140
 W6-P04    | School Road, near plot 162
(8 rows)
*/

-- C4. EXISTS (correlated)
-- Wards that have at least one open fault that nobody has been assigned to yet.
SELECT w.ward_name
FROM   ward w
WHERE  EXISTS (SELECT 1
               FROM   fault_report f
               JOIN   pole p ON p.pole_id = f.pole_id
               WHERE  p.ward_id = w.ward_id
                 AND  f.status = 'OPEN'
                 AND  NOT EXISTS (SELECT 1 FROM fault_assignment a
                                  WHERE a.fault_id = f.fault_id))
ORDER  BY w.ward_name;
/* OUTPUT
 ward_name  
------------
 Dharampeth
 Ganeshpeth
 Sadar
(3 rows)
*/

-- C5. NOT EXISTS: see Q2 and Q3 above.


-- C6. ANY  ( < ANY  means "less than at least one value in the list")
-- Open faults in Ward 1 that are older than ANY open fault of Ward 3,
-- i.e. older than at least one of them (same as older than Ward 3's newest open fault).
SELECT f.fault_id, p.pole_code, f.reported_on
FROM   fault_report f
JOIN   pole p ON p.pole_id = f.pole_id
WHERE  f.status = 'OPEN'
  AND  p.ward_id = 1
  AND  f.reported_on < ANY (SELECT f3.reported_on
                            FROM   fault_report f3
                            JOIN   pole p3 ON p3.pole_id = f3.pole_id
                            WHERE  f3.status = 'OPEN' AND p3.ward_id = 3)
ORDER  BY f.reported_on;
/* OUTPUT
 fault_id | pole_code | reported_on 
----------+-----------+-------------
       39 | W1-P07    | 2025-10-31
       56 | W1-P04    | 2025-11-27
       90 | W1-P05    | 2026-01-15
      174 | W1-P09    | 2026-07-13
      188 | W1-P04    | 2026-08-27
      194 | W1-P05    | 2026-09-10
      200 | W1-P04    | 2026-09-23
      201 | W1-P04    | 2026-09-24
(8 rows)
*/

-- C7. ALL  ( >= ALL means "at least as big as EVERY value in the list")
-- The ward with the highest total number of faults.
SELECT w.ward_name, COUNT(*) AS total_faults
FROM   fault_report f
JOIN   pole p ON p.pole_id = f.pole_id
JOIN   ward w ON w.ward_id = p.ward_id
GROUP  BY w.ward_name
HAVING COUNT(*) >= ALL (SELECT COUNT(*)
                        FROM   fault_report f2
                        JOIN   pole p2 ON p2.pole_id = f2.pole_id
                        GROUP  BY p2.ward_id);
/* OUTPUT
 ward_name  | total_faults 
------------+--------------
 Ganeshpeth |           36
(1 row)
*/

-- C8. ALL again: the single oldest open fault in the whole city
SELECT fault_id, pole_id, reported_on
FROM   fault_report
WHERE  status = 'OPEN'
  AND  reported_on <= ALL (SELECT reported_on FROM fault_report WHERE status = 'OPEN');
/* OUTPUT
 fault_id | pole_id | reported_on 
----------+---------+-------------
        1 |      49 | 2025-09-01
(1 row)
*/

-- C9. Uncorrelated vs correlated: how PostgreSQL really runs them
-- Uncorrelated: inner query has no link to the outer one -> runs ONCE (Q1, C1, C2, C3).
-- Correlated:   inner query uses a column of the current outer row -> logically
--               re-evaluated FOR EACH outer row (Q2, Q3, Q5, C4).
-- PostgreSQL's planner often turns a correlated EXISTS into a join internally.
-- Proof: look at the plan of Q3 - the NOT EXISTS shows up as an "Anti Join".
EXPLAIN
SELECT c.contractor_id
FROM   contractor c
WHERE  NOT EXISTS (SELECT 1
                   FROM   fault_assignment a
                   JOIN   fault_report f ON f.fault_id = a.fault_id
                   WHERE  a.contractor_id = c.contractor_id AND f.status = 'OPEN');
/* OUTPUT
                                   QUERY PLAN                                    
---------------------------------------------------------------------------------
 Hash Right Anti Join  (cost=8.26..13.29 rows=1 width=4)
   Hash Cond: (a.contractor_id = c.contractor_id)
   ->  Hash Join  (cost=7.08..11.60 rows=41 width=4)
         Hash Cond: (a.fault_id = f.fault_id)
         ->  Seq Scan on fault_assignment a  (cost=0.00..3.99 rows=199 width=8)
         ->  Hash  (cost=6.55..6.55 rows=42 width=4)
               ->  Seq Scan on fault_report f  (cost=0.00..6.55 rows=42 width=4)
                     Filter: ((status)::text = 'OPEN'::text)
   ->  Hash  (cost=1.08..1.08 rows=8 width=4)
         ->  Seq Scan on contractor c  (cost=0.00..1.08 rows=8 width=4)
(10 rows)
*/

-- #####################################################################
-- PART D : SUBQUERY REWRITTEN AS A JOIN  (3 pairs; see subquery_vs_join.md)
-- Each pair is followed by a proof query: (A EXCEPT B) UNION ALL (B EXCEPT A).
-- 0 rows = both versions return exactly the same rows.
-- #####################################################################

-- D1-a. Contractors holding open faults - SUBQUERY version (same as C2)
SELECT contractor_id, contractor_name
FROM   contractor
WHERE  contractor_id IN (SELECT a.contractor_id
                         FROM   fault_assignment a
                         JOIN   fault_report f ON f.fault_id = a.fault_id
                         WHERE  f.status = 'OPEN')
ORDER  BY contractor_id;
/* OUTPUT
 contractor_id |      contractor_name       
---------------+----------------------------
             1 | Bright Spark Electricals
             2 | Lumina Power Works
             3 | Shree Electricals
             4 | VoltEdge Contractors
             5 | Sai Lighting Services
             6 | Gupta and Sons Electricals
(6 rows)
*/

-- D1-b. Same question - JOIN version
-- Needs DISTINCT: a contractor with 10 open faults would otherwise appear 10 times.
SELECT DISTINCT c.contractor_id, c.contractor_name
FROM   contractor c
JOIN   fault_assignment a ON a.contractor_id = c.contractor_id
JOIN   fault_report f     ON f.fault_id = a.fault_id
WHERE  f.status = 'OPEN'
ORDER  BY c.contractor_id;
/* OUTPUT
 contractor_id |      contractor_name       
---------------+----------------------------
             1 | Bright Spark Electricals
             2 | Lumina Power Works
             3 | Shree Electricals
             4 | VoltEdge Contractors
             5 | Sai Lighting Services
             6 | Gupta and Sons Electricals
(6 rows)
*/

-- D1-b (without DISTINCT, to show the duplicate-row trap)
SELECT c.contractor_id, c.contractor_name
FROM   contractor c
JOIN   fault_assignment a ON a.contractor_id = c.contractor_id
JOIN   fault_report f     ON f.fault_id = a.fault_id
WHERE  f.status = 'OPEN'
ORDER  BY c.contractor_id
LIMIT  12;
/* OUTPUT
 contractor_id |     contractor_name      
---------------+--------------------------
             1 | Bright Spark Electricals
             1 | Bright Spark Electricals
             1 | Bright Spark Electricals
             1 | Bright Spark Electricals
             1 | Bright Spark Electricals
             1 | Bright Spark Electricals
             1 | Bright Spark Electricals
             1 | Bright Spark Electricals
             1 | Bright Spark Electricals
             1 | Bright Spark Electricals
             2 | Lumina Power Works
             3 | Shree Electricals
(12 rows)
*/

-- D1 proof: differences between D1-a and D1-b (expect 0 rows)
(SELECT contractor_id FROM contractor
  WHERE contractor_id IN (SELECT a.contractor_id FROM fault_assignment a
                          JOIN fault_report f ON f.fault_id = a.fault_id WHERE f.status = 'OPEN')
 EXCEPT
 SELECT DISTINCT c.contractor_id FROM contractor c
  JOIN fault_assignment a ON a.contractor_id = c.contractor_id
  JOIN fault_report f ON f.fault_id = a.fault_id WHERE f.status = 'OPEN')
UNION ALL
(SELECT DISTINCT c.contractor_id FROM contractor c
  JOIN fault_assignment a ON a.contractor_id = c.contractor_id
  JOIN fault_report f ON f.fault_id = a.fault_id WHERE f.status = 'OPEN'
 EXCEPT
 SELECT contractor_id FROM contractor
  WHERE contractor_id IN (SELECT a.contractor_id FROM fault_assignment a
                          JOIN fault_report f ON f.fault_id = a.fault_id WHERE f.status = 'OPEN'));
/* OUTPUT
 contractor_id 
---------------
(0 rows)
*/

-- D2-a. Contractors with NO pending faults - SUBQUERY version (NOT EXISTS, same as Q3)
SELECT c.contractor_id, c.contractor_name
FROM   contractor c
WHERE  NOT EXISTS (SELECT 1
                   FROM   fault_assignment a
                   JOIN   fault_report f ON f.fault_id = a.fault_id
                   WHERE  a.contractor_id = c.contractor_id
                     AND  f.status = 'OPEN')
ORDER  BY c.contractor_id;
/* OUTPUT
 contractor_id |  contractor_name   
---------------+--------------------
             7 | Metro Illumination
             8 | NovaGrid Services
(2 rows)
*/

-- D2-b. Same question - JOIN version (LEFT JOIN ... IS NULL, the "anti-join")
-- The status = 'OPEN' test MUST sit in the ON clause, not in WHERE.
-- Put in WHERE it would throw away the NULL rows and the query would return nothing.
SELECT c.contractor_id, c.contractor_name
FROM   contractor c
LEFT   JOIN (SELECT a.contractor_id
             FROM   fault_assignment a
             JOIN   fault_report f ON f.fault_id = a.fault_id
             WHERE  f.status = 'OPEN') open_work
       ON open_work.contractor_id = c.contractor_id
WHERE  open_work.contractor_id IS NULL
ORDER  BY c.contractor_id;
/* OUTPUT
 contractor_id |  contractor_name   
---------------+--------------------
             7 | Metro Illumination
             8 | NovaGrid Services
(2 rows)
*/

-- D2 proof (expect 0 rows)
(SELECT c.contractor_id FROM contractor c
  WHERE NOT EXISTS (SELECT 1 FROM fault_assignment a JOIN fault_report f ON f.fault_id = a.fault_id
                    WHERE a.contractor_id = c.contractor_id AND f.status = 'OPEN')
 EXCEPT
 SELECT c.contractor_id FROM contractor c
  LEFT JOIN (SELECT a.contractor_id FROM fault_assignment a JOIN fault_report f ON f.fault_id = a.fault_id
             WHERE f.status = 'OPEN') o ON o.contractor_id = c.contractor_id
  WHERE o.contractor_id IS NULL)
UNION ALL
(SELECT c.contractor_id FROM contractor c
  LEFT JOIN (SELECT a.contractor_id FROM fault_assignment a JOIN fault_report f ON f.fault_id = a.fault_id
             WHERE f.status = 'OPEN') o ON o.contractor_id = c.contractor_id
  WHERE o.contractor_id IS NULL
 EXCEPT
 SELECT c.contractor_id FROM contractor c
  WHERE NOT EXISTS (SELECT 1 FROM fault_assignment a JOIN fault_report f ON f.fault_id = a.fault_id
                    WHERE a.contractor_id = c.contractor_id AND f.status = 'OPEN'));
/* OUTPUT
 contractor_id 
---------------
(0 rows)
*/

-- D3-a. Oldest open fault per ward - CORRELATED SUBQUERY version (same as Q5)
SELECT w.ward_name, f.fault_id, p.pole_code, f.reported_on
FROM   fault_report f
JOIN   pole p ON p.pole_id = f.pole_id
JOIN   ward w ON w.ward_id = p.ward_id
WHERE  f.status = 'OPEN'
  AND  f.reported_on = (SELECT MIN(f2.reported_on)
                        FROM   fault_report f2
                        JOIN   pole p2 ON p2.pole_id = f2.pole_id
                        WHERE  f2.status = 'OPEN' AND p2.ward_id = p.ward_id)
ORDER  BY w.ward_name;
/* OUTPUT
 ward_name  | fault_id | pole_code | reported_on 
------------+----------+-----------+-------------
 Dharampeth |      198 | W3-P04    | 2026-09-16
 Ganeshpeth |       39 | W1-P07    | 2025-10-31
 Hingna     |      141 | W5-P02    | 2026-05-02
 Itwari     |        1 | W7-P04    | 2025-09-01
 Mankapur   |      150 | W6-P06    | 2026-05-27
 Nandanvan  |      165 | W8-P05    | 2026-07-06
 Sadar      |      170 | W2-P05    | 2026-07-10
 Sitabuldi  |       40 | W4-P07    | 2025-11-02
(8 rows)
*/

-- D3-b. Same question - JOIN version (join to a grouped derived table)
-- The GROUP BY runs once for all wards, then we join back to find the matching fault.
SELECT w.ward_name, f.fault_id, p.pole_code, f.reported_on
FROM   fault_report f
JOIN   pole p ON p.pole_id = f.pole_id
JOIN   ward w ON w.ward_id = p.ward_id
JOIN  (SELECT p2.ward_id, MIN(f2.reported_on) AS oldest_date
       FROM   fault_report f2
       JOIN   pole p2 ON p2.pole_id = f2.pole_id
       WHERE  f2.status = 'OPEN'
       GROUP  BY p2.ward_id) oldest
      ON  oldest.ward_id = p.ward_id
      AND oldest.oldest_date = f.reported_on
WHERE  f.status = 'OPEN'
ORDER  BY w.ward_name;
/* OUTPUT
 ward_name  | fault_id | pole_code | reported_on 
------------+----------+-----------+-------------
 Dharampeth |      198 | W3-P04    | 2026-09-16
 Ganeshpeth |       39 | W1-P07    | 2025-10-31
 Hingna     |      141 | W5-P02    | 2026-05-02
 Itwari     |        1 | W7-P04    | 2025-09-01
 Mankapur   |      150 | W6-P06    | 2026-05-27
 Nandanvan  |      165 | W8-P05    | 2026-07-06
 Sadar      |      170 | W2-P05    | 2026-07-10
 Sitabuldi  |       40 | W4-P07    | 2025-11-02
(8 rows)
*/

-- D3 proof (expect 0 rows)
(SELECT f.fault_id FROM fault_report f JOIN pole p ON p.pole_id = f.pole_id
  WHERE f.status = 'OPEN'
    AND f.reported_on = (SELECT MIN(f2.reported_on) FROM fault_report f2
                         JOIN pole p2 ON p2.pole_id = f2.pole_id
                         WHERE f2.status = 'OPEN' AND p2.ward_id = p.ward_id)
 EXCEPT
 SELECT f.fault_id FROM fault_report f JOIN pole p ON p.pole_id = f.pole_id
  JOIN (SELECT p2.ward_id, MIN(f2.reported_on) AS oldest_date
        FROM fault_report f2 JOIN pole p2 ON p2.pole_id = f2.pole_id
        WHERE f2.status = 'OPEN' GROUP BY p2.ward_id) o
    ON o.ward_id = p.ward_id AND o.oldest_date = f.reported_on
  WHERE f.status = 'OPEN')
UNION ALL
(SELECT f.fault_id FROM fault_report f JOIN pole p ON p.pole_id = f.pole_id
  JOIN (SELECT p2.ward_id, MIN(f2.reported_on) AS oldest_date
        FROM fault_report f2 JOIN pole p2 ON p2.pole_id = f2.pole_id
        WHERE f2.status = 'OPEN' GROUP BY p2.ward_id) o
    ON o.ward_id = p.ward_id AND o.oldest_date = f.reported_on
  WHERE f.status = 'OPEN'
 EXCEPT
 SELECT f.fault_id FROM fault_report f JOIN pole p ON p.pole_id = f.pole_id
  WHERE f.status = 'OPEN'
    AND f.reported_on = (SELECT MIN(f2.reported_on) FROM fault_report f2
                         JOIN pole p2 ON p2.pole_id = f2.pole_id
                         WHERE f2.status = 'OPEN' AND p2.ward_id = p.ward_id));
/* OUTPUT
 fault_id 
----------
(0 rows)
*/

-- D-note. A case where a subquery CANNOT simply be turned into a join:
-- Q1 (faults above the city average) compares a group total to ONE number
-- computed from the whole table. A join would need a CROSS JOIN to a one-row
-- derived table - legal, but harder to read than the scalar subquery in HAVING.

-- #####################################################################
-- PART E : THE NULL TRAP IN NOT IN
-- fault_assignment.contractor_id is NOT NULL, so Q3 is safe today. To SEE the trap
-- we feed both forms a list that contains a NULL (as a nullable column could).
-- #####################################################################

-- E1. NOT IN with a NULL in the list -> returns NOTHING (wrong answer, no error!)
-- x NOT IN (1, 2, NULL)  means  x<>1 AND x<>2 AND x<>NULL.  x<>NULL is UNKNOWN,
-- and TRUE AND UNKNOWN is never TRUE, so every row is rejected.
SELECT contractor_id, contractor_name
FROM   contractor
WHERE  contractor_id NOT IN (SELECT id FROM (VALUES (1), (2), (NULL::int)) AS t(id));
/* OUTPUT
 contractor_id | contractor_name 
---------------+-----------------
(0 rows)
*/

-- E2. NOT EXISTS with the same list -> correct answer (contractors 3 to 8)
-- NOT EXISTS only asks "is there a matching row?", and NULL never matches.
SELECT contractor_id, contractor_name
FROM   contractor c
WHERE  NOT EXISTS (SELECT 1
                   FROM   (VALUES (1), (2), (NULL::int)) AS t(id)
                   WHERE  t.id = c.contractor_id)
ORDER  BY contractor_id;
/* OUTPUT
 contractor_id |      contractor_name       
---------------+----------------------------
             3 | Shree Electricals
             4 | VoltEdge Contractors
             5 | Sai Lighting Services
             6 | Gupta and Sons Electricals
             7 | Metro Illumination
             8 | NovaGrid Services
(6 rows)
*/

-- #####################################################################
-- PART F : PROVING THE RULES INSIDE THE DATABASE
-- (each demo catches the error so the script keeps running in pgAdmin)
-- #####################################################################

-- F1. Try to CLOSE fault 200 (open, never verified) -> must be BLOCKED
DO $$
BEGIN
    UPDATE fault_report SET status = 'CLOSED', closed_on = DATE '2026-09-30'
    WHERE fault_id = 200;
    RAISE NOTICE 'NOT BLOCKED - this should never print';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'BLOCKED: %', SQLERRM;
END $$;
/* OUTPUT
DO
NOTICE:  BLOCKED: Fault 200 cannot be closed: it has not been verified
*/

-- F2. Try to assign fault 200 (Ward 1) to contractor 5 (serves only Ward 7) -> BLOCKED
DO $$
BEGIN
    INSERT INTO fault_assignment (fault_id, contractor_id, assigned_on)
    VALUES (200, 5, DATE '2026-09-30');
    RAISE NOTICE 'NOT BLOCKED - this should never print';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'BLOCKED: %', SQLERRM;
END $$;
/* OUTPUT
DO
NOTICE:  BLOCKED: Contractor 5 does not serve the ward of fault 200
*/

-- F3. Try to delete the verification of an already closed fault (fault 2) -> BLOCKED
DO $$
BEGIN
    DELETE FROM fault_verification WHERE fault_id = 2;
    RAISE NOTICE 'NOT BLOCKED - this should never print';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'BLOCKED: %', SQLERRM;
END $$;
/* OUTPUT
DO
NOTICE:  BLOCKED: Cannot delete verification of closed fault 2
*/

-- F4. Try to give closed fault 2 a closing date BEFORE its report date -> blocked by CHECK
DO $$
BEGIN
    UPDATE fault_report SET closed_on = DATE '2020-01-01' WHERE fault_id = 2;
    RAISE NOTICE 'NOT BLOCKED - this should never print';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'BLOCKED: %', SQLERRM;
END $$;
/* OUTPUT
DO
NOTICE:  BLOCKED: new row for relation "fault_report" violates check constraint "chk_status_closed_on"
*/

-- F5. The CORRECT workflow for fault 200: assign -> verify -> close
-- Wrapped in BEGIN ... ROLLBACK so the demo leaves the data unchanged.
BEGIN;
INSERT INTO fault_assignment (fault_id, contractor_id, assigned_on) VALUES (200, 1, DATE '2026-09-30');
INSERT INTO fault_verification (fault_id, verified_by, verified_on, remarks)
VALUES (200, 'R. K. Deshmukh', DATE '2026-09-30', 'Demo: verified on site');
UPDATE fault_report SET status = 'CLOSED', closed_on = DATE '2026-09-30' WHERE fault_id = 200;
SELECT fault_id, status, closed_on FROM fault_report WHERE fault_id = 200;
ROLLBACK;
/* OUTPUT
BEGIN
INSERT 0 1
INSERT 0 1
UPDATE 1
 fault_id | status | closed_on  
----------+--------+------------
      200 | CLOSED | 2026-09-30
(1 row)

ROLLBACK
*/

-- F6. Data volume check (proves the seed is realistic, not 3 rows per table)
SELECT 'ward' AS table_name, COUNT(*) AS row_count FROM ward
UNION ALL SELECT 'contractor',        COUNT(*) FROM contractor
UNION ALL SELECT 'contractor_ward',   COUNT(*) FROM contractor_ward
UNION ALL SELECT 'pole',              COUNT(*) FROM pole
UNION ALL SELECT 'fault_report',      COUNT(*) FROM fault_report
UNION ALL SELECT 'fault_assignment',  COUNT(*) FROM fault_assignment
UNION ALL SELECT 'fault_verification',COUNT(*) FROM fault_verification;
/* OUTPUT
     table_name     | row_count 
--------------------+-----------
 ward               |         8
 contractor         |         8
 contractor_ward    |        12
 pole               |        60
 fault_report       |       204
 fault_assignment   |       199
 fault_verification |       162
(7 rows)
*/
