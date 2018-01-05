BEGIN;

DROP FUNCTION IF EXISTS pgst_suffix_table_name(TEXT, TEXT);
DROP FUNCTION IF EXISTS pgst_start_for_table(TEXT);
DROP FUNCTION IF EXISTS pgst_stop_for_table(TEXT, BOOLEAN);
DROP FUNCTION IF EXISTS pgst_start_for_all_tables();
DROP FUNCTION IF EXISTS pgst_stop_for_all_tables(BOOLEAN);
DROP FUNCTION IF EXISTS pgst_swap_tracked_tables(BOOLEAN);

COMMIT;
