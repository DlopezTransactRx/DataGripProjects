SET START_DATE = CURRENT_DATE() - 7;
SET END_DATE = CURRENT_DATE();

//====================================================================================================
// Total Credits Consumed By Warehouse Over Range
//====================================================================================================
-- Total Credits Consumed
SELECT WAREHOUSE_NAME, ROUND(SUM(CREDITS_USED), 2) AS credits, MIN(START_TIME)::DATE AS first_day, MAX(START_TIME)::DATE AS last_day
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME BETWEEN $START_DATE AND $END_DATE
AND WAREHOUSE_NAME LIKE '%DATA_SCIENCE%'
GROUP BY WAREHOUSE_NAME
ORDER BY credits DESC;


//====================================================================================================
// Get Daily Credits Consumed By Warehouse
//====================================================================================================
SET WAREHOUSE_NAME = 'WH_DATAVANT';

-- Credits Consumed By Warehouse
SELECT
    DATE_TRUNC('day', START_TIME)::DATE AS day
     , WAREHOUSE_NAME
     , ROUND(SUM(CREDITS_USED), 3) AS credits_total
     , ROUND(SUM(CREDITS_USED_COMPUTE), 3) AS credits_compute
     , ROUND(SUM(CREDITS_USED_CLOUD_SERVICES),3) AS credits_cloud
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE WAREHOUSE_NAME = $WAREHOUSE_NAME
    AND START_TIME BETWEEN $START_DATE AND $END_DATE
GROUP BY 1, 2
ORDER BY 1;