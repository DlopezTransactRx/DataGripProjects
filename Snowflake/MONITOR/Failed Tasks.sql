USE ROLE SYSADMIN;
USE DATABASE CPE_PROD;
USE SCHEMA DATA;

SET startTime = CURRENT_DATE();
SET endTime = DATEADD(day, 1, $startTime);

WITH ranked_tasks AS (
    SELECT
        STATE AS taskState,
        NAME AS taskName,
        SCHEDULED_TIME AS taskScheduledTime,
        DATABASE_NAME,
        SCHEMA_NAME,
        ROW_NUMBER() OVER (PARTITION BY NAME ORDER BY SCHEDULED_TIME DESC) AS rn
    FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
    WHERE SCHEDULED_TIME BETWEEN $startTime AND $endTime
      AND DATABASE_NAME = CURRENT_DATABASE()
), lastTask as (
    SELECT
        taskState,
        taskName,
        taskScheduledTime,
        DATABASE_NAME,
        SCHEMA_NAME
    FROM ranked_tasks
    WHERE rn = 1
    ORDER BY SCHEMA_NAME, taskScheduledTime DESC
), failedTasks AS (
    SELECT *
    FROM lastTask
    WHERE TASKSTATE = 'FAILED'
)

// See Failed Tasks
SELECT * FROM failedTasks;

//Generate RE-EXECUTE commands for Failed Tasks
-- SELECT 'EXECUTE TASK ' || DATABASE_NAME || '.' || SCHEMA_NAME || '.' || taskName || ';' AS execute_command
-- FROM failedTasks;