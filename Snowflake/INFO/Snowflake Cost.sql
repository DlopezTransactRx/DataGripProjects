 USE ROLE ACCOUNTADMIN;

----------------------------------------------------------------------------------------------------
-- Set the window ONCE, then run any query below.
----------------------------------------------------------------------------------------------------
SET start_date = CURRENT_DATE() - 7;
SET end_date = CURRENT_DATE();


----------------------------------------------------------------------------------------------------
-- sanity check
----------------------------------------------------------------------------------------------------
SELECT $start_date AS start_date, $end_date AS end_date,
       DATEDIFF(day, $start_date, $end_date) + 1 AS days;

----------------------------------------------------------------------------------------------------
-- 1 — Daily detail by account and usage type (dollars)
----------------------------------------------------------------------------------------------------
SELECT usage_date,
       account_name,
       usage_type,
       ROUND(SUM(usage), 4)             AS usage_qty,
       ROUND(SUM(usage_in_currency), 2) AS cost,
       ANY_VALUE(currency)              AS currency
FROM SNOWFLAKE.ORGANIZATION_USAGE.USAGE_IN_CURRENCY_DAILY
WHERE usage_date BETWEEN $start_date AND $end_date
GROUP BY usage_date, account_name, usage_type
ORDER BY usage_date, cost DESC;

----------------------------------------------------------------------------------------------------
-- 2 - Total - Cost Per Account By Day
----------------------------------------------------------------------------------------------------
SELECT
    usage_date,
    account_name,
    ROUND(SUM(usage_in_currency), 2) AS cost
FROM SNOWFLAKE.ORGANIZATION_USAGE.USAGE_IN_CURRENCY_DAILY
WHERE usage_date BETWEEN $start_date AND $end_date
GROUP BY account_name, usage_date
ORDER BY usage_date, account_name;

----------------------------------------------------------------------------------------------------
-- 3 — Daily, usage types pivoted into columns (statement-style)
----------------------------------------------------------------------------------------------------
SELECT usage_date,
       account_name,
       ROUND(SUM(usage_in_currency), 2) AS total,
       ROUND(SUM(IFF(usage_type = 'compute',                    usage_in_currency, 0)), 2) AS compute,
       ROUND(SUM(IFF(usage_type = 'storage',                    usage_in_currency, 0)), 2) AS storage,
       ROUND(SUM(IFF(usage_type = 'cloud services',             usage_in_currency, 0)), 2) AS cloud_services,
       ROUND(SUM(IFF(usage_type ILIKE 'data transfer%',         usage_in_currency, 0)), 2) AS data_transfer,
       ROUND(SUM(IFF(usage_type ILIKE 'automatic clustering%',  usage_in_currency, 0)), 2) AS auto_clustering,
       ROUND(SUM(IFF(usage_type ILIKE 'data transfer%',        usage_in_currency, 0)), 2) AS data_transfer,
       ROUND(SUM(IFF(usage_type ILIKE 'automatic clustering%', usage_in_currency, 0)), 2) AS auto_clustering,
       ROUND(SUM(IFF(usage_type ILIKE '%cortex%'
                  OR usage_type ILIKE '%ai service%'
                  OR usage_type ILIKE '%document ai%'
                  OR usage_type ILIKE '%ml service%',          usage_in_currency, 0)), 2) AS ai_cortex
FROM SNOWFLAKE.ORGANIZATION_USAGE.USAGE_IN_CURRENCY_DAILY
WHERE usage_date BETWEEN $start_date AND $end_date
AND account_name in (
    'EAST',
    'WEST',
    'DATA_SCIENCE'
    )
GROUP BY account_name, usage_date
ORDER BY usage_date;

----------------------------------------------------------------------------------------------------
-- 4 — Range total, one row (reconciles to the statement)
----------------------------------------------------------------------------------------------------
SELECT MIN(usage_date) AS first_day,
       MAX(usage_date) AS last_day,
       usage_type,
       ROUND(SUM(usage_in_currency), 2) AS cost
FROM SNOWFLAKE.ORGANIZATION_USAGE.USAGE_IN_CURRENCY_DAILY
WHERE usage_date BETWEEN $start_date AND $end_date
GROUP BY usage_type
ORDER BY cost DESC;

----------------------------------------------------------------------------------------------------
-- 5 — Daily credits by warehouse (ACCOUNTADMIN, no ORGADMIN needed)
----------------------------------------------------------------------------------------------------
SELECT DATE(start_time)              AS usage_date,
       warehouse_name,
       ROUND(SUM(credits_used), 4)   AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= $start_date
  AND start_time <  DATEADD(day, 1, $end_date)   -- TIMESTAMP column: half-open interval
GROUP BY 1, 2
ORDER BY 1, 3 DESC;

-----------------------------yy-----------------------------------------------------------------------
-- 6 — Daily credits by service type
----------------------------------------------------------------------------------------------------
DESCRIBE VIEW SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY;

SELECT DATE(usage_date)            AS usage_date,
       service_type,
       ROUND(SUM(credits_used), 4) AS credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE usage_date >= $start_date
  AND usage_date <  DATEADD(day, 1, $end_date)
GROUP BY 1, 2
ORDER BY 1, 3 DESC;


//====================================================================================================
// Total Credits Consumed By Warehouse Over Range
//====================================================================================================
SELECT WAREHOUSE_NAME, ROUND(SUM(CREDITS_USED), 2) AS credits, MIN(START_TIME)::DATE AS first_day, MAX(START_TIME)::DATE AS last_day
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME BETWEEN $START_DATE AND $END_DATE
-- AND WAREHOUSE_NAME LIKE '%DATA_SCIENCE%'
GROUP BY WAREHOUSE_NAME
ORDER BY credits DESC;