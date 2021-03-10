-- create a table to use as a basis for views and materialized views in various combinations
CREATE TABLE mv_base_a (i int, j int);
INSERT INTO mv_base_a VALUES
  (1,10),
  (2,20),
  (3,30),
  (4,40),
  (5,50);
CREATE TABLE mv_base_b (i int, k int);
INSERT INTO mv_base_b VALUES
  (1,101),
  (2,102),
  (3,103),
  (4,104);

CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_1 AS SELECT i,j,k FROM mv_base_a a INNER JOIN mv_base_b b USING(i) WITH NO DATA;
SELECT * FROM mv_ivm_1 ORDER BY 1,2,3;
REFRESH MATERIALIZED VIEW mv_ivm_1;
SELECT * FROM mv_ivm_1 ORDER BY 1,2,3;
-- immediate maintenance
BEGIN;
INSERT INTO mv_base_b VALUES(5,105);
SELECT * FROM mv_ivm_1 ORDER BY 1,2,3;
UPDATE mv_base_a SET j = 0 WHERE i = 1;
SELECT * FROM mv_ivm_1 ORDER BY 1,2,3;
DELETE FROM mv_base_b WHERE (i,k) = (5,105);
SELECT * FROM mv_ivm_1 ORDER BY 1,2,3;
ROLLBACK;
SELECT * FROM mv_ivm_1 ORDER BY 1,2,3;

-- rename of IVM columns
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_rename AS SELECT DISTINCT * FROM mv_base_a;
ALTER MATERIALIZED VIEW mv_ivm_rename RENAME COLUMN __ivm_count__ TO xxx;
DROP MATERIALIZED VIEW mv_ivm_rename;

-- unique index on IVM columns
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_unique AS SELECT DISTINCT * FROM mv_base_a;
CREATE UNIQUE INDEX ON mv_ivm_unique(__ivm_count__);
CREATE UNIQUE INDEX ON mv_ivm_unique((__ivm_count__));
CREATE UNIQUE INDEX ON mv_ivm_unique((__ivm_count__ + 1));
DROP MATERIALIZED VIEW mv_ivm_unique;

-- some query syntax
BEGIN;
CREATE FUNCTION ivm_func() RETURNS int LANGUAGE 'sql'
       AS 'SELECT 1' IMMUTABLE;
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_func AS SELECT * FROM ivm_func();
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_no_tbl AS SELECT 1;
ROLLBACK;

-- result of materialized view have DISTINCT clause or the duplicate result.
BEGIN;
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_duplicate AS SELECT j FROM mv_base_a;
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_distinct AS SELECT DISTINCT j FROM mv_base_a;
INSERT INTO mv_base_a VALUES(6,20);
SELECT * FROM mv_ivm_duplicate ORDER BY 1;
SELECT * FROM mv_ivm_distinct ORDER BY 1;
DELETE FROM mv_base_a WHERE (i,j) = (2,20);
SELECT * FROM mv_ivm_duplicate ORDER BY 1;
SELECT * FROM mv_ivm_distinct ORDER BY 1;
ROLLBACK;

-- support SUM(), COUNT() and AVG() aggregate functions
BEGIN;
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_agg AS SELECT i, SUM(j), COUNT(i), AVG(j) FROM mv_base_a GROUP BY i;
SELECT * FROM mv_ivm_agg ORDER BY 1,2,3,4;
INSERT INTO mv_base_a VALUES(2,100);
SELECT * FROM mv_ivm_agg ORDER BY 1,2,3,4;
UPDATE mv_base_a SET j = 200 WHERE (i,j) = (2,100);
SELECT * FROM mv_ivm_agg ORDER BY 1,2,3,4;
DELETE FROM mv_base_a WHERE (i,j) = (2,200);
SELECT * FROM mv_ivm_agg ORDER BY 1,2,3,4;
ROLLBACK;

-- support COUNT(*) aggregate function
BEGIN;
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_agg AS SELECT i, SUM(j), COUNT(*) FROM mv_base_a GROUP BY i;
SELECT * FROM mv_ivm_agg ORDER BY 1,2,3;
INSERT INTO mv_base_a VALUES(2,100);
SELECT * FROM mv_ivm_agg ORDER BY 1,2,3;
ROLLBACK;

-- support aggregate functions without GROUP clause
BEGIN;
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_group AS SELECT SUM(j), COUNT(j), AVG(j) FROM mv_base_a;
SELECT * FROM mv_ivm_group ORDER BY 1;
INSERT INTO mv_base_a VALUES(6,60);
SELECT * FROM mv_ivm_group ORDER BY 1;
DELETE FROM mv_base_a;
SELECT * FROM mv_ivm_group ORDER BY 1;
ROLLBACK;

-- resolved issue: When use AVG() function and values is indivisible, result of AVG() is incorrect.
BEGIN;
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_avg_bug AS SELECT i, SUM(j), COUNT(j), AVG(j) FROM mv_base_A GROUP BY i;
SELECT * FROM mv_ivm_avg_bug ORDER BY 1,2,3;
INSERT INTO mv_base_a VALUES
  (1,0),
  (1,0),
  (2,30),
  (2,30);
SELECT * FROM mv_ivm_avg_bug ORDER BY 1,2,3;
DELETE FROM mv_base_a WHERE (i,j) = (1,0);
DELETE FROM mv_base_a WHERE (i,j) = (2,30);
SELECT * FROM mv_ivm_avg_bug ORDER BY 1,2,3;
ROLLBACK;

-- support MIN(), MAX() aggregate functions
BEGIN;
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_min_max AS SELECT i, MIN(j), MAX(j)  FROM mv_base_a GROUP BY i;
SELECT * FROM mv_ivm_min_max ORDER BY 1,2,3;
INSERT INTO mv_base_a VALUES
  (1,11), (1,12),
  (2,21), (2,22),
  (3,31), (3,32),
  (4,41), (4,42),
  (5,51), (5,52);
SELECT * FROM mv_ivm_min_max ORDER BY 1,2,3;
DELETE FROM mv_base_a WHERE (i,j) IN ((1,10), (2,21), (3,32));
SELECT * FROM mv_ivm_min_max ORDER BY 1,2,3;
ROLLBACK;

-- support MIN(), MAX() aggregate functions without GROUP clause
BEGIN;
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_min_max AS SELECT MIN(j), MAX(j)  FROM mv_base_a;
SELECT * FROM mv_ivm_min_max;
INSERT INTO mv_base_a VALUES
  (0,0), (6,60), (7,70);
SELECT * FROM mv_ivm_min_max;
DELETE FROM mv_base_a WHERE (i,j) IN ((0,0), (7,70));
SELECT * FROM mv_ivm_min_max;
DELETE FROM mv_base_a;
SELECT * FROM mv_ivm_min_max;
ROLLBACK;

-- support self join view and multiple change on the same table
BEGIN;
CREATE TABLE base_t (i int, v int);
INSERT INTO base_t VALUES (1, 10), (2, 20), (3, 30);
CREATE INCREMENTAL MATERIALIZED VIEW mv_self(v1, v2) AS
 SELECT t1.v, t2.v FROM base_t AS t1 JOIN base_t AS t2 ON t1.i = t2.i;
SELECT * FROM mv_self ORDER BY v1;
INSERT INTO base_t VALUES (4,40);
DELETE FROM base_t WHERE i = 1;
UPDATE base_t SET v = v*10 WHERE i=2;
SELECT * FROM mv_self ORDER BY v1;
WITH
 ins_t1 AS (INSERT INTO base_t VALUES (5,50) RETURNING 1),
 ins_t2 AS (INSERT INTO base_t VALUES (6,60) RETURNING 1),
 upd_t AS (UPDATE base_t SET v = v + 100  RETURNING 1),
 dlt_t AS (DELETE FROM base_t WHERE i IN (4,5)  RETURNING 1)
SELECT NULL;
SELECT * FROM mv_self ORDER BY v1;
ROLLBACK;

-- support simultaneous table changes
BEGIN;
CREATE TABLE base_r (i int, v int);
CREATE TABLE base_s (i int, v int);
INSERT INTO base_r VALUES (1, 10), (2, 20), (3, 30);
INSERT INTO base_s VALUES (1, 100), (2, 200), (3, 300);
CREATE INCREMENTAL MATERIALIZED VIEW mv(v1, v2) AS
 SELECT r.v, s.v FROM base_r AS r JOIN base_s AS s USING(i);
SELECT * FROM mv ORDER BY v1;
WITH
 ins_r AS (INSERT INTO base_r VALUES (1,11) RETURNING 1),
 ins_r2 AS (INSERT INTO base_r VALUES (3,33) RETURNING 1),
 ins_s AS (INSERT INTO base_s VALUES (2,222) RETURNING 1),
 upd_r AS (UPDATE base_r SET v = v + 1000 WHERE i = 2 RETURNING 1),
 dlt_s AS (DELETE FROM base_s WHERE i = 3 RETURNING 1)
SELECT NULL;
SELECT * FROM mv ORDER BY v1;
ROLLBACK;

-- support foreign reference constraints
BEGIN;
CREATE TABLE ri1 (i int PRIMARY KEY);
CREATE TABLE ri2 (i int PRIMARY KEY REFERENCES ri1(i) ON UPDATE CASCADE ON DELETE CASCADE, v int);
INSERT INTO ri1 VALUES (1),(2),(3);
INSERT INTO ri2 VALUES (1),(2),(3);
CREATE INCREMENTAL MATERIALIZED VIEW mv_ri(i1, i2) AS
 SELECT ri1.i, ri2.i FROM ri1 JOIN ri2 USING(i);
SELECT * FROM mv_ri ORDER BY i1;
UPDATE ri1 SET i=10 where i=1;
DELETE FROM ri1 WHERE i=2;
SELECT * FROM mv_ri ORDER BY i2;
ROLLBACK;

-- views including NULL
BEGIN;
CREATE TABLE base_t (i int, v int);
INSERT INTO base_t VALUES (1,10),(2, NULL);
CREATE INCREMENTAL MATERIALIZED VIEW mv AS SELECT * FROM base_t;
SELECT * FROM mv ORDER BY i;
UPDATE base_t SET v = 20 WHERE i = 2;
SELECT * FROM mv ORDER BY i;
ROLLBACK;

BEGIN;
CREATE TABLE base_t (i int);
CREATE INCREMENTAL MATERIALIZED VIEW mv AS SELECT * FROM base_t;
SELECT * FROM mv ORDER BY i;
INSERT INTO base_t VALUES (1),(NULL);
SELECT * FROM mv ORDER BY i;
ROLLBACK;

BEGIN;
CREATE TABLE base_t (i int, v int);
INSERT INTO base_t VALUES (NULL, 1), (NULL, 2), (1, 10), (1, 20);
CREATE INCREMENTAL MATERIALIZED VIEW mv AS SELECT i, sum(v) FROM base_t GROUP BY i;
SELECT * FROM mv ORDER BY i;
UPDATE base_t SET v = v * 10;
SELECT * FROM mv ORDER BY i;
ROLLBACK;

BEGIN;
CREATE TABLE base_t (i int, v int);
INSERT INTO base_t VALUES (NULL, 1), (NULL, 2), (NULL, 3), (NULL, 4), (NULL, 5);
CREATE INCREMENTAL MATERIALIZED VIEW mv AS SELECT i, min(v), max(v) FROM base_t GROUP BY i;
SELECT * FROM mv ORDER BY i;
DELETE FROM base_t WHERE v = 1;
SELECT * FROM mv ORDER BY i;
DELETE FROM base_t WHERE v = 3;
SELECT * FROM mv ORDER BY i;
DELETE FROM base_t WHERE v = 5;
SELECT * FROM mv ORDER BY i;
ROLLBACK;

-- IMMV containing user defined type
BEGIN;

CREATE TYPE mytype;
CREATE FUNCTION mytype_in(cstring)
 RETURNS mytype AS 'int4in'
 LANGUAGE INTERNAL STRICT IMMUTABLE;
CREATE FUNCTION mytype_out(mytype)
 RETURNS cstring AS 'int4out'
 LANGUAGE INTERNAL STRICT IMMUTABLE;
CREATE TYPE mytype (
 LIKE = int4,
 INPUT = mytype_in,
 OUTPUT = mytype_out
);

CREATE FUNCTION mytype_eq(mytype, mytype)
 RETURNS bool AS 'int4eq'
 LANGUAGE INTERNAL STRICT IMMUTABLE;
CREATE FUNCTION mytype_lt(mytype, mytype)
 RETURNS bool AS 'int4lt'
 LANGUAGE INTERNAL STRICT IMMUTABLE;
CREATE FUNCTION mytype_cmp(mytype, mytype)
 RETURNS integer AS 'btint4cmp'
 LANGUAGE INTERNAL STRICT IMMUTABLE;

CREATE OPERATOR = (
 leftarg = mytype, rightarg = mytype,
 procedure = mytype_eq);
CREATE OPERATOR < (
 leftarg = mytype, rightarg = mytype,
 procedure = mytype_lt);

CREATE OPERATOR CLASS mytype_ops
 DEFAULT FOR TYPE mytype USING btree AS
 OPERATOR        1       <,
 OPERATOR        3       = ,
 FUNCTION		1		mytype_cmp(mytype,mytype);

CREATE TABLE t_mytype (x mytype);
CREATE INCREMENTAL MATERIALIZED VIEW mv_mytype AS
 SELECT * FROM t_mytype;
INSERT INTO t_mytype VALUES ('1'::mytype);
SELECT * FROM mv_mytype;

ROLLBACK;

-- outer join is not supported
CREATE INCREMENTAL MATERIALIZED VIEW mv(a,b) AS SELECT a.i, b.i FROM mv_base_a a LEFT JOIN mv_base_b b ON a.i=b.i;
-- CTE is not supported
CREATE INCREMENTAL MATERIALIZED VIEW mv AS
    WITH b AS ( SELECT * FROM mv_base_b) SELECT a.i,a.j FROM mv_base_a a, b WHERE a.i = b.i;
-- contain system column
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm01 AS SELECT i,j,xmin FROM mv_base_a;
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm02 AS SELECT i,j FROM mv_base_a WHERE xmin = '610';
-- contain subquery
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm03 AS SELECT i,j FROM mv_base_a WHERE i IN (SELECT i FROM mv_base_b WHERE k < 103 );
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm04 AS SELECT a.i,a.j FROM mv_base_a a, (SELECT * FROM mv_base_b) b WHERE a.i = b.i;
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm05 AS SELECT i,j, (SELECT k FROM mv_base_b b WHERE a.i = b.i) FROM mv_base_a a;
-- contain ORDER BY
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm07 AS SELECT i,j,k FROM mv_base_a a INNER JOIN mv_base_b b USING(i) ORDER BY i,j,k;
-- contain HAVING
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm08 AS SELECT i,j,k FROM mv_base_a a INNER JOIN mv_base_b b USING(i) GROUP BY i,j,k HAVING SUM(i) > 5;

-- contain view or materialized view
CREATE VIEW b_view AS SELECT i,k FROM mv_base_b;
CREATE MATERIALIZED VIEW b_mview AS SELECT i,k FROM mv_base_b;
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm07 AS SELECT a.i,a.j FROM mv_base_a a,b_view b WHERE a.i = b.i;
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm08 AS SELECT a.i,a.j FROM mv_base_a a,b_mview b WHERE a.i = b.i;
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm09 AS SELECT a.i,a.j FROM mv_base_a a, (SELECT i, COUNT(*) FROM mv_base_b GROUP BY i) b WHERE a.i = b.i;
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm10 AS SELECT a.i,a.j FROM mv_base_a a WHERE EXISTS(SELECT 1 FROM mv_base_b b WHERE a.i = b.i) OR a.i > 5;

-- contain mutable functions
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm12 AS SELECT i,j FROM mv_base_a WHERE i = random()::int;

-- LIMIT/OFFSET is not supported
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm13 AS SELECT i,j FROM mv_base_a LIMIT 10 OFFSET 5;

-- DISTINCT ON is not supported
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm14 AS SELECT DISTINCT ON(i) i, j FROM mv_base_a;

-- TABLESAMPLE clause is not supported
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm15 AS SELECT i, j FROM mv_base_a TABLESAMPLE SYSTEM(50);

-- window functions are not supported
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm16 AS SELECT *, cume_dist() OVER (ORDER BY i) AS rank FROM mv_base_a;

-- aggregate function with some options is not supported
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm17 AS SELECT COUNT(*) FILTER(WHERE i < 3) FROM mv_base_a;
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm18 AS SELECT COUNT(DISTINCT i)  FROM mv_base_a;
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm19 AS SELECT array_agg(j ORDER BY i DESC) FROM mv_base_a;
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm20 AS SELECT i,SUM(j) FROM mv_base_a GROUP BY GROUPING SETS((i),());

-- inheritance parent is not supported
BEGIN;
CREATE TABLE parent (i int, v int);
CREATE TABLE child_a(options text) INHERITS(parent);
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm21 AS SELECT * FROM parent;
ROLLBACK;

-- UNION statement is not supported
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm22 AS SELECT i,j FROM mv_base_a UNION ALL SELECT i,k FROM mv_base_b;;

-- empty target list is not allowed with IVM
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm25 AS SELECT FROM mv_base_a;

-- FOR UPDATE/SHARE is not supported
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm26 AS SELECT i,j FROM mv_base_a FOR UPDATE;

-- tartget list cannot contain ivm column that start with '__ivm'
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm28 AS SELECT i AS "__ivm_count__" FROM mv_base_a;

-- expressions specified in GROUP BY must appear in the target list.
CREATE INCREMENTAL MATERIALIZED VIEW  mv_ivm29 AS SELECT COUNT(i) FROM mv_base_a GROUP BY i;

-- experssions containing an aggregate is not supported
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm30 AS SELECT sum(i)*0.5 FROM mv_base_a;
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm31 AS SELECT sum(i)/sum(j) FROM mv_base_a;

-- VALUES is not supported
CREATE INCREMENTAL MATERIALIZED VIEW mv_ivm_only_values1 AS values(1);

-- base table which has row level security
DROP USER IF EXISTS ivm_admin;
DROP USER IF EXISTS ivm_user;
CREATE USER ivm_admin;
CREATE USER ivm_user;
SET SESSION AUTHORIZATION ivm_admin;

CREATE TABLE rls_tbl(id int, data text, owner name);
INSERT INTO rls_tbl VALUES
  (1,'foo','ivm_user'),
  (2,'bar','postgres');
CREATE TABLE num_tbl(id int, num text);
INSERT INTO num_tbl VALUES
  (1,'one'),
  (2,'two'),
  (3,'three'),
  (4,'four');
CREATE POLICY rls_tbl_policy ON rls_tbl FOR SELECT TO PUBLIC USING(owner = current_user);
CREATE POLICY rls_tbl_policy2 ON rls_tbl FOR INSERT TO PUBLIC WITH CHECK(current_user LIKE 'ivm_%');
ALTER TABLE rls_tbl ENABLE ROW LEVEL SECURITY;
GRANT ALL on rls_tbl TO PUBLIC;
GRANT ALL on num_tbl TO PUBLIC;

SET SESSION AUTHORIZATION ivm_user;

CREATE INCREMENTAL MATERIALIZED VIEW  ivm_rls AS SELECT * FROM rls_tbl;
SELECT id, data, owner FROM ivm_rls ORDER BY 1,2,3;
INSERT INTO rls_tbl VALUES
  (3,'baz','ivm_user'),
  (4,'qux','postgres');
SELECT id, data, owner FROM ivm_rls ORDER BY 1,2,3;
CREATE INCREMENTAL MATERIALIZED VIEW  ivm_rls2 AS SELECT * FROM rls_tbl JOIN num_tbl USING(id);

RESET SESSION AUTHORIZATION;

WITH
 x AS (UPDATE rls_tbl SET data = data || '_2' where id in (3,4)),
 y AS (UPDATE num_tbl SET num = num || '_2' where id in (3,4))
SELECT;
SELECT * FROM ivm_rls2 ORDER BY 1,2,3;

DROP TABLE rls_tbl CASCADE;
DROP TABLE num_tbl CASCADE;
DROP USER ivm_user;
DROP USER ivm_admin;

DROP TABLE mv_base_b CASCADE;
DROP TABLE mv_base_a CASCADE;
