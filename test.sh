#!/bin/bash

assert() {
	if [ $2 ]; then
		echo "[ PASS ] $1";
	else
		echo -e "[\e[31mFAIL\e[0m] $1: \"$2\""
	fi
}

run_sql() {
	docker exec -i pgst_test psql postgres postgres $1 2>&1
}

indent () {
	$1 | sed -e 's/^/    /'
}

if ! docker ps -f 'name=pgst_test' -q > /dev/null; then
	docker run -d --rm --name pgst_test -v $PWD:/pgst postgres:9.4
fi

echo "Setup"
indent run_sql <<EOS
	DROP SCHEMA public CASCADE;
	CREATE SCHEMA public;

	\i /pgst/pgst_install.sql

	CREATE TABLE test(col int);
	INSERT INTO test VALUES (1), (2), (3);
EOS

echo -e "\nTrack first two rows"
indent run_sql <<EOS
	SELECT pgst_start_for_table('test');
	SELECT * FROM test WHERE col < 3;
	SELECT pgst_stop_for_table('test', FALSE);
EOS

echo -e "\nTesting"
ROWS=$(run_sql -t <<< "SELECT STRING_AGG(col::text, ',') FROM test_pgst_track;")
assert "check only first two rows tracked" "$ROWS == 1,2"

ROWS=$(run_sql -t <<< "SELECT STRING_AGG(col::text, ',') FROM test;")
assert "check all three rows still present" "$ROWS == 1,2,3"

echo -e "\nCleanup"
indent run_sql <<< '\i /pgst/pgst_uninstall.sql'
