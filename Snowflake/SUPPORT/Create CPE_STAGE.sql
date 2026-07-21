--------------------------------------------------------------------------------------------------
-- This script is intended to be run in the ACCOUNT_OPERATIONS_PROD.GOVERNANCE schema.
-- It will clone the CPE_PROD database into a new CPE_STAGE database, and then drop all tasks and procedures in the new stage database.
-- This is useful for creating a safe environment for testing or development without affecting production data or processes.
-- Note all tasks and procedures will be dropped in the CPE_STAGE database.
--------------------------------------------------------------------------------------------------
USE ROLE SYSADMIN;

-- Create Environment Stage Procedure
CREATE OR REPLACE PROCEDURE ACCOUNT_OPERATIONS_PROD.GOVERNANCE.CREATE_ENVIRONMENT_STAGE()
  RETURNS STRING
  LANGUAGE SQL
  EXECUTE AS OWNER
AS
$$
DECLARE
  target_db     STRING  DEFAULT 'CPE_STAGE';
  source_db     STRING  DEFAULT 'CPE_PROD';
  tasks_dropped INT     DEFAULT 0;
  procs_dropped INT     DEFAULT 0;
  guard         INT     DEFAULT 0;
  progressed    BOOLEAN DEFAULT TRUE;
  UNSAFE_TARGET EXCEPTION (-20001, 'Refusing to clone: TARGET_DB must not be CPE_PROD or CPE_DEV.');
  INVALID_TARGET EXCEPTION (-20001, 'Refusing to clone: CPE_STAGE is only allowable TARGET_DB.');
BEGIN

  -- Safety guard: never operate on protected databases.
  IF (UPPER(:target_db) IN ('CPE_PROD', 'CPE_DEV')) THEN
    RAISE UNSAFE_TARGET;
  END IF;

  -- Safety guard: For now only CPE_STAGE is allowed as a target. This can be relaxed later if needed.
  IF (UPPER(:target_db) != 'CPE_STAGE') THEN
      RAISE INVALID_TARGET;
  END IF;

  -- 0) Clone the source database into the stage database (replaces any existing stage).
  EXECUTE IMMEDIATE 'CREATE OR REPLACE DATABASE "' || :target_db || '" CLONE "' || :source_db || '"';

  -- 1) Drop all TASKS. Retry passes handle DAG (predecessor) dependencies.
  WHILE (progressed AND guard < 50) DO
    guard := guard + 1;
    progressed := FALSE;
    EXECUTE IMMEDIATE 'SHOW TASKS IN DATABASE ' || :target_db;
    LET tcur CURSOR FOR
      SELECT "schema_name" AS sch, "name" AS nm
      FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    FOR t IN tcur DO
      BEGIN
        EXECUTE IMMEDIATE 'DROP TASK "' || :target_db || '"."' || t.sch || '"."' || t.nm || '"';
        tasks_dropped := tasks_dropped + 1;
        progressed := TRUE;
      EXCEPTION
        WHEN OTHER THEN NULL;   -- predecessor dependency; a later pass will get it
      END;
    END FOR;
  END WHILE;

  -- 2) Drop all PROCEDURES. Cursor pulls only schema + signature; the DB comes from
  --    :target_db in the loop body (SHOW PROCEDURES' catalog_name column is unreliable).
  EXECUTE IMMEDIATE 'SHOW PROCEDURES IN DATABASE ' || :target_db;
  LET pcur CURSOR FOR
    SELECT "schema_name" AS sch,
           REGEXP_REPLACE("arguments", ' RETURN .*$', '') AS sig
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    WHERE NULLIF("schema_name", '') IS NOT NULL
      AND "schema_name" <> 'INFORMATION_SCHEMA';
  FOR p IN pcur DO
    EXECUTE IMMEDIATE 'DROP PROCEDURE IF EXISTS "' || :target_db || '"."' || p.sch || '".' || p.sig;
    procs_dropped := procs_dropped + 1;
  END FOR;

  RETURN 'Cloned ' || :source_db || ' into ' || :target_db ||
         '; dropped ' || tasks_dropped || ' task(s) and ' ||
         procs_dropped || ' procedure(s).';
END;
$$;

--Execute Procedure
CALL ACCOUNT_OPERATIONS_PROD.GOVERNANCE.CREATE_ENVIRONMENT_STAGE();