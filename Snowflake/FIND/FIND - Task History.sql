----------------------------------------------------------------------------------------------------
-- Target Task
----------------------------------------------------------------------------------------------------
SET (run_group_id, root_task_uuid, task_name, scheduled_time, end_range_unit, end_range_value) = (

    --TODO: Substitute a query that identifies a particular record.
    SELECT
        TASK_META[0]:RUN_GROUP_ID::string,
        TASK_META[0]:ROOT_TASK_UUID::string,
        SPLIT_PART(TASK_META[0]:TASK_NAME::string, '.', 3),
        TASK_META[0]:SCHEDULED_TIME::string,
        'hour', -- End Range Unit
        1 -- End Range Value
    FROM CPE_DEV.RXMARKET.RXPB_AUCTIONS_POC_V2
    LIMIT 1

);

    SELECT $run_group_id, $root_task_uuid, $task_name, $scheduled_time, $end_range_unit, $end_range_value;

----------------------------------------------------------------------------------------------------
-- Informational History
----------------------------------------------------------------------------------------------------
SELECT *
FROM TABLE(
    CPE_DEV.INFORMATION_SCHEMA.TASK_HISTORY(
        ROOT_TASK_ID => $root_task_uuid
        , SCHEDULED_TIME_RANGE_START => TO_TIMESTAMP_LTZ($scheduled_time)
        , SCHEDULED_TIME_RANGE_END => DATEADD($end_range_unit,  $end_range_value, TO_TIMESTAMP_LTZ($scheduled_time))
        ,  TASK_NAME => $task_name
    )
)
WHERE GRAPH_RUN_GROUP_ID = $run_group_id
ORDER BY run_id, scheduled_time;


----------------------------------------------------------------------------------------------------
-- Account History
----------------------------------------------------------------------------------------------------
SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
    WHERE SCHEDULED_TIME BETWEEN $scheduled_time AND DATEADD($end_range_unit,  $end_range_value, $scheduled_time)
    AND NAME = $task_name
    AND ROOT_TASK_ID = $root_task_uuid
    AND GRAPH_RUN_GROUP_ID = $run_group_id;