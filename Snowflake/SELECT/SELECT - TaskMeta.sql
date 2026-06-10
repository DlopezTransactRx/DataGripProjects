----------------------------------------------------------------------------------------------------
-- Following is the select portion to parse the latest history from a task created record.
----------------------------------------------------------------------------------------------------
SELECT
    TASK_META[0]:ROOT_TASK_NAME as ROOT_TASK_NAME,
    TASK_META[0]:ROOT_TASK_UUID as ROOT_TASK_UUID,
    TASK_META[0]:RUN_GROUP_ID   as RUN_GROUP_ID,
    TASK_META[0]:RUN_TIME       as RUN_TIME,
    TASK_META[0]:SCHEDULED_TIME as SCHEDULED_TIME,
    TASK_META[0]:TASK_NAME      as TASK_NAME,
    *
FROM
    <TABLE>
;
