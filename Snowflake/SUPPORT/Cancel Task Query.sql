-- List of currently executing tasks
SELECT
    name           AS task_name,
    database_name,
    schema_name,
    query_id,
    query_text,
    scheduled_time,
    completed_time,
    state
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP()),
    RESULT_LIMIT => 10000
))
WHERE query_id IS NOT NULL
  AND state = 'EXECUTING'
ORDER BY scheduled_time DESC;

-- Cancel Query.
SELECT SYSTEM$CANCEL_QUERY('QUERY_ID');