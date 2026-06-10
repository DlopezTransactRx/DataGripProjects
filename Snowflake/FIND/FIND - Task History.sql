----------------------------------------------------------------------------------------------------
-- Target Task Record
----------------------------------------------------------------------------------------------------
SET target_meta = (
    --TODO: Substitute a query that identifies a particular record with TASK_META.
    SELECT TO_JSON(TASK_META)   --NOTE: Must TO_JSON
    FROM CPE_DEV.RXMARKET.RXPB_AUCTIONS_POC_V2
    LIMIT 1
 );

--TODO: Substitute a query that identifies a particular record with TASK_META.
SELECT
      TASK_META[0]:ROOT_TASK_NAME as ROOT_TASK_NAME,
      TASK_META[0]:ROOT_TASK_UUID as ROOT_TASK_UUID,
      TASK_META[0]:RUN_GROUP_ID   as RUN_GROUP_ID,
      TASK_META[0]:RUN_TIME       as RUN_TIME,
      TASK_META[0]:SCHEDULED_TIME as SCHEDULED_TIME,
      TASK_META[0]:TASK_NAME      as TASK_NAME
FROM CPE_DEV.RXMARKET.RXPB_AUCTIONS_POC_V2
LIMIT 10;


----------------------------------------------------------------------------------------------------
-- Select Meta History To Investigate - NOTE: Index 0 is always the latest.
----------------------------------------------------------------------------------------------------

-- View All Task Meta History
WITH META AS (
    SELECT PARSE_JSON($target_meta) as TASK_META
)
, META_HISTORY AS (
    SELECT f.index                as HISTORY_INDEX,
          f.VALUE:ROOT_TASK_NAME as ROOT_TASK_NAME,
          f.VALUE:ROOT_TASK_UUID as ROOT_TASK_UUID,
          f.VALUE:RUN_GROUP_ID   as RUN_GROUP_ID,
          f.VALUE:RUN_TIME       as RUN_TIME,
          f.VALUE:SCHEDULED_TIME as SCHEDULED_TIME,
          f.VALUE:TASK_NAME      as TASK_NAME
    FROM META m,
    LATERAL FLATTEN(input => m.TASK_META) f
)
SELECT * FROM META_HISTORY;


-- Select Index To Investigate
SET history_index = 0;


----------------------------------------------------------------------------------------------------
-- Target Task
----------------------------------------------------------------------------------------------------
SET (run_group_id, root_task_uuid, task_name, scheduled_time, end_range_unit, end_range_value) = (
    WITH META AS (
        SELECT PARSE_JSON($target_meta) as TASK_META
    )
    SELECT
        TASK_META[$history_index]:RUN_GROUP_ID::string,
        TASK_META[$history_index]:ROOT_TASK_UUID::string,
        SPLIT_PART(TASK_META[$history_index]:TASK_NAME::string, '.', 3),
        TASK_META[$history_index]:SCHEDULED_TIME::string,
        'hour', -- End Range Unit
        1 -- End Range Value
    FROM META
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