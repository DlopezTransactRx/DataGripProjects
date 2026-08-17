/* ---------------------------------------------------------------------------
 * Snowflake task run history — the UI equivalent
 * Returns one row per execution of a single task. This is the same data. Snowsight shows under a task's "Run History" tab.
 * ------------------------------------------------------------------------- */
SET db = 'CPE_PROD';
SET taskName = 'STREAM_TASK_TRANSACTION_LOG';
SET dayz = -7;

SELECT database_name, schema_name, name, state, attempt_number, scheduled_time, query_start_time, completed_time, query_id, run_id, graph_version, error_code, error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
  TASK_NAME => $taskName,
  SCHEDULED_TIME_RANGE_START => DATEADD('day', $dayz, CURRENT_TIMESTAMP())
))
WHERE DATABASE_NAME = $db
ORDER BY scheduled_time DESC;