//NOTE: Search and replace <TABLE_NAME> with the name of the table you want to clean up. This will create a backup of the table, truncate it, and then execute the associated stream task to repopulate it.
USE DATABASE CPE_DEV;
USE SCHEMA DATA;

SELECT COUNT(*) FROM <TABLE_NAME>;
CREATE OR REPLACE STREAM STREAM_<TABLE_NAME> ON TABLE STAGING.STAGE_EVENTS APPEND_ONLY = TRUE SHOW_INITIAL_ROWS = TRUE;
TRUNCATE TABLE <TABLE_NAME>;
EXECUTE TASK STREAM_TASK_<TABLE_NAME>;
