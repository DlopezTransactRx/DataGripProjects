-------------------------------------------------------------------------------
-- Following is the select portion to parse the latest history from a task created record.
-------------------------------------------------------------------------------
SELECT
    * EXCLUDE (TASK_META),
    TASK_META[0]:ROOT_TASK_NAME    as _TASKMETA_ROOT_TASK_NAME,
    TASK_META[0]:ROOT_TASK_UUID    as _TASKMETA_ROOT_TASK_UUID,
    TASK_META[0]:RUN_GROUP_ID      as _TASKMETA_RUN_GROUP_ID,
    TASK_META[0]:RUN_TIME          as _TASKMETA_RUN_TIME,
    TASK_META[0]:SCHEDULED_TIME    as _TASKMETA_SCHEDULED_TIME,
    TASK_META[0]:TASK_NAME         as _TASKMETA_TASK_NAME
FROM
    <TABLE>
;