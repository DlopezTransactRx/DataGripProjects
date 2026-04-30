/*
==============================================================================
Task Revision History
==============================================================================

PURPOSE
-------
Tracks when a Snowflake task's definition (its query_text) has been modified
over time, and shows when each version of the task was active.

WHY THIS IS USEFUL
------------------
Tasks are typically expected to run the same query on every execution. If
someone modifies the task (via CREATE OR REPLACE TASK, ALTER TASK, etc.),
that change isn't always obvious or announced. This query surfaces those
changes by detecting when the query_text differs from one run to the next.

It also handles reversions correctly: if the task is changed from version A
to version B and then back to A, you'll see three separate entries — not two.
Each entry represents a contiguous "run" of identical executions, so you can
see exactly when a change took effect and when it was reverted.

HOW TO READ THE RESULTS
-----------------------
Each row represents one "version" of the task that ran for some period of
time. For example, a task that was modified twice within the time window
might produce three rows:

  version_group  first_scheduled_time   last_scheduled_time   run_count
  1              2026-04-29 00:00       2026-04-29 10:00      11
  2              2026-04-29 11:00       2026-04-29 14:00      4
  3              2026-04-29 15:00       2026-04-30 00:00      10

This reads as: the original version ran 11 times, then someone changed it
and the new version ran 4 times, then it was changed again (or reverted)
and that version ran 10 times.

COLUMNS
-------
  version_group         Sequential id for each distinct version within the window
  first_scheduled_time  When this version first ran
  last_scheduled_time   When this version last ran
  run_count             How many times this version executed
  query_text            The actual SQL that ran for this version
  run_details           VARIANT array with full details for every run in
                        this version (state, query_id, errors, who triggered
                        it, etc.) — useful for drilling into individual runs

PARAMETERS
----------
  DATABASE_NAME  The database containing the task
  SCHEMA_NAME    The schema containing the task
  TASK_NAME      The name of the task to analyze
  START_TIME     Beginning of the time window (inclusive)
  END_TIME       End of the time window (exclusive midnight boundary —
                 e.g. END_TIME = '2026-04-30' covers through 2026-04-29 23:59)

DATA SOURCE
-----------
SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY — has up to 365 days of history but
with ~45 minute latency. For more recent data (last 7 days, near real-time),
substitute INFORMATION_SCHEMA.TASK_HISTORY().

HOW IT WORKS (TECHNICAL)
------------------------
1. task_runs CTE: For each run, uses LAG() to compare its query_text to the
   previous run's query_text. Marks a "1" whenever the text changes, "0"
   when it's the same.

2. versioned CTE: Uses a running SUM() over those change flags to assign
   each consecutive group of identical query_texts a unique version_group
   number. This is a classic "gaps and islands" pattern — every time the
   query_text changes, the version number ticks up.

3. Final SELECT: Groups by version_group to collapse each "island" of
   identical runs into a single row, and uses ARRAY_AGG with OBJECT_CONSTRUCT
   to pack the full per-run details into a JSON array column.
==============================================================================
*/

-- Parameters
SET DATABASE_NAME = 'CPE_PROD';
SET SCHEMA_NAME = 'DATA';
SET TASK_NAME = 'STREAM_TASK_TRANSACTION_LOG';
SET START_TIME = '2026-04-29';
SET END_TIME = '2026-04-30';


-- Task Change History
WITH task_runs AS (
    SELECT
        *,
        -- Detect when query_text changes from the previous run for this task
        CASE
            WHEN query_text = LAG(query_text) OVER (
                PARTITION BY database_name, schema_name, name
                ORDER BY scheduled_time
            )
            THEN 0
            ELSE 1
        END AS is_change
    FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
    WHERE scheduled_time BETWEEN $START_TIME AND $END_TIME
      AND name = $TASK_NAME
      AND SCHEMA_NAME = $SCHEMA_NAME
      AND database_name = $DATABASE_NAME
      AND query_text IS NOT NULL
)
, versioned AS (
    SELECT
        *,
        -- Running sum gives each "island" of identical consecutive query_text a unique id
        SUM(is_change) OVER (
            PARTITION BY database_name, schema_name, name
            ORDER BY scheduled_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS version_group
    FROM task_runs
)
SELECT
    database_name,
    schema_name,
    name AS task_name,
    version_group,
    MIN(scheduled_time) AS first_scheduled_time,
    MAX(scheduled_time) AS last_scheduled_time,
    COUNT(*) AS run_count,
    ANY_VALUE(query_text) AS query_text,
    ARRAY_AGG(
        OBJECT_CONSTRUCT(
            'NAME', name,
            'QUERY_TEXT', query_text,
            'CONDITION_TEXT', condition_text,
            'SCHEMA_NAME', schema_name,
            'TASK_SCHEMA_ID', task_schema_id,
            'DATABASE_NAME', database_name,
            'TASK_DATABASE_ID', task_database_id,
            'SCHEDULED_TIME', scheduled_time,
            'COMPLETED_TIME', completed_time,
            'STATE', state,
            'RETURN_VALUE', return_value,
            'QUERY_ID', query_id,
            'QUERY_START_TIME', query_start_time,
            'ERROR_CODE', error_code,
            'ERROR_MESSAGE', error_message,
            'GRAPH_VERSION', graph_version,
            'RUN_ID', run_id,
            'ROOT_TASK_ID', root_task_id,
            'SCHEDULED_FROM', scheduled_from,
            'INSTANCE_ID', instance_id,
            'ATTEMPT_NUMBER', attempt_number,
            'CONFIG', config,
            'QUERY_HASH', query_hash,
            'QUERY_HASH_VERSION', query_hash_version,
            'QUERY_PARAMETERIZED_HASH', query_parameterized_hash,
            'QUERY_PARAMETERIZED_HASH_VERSION', query_parameterized_hash_version,
            'GRAPH_RUN_GROUP_ID', graph_run_group_id,
            'BACKFILL_INFO', backfill_info,
            'SPCS_JOB_ID', spcs_job_id,
            'SCHEDULED_BY_USER', scheduled_by_user
        )
    ) WITHIN GROUP (ORDER BY scheduled_time) AS run_details
FROM versioned
GROUP BY database_name, schema_name, name, version_group
ORDER BY database_name, schema_name, task_name, first_scheduled_time;