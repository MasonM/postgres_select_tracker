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

	IF drop_track_tables THEN
		EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(track_table_name);
	END IF;
END;
$$ LANGUAGE plpgsql VOLATILE;


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


CREATE OR REPLACE FUNCTION pgst_swap_tracked_tables(drop_data_tables BOOLEAN) RETURNS void AS
$$
DECLARE
	track_table_names CURSOR IS SELECT table_name AS name
		FROM information_schema.tables
		WHERE table_schema = 'public'
		AND table_name LIKE pgst_suffix_table_name('%', 'track');
	regular_table_name TEXT;
	tmp_table_name TEXT;
BEGIN
	FOR tbl IN track_table_names LOOP
		regular_table_name := REPLACE(tbl.name, pgst_suffix_table_name('', 'track'), '');
		tmp_table_name := pgst_suffix_table_name(regular_table_name, 'tmp');
		EXECUTE 'ALTER TABLE IF EXISTS ' || quote_ident(regular_table_name) || ' RENAME TO ' || quote_ident(tmp_table_name);
		EXECUTE 'ALTER TABLE IF EXISTS ' || quote_ident(tbl.name) || ' RENAME TO ' || quote_ident(regular_table_name);
		IF drop_track_tables THEN
			EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(tmp_table_name);
		ELSE
			EXECUTE 'ALTER TABLE IF EXISTS ' || quote_ident(tmp_table_name) || ' RENAME TO ' || quote_ident(tbl.name);
		END IF;
	END LOOP;
END;
$$ LANGUAGE plpgsql VOLATILE;

COMMIT;
