# postgres_select_tracker
PL/pgSQL functions to copy rows that are selected from a given table(s) to a separate tracking table. Meant to help prune unused rows from datasets used for testing, but could also be useful for auditing purposes. Inspired by [this post](https://www.postgresql.org/message-id/CAFcNs+rrRxsO1W5N7UN_p5MJreh7n61gLm1UqAREEm8D534o3Q@mail.gmail.com) by Fabrízio de Royes Mello.

Example:

```sql
\i /pgst/pgst_install.sql

CREATE TABLE test(col int);
INSERT INTO test VALUES (1), (2), (3);
SELECT pgst_start_for_table('test');

SELECT * FROM test WHERE col < 3;
-- Will return rows 1 and 2

SELECT * FROM test_pgst_track;
-- Will also return rows 1 and 2
```

# Caveats
1. After calling `pgst_start_for_table(<table_name>);`, all selects to the table will have an extra column (which can be ignored)
2. Won't work with tables joined to other tables by an index, because the tracking function will cause PostgreSQL to ignore the index and do a sequential scan.
