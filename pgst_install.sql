BEGIN;

CREATE OR REPLACE FUNCTION pgst_suffix_table_name(table_name TEXT, suffix TEXT) RETURNS TEXT AS
$$
	SELECT TEXT (table_name || '_pgst_' || suffix);
$$
LANGUAGE sql IMMUTABLE;


CREATE OR REPLACE FUNCTION pgst_start_for_table(table_name TEXT) RETURNS void AS
$outer$
DECLARE
	data_table_name TEXT;
	track_table_name TEXT;
	track_table_name_func TEXT;
BEGIN
	data_table_name := pgst_suffix_table_name(table_name, 'data');
	track_table_name := pgst_suffix_table_name(table_name, 'track');
	track_table_name_func := track_table_name || '_func';

	EXECUTE 'ALTER TABLE ' || quote_ident(table_name) || ' RENAME TO ' || quote_ident(data_table_name);

	EXECUTE 'CREATE TABLE ' || quote_ident(track_table_name) || '(LIKE ' || quote_ident(data_table_name) || ' INCLUDING ALL)';

	EXECUTE '
		CREATE OR REPLACE FUNCTION ' || quote_ident(track_table_name_func) || '(table_row ' || quote_ident(data_table_name) || ') RETURNS integer AS
		$inner$
		BEGIN
			BEGIN
				INSERT INTO ' || quote_ident(track_table_name) || ' VALUES (table_row.*);
			EXCEPTION WHEN unique_violation THEN
				-- Do nothing
			END;
			RETURN 1;
		END;
		$inner$
		LANGUAGE plpgsql VOLATILE COST 10000;
	';

	EXECUTE format('CREATE VIEW %1$I AS SELECT %2$I.*, %3$I(%2$I.*) FROM %2$I', table_name, data_table_name, track_table_name_func);
END;
$outer$ LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION pgst_start_for_table (TEXT) IS 'Start tracking rows for the given table. The tracked rows will be put in the table <table_name>_pgst_track';


CREATE OR REPLACE FUNCTION pgst_stop_for_table(table_name TEXT, drop_track_table BOOLEAN) RETURNS void AS
$$
DECLARE
	data_table_name TEXT;
	track_table_name TEXT;
	track_table_name_func TEXT;
BEGIN
	data_table_name := pgst_suffix_table_name(table_name, 'data');
	track_table_name := pgst_suffix_table_name(table_name, 'track');
	track_table_name_func := track_table_name || '_func';

	EXECUTE 'DROP VIEW IF EXISTS ' || quote_ident(table_name);

	EXECUTE 'DROP FUNCTION IF EXISTS ' || quote_ident(track_table_name_func) || '(table_row ' || quote_ident(data_table_name) || ')';

	EXECUTE 'ALTER TABLE IF EXISTS ' || quote_ident(data_table_name) || ' RENAME TO ' || quote_ident(table_name);

	IF drop_track_table THEN
		EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(track_table_name);
	END IF;
END;
$$ LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION pgst_stop_for_table (TEXT, BOOLEAN) IS 'Stop tracking rows for the given table, and optionally drop the tracking table';


CREATE OR REPLACE FUNCTION pgst_start_for_all_tables() RETURNS void AS
$$
DECLARE
	table_names CURSOR IS SELECT table_name AS name
		FROM information_schema.tables
		WHERE table_schema = 'public'
		AND table_type = 'BASE TABLE'
		AND table_name NOT LIKE pgst_suffix_table_name('%', 'track');
BEGIN
	FOR tbl IN table_names LOOP
		PERFORM pgst_start_for_table(tbl.name);
	END LOOP;
END;
$$ LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION pgst_start_for_all_tables () IS 'Helper function to start tracking for all tables';


CREATE OR REPLACE FUNCTION pgst_stop_for_all_tables(drop_track_tables BOOLEAN) RETURNS void AS
$$
DECLARE
	view_names CURSOR IS SELECT table_name AS name
		FROM information_schema.tables
		WHERE table_schema = 'public'
		AND table_type = 'VIEW';
BEGIN
	FOR tbl IN view_names LOOP
		PERFORM pgst_stop_for_table(tbl.name, drop_track_tables);
	END LOOP;
END;
$$ LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION pgst_stop_for_all_tables (BOOLEAN) IS 'Helper function to stop tracking for all tables';


CREATE OR REPLACE FUNCTION pgst_replace_with_track_table(table_name TEXT) RETURNS void AS
$$
BEGIN
	EXECUTE 'DROP TABLE ' || quote_ident(table_name);
	EXECUTE 'ALTER TABLE ' || quote_ident(pgst_suffix_table_name(table_name, 'track')) || ' RENAME TO ' || quote_ident(table_name);
END;
$$ LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION pgst_replace_with_track_table (TEXT) IS 'Replace original table with the tracking table';


CREATE OR REPLACE FUNCTION pgst_replace_all_with_track_table() RETURNS void AS
$$
DECLARE
	track_table_names CURSOR IS SELECT table_name AS name
		FROM information_schema.tables
		WHERE table_schema = 'public'
		AND table_name LIKE pgst_suffix_table_name('%', 'track');
BEGIN
	FOR tbl IN track_table_names LOOP
		PERFORM pgst_replace_with_track_table(REPLACE(tbl.name, pgst_suffix_table_name('', 'track'), ''));
	END LOOP;
END;
$$ LANGUAGE plpgsql VOLATILE;

COMMENT ON FUNCTION pgst_replace_all_with_track_table () IS 'Helper function tor replace all tables with the corresponding tracking table';


COMMIT;
