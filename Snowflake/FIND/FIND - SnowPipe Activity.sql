SHOW PIPES;
USE DATABASE CPE_PROD;


-- Show EVENT Imports
SELECT *
FROM snowflake.account_usage.copy_history
WHERE LAST_LOAD_TIME > CURRENT_DATE() - 10
AND pipe_name = 'EVENTS'
AND TABLE_CATALOG_NAME = 'CPE_PROD'
AND ROW_COUNT > 0
AND FILE_NAME LIKE '%copay-pharmacypaymentdeliveries%'
ORDER BY last_load_time DESC
LIMIT 1000;

-- Show CLAIM Imports
SELECT *
FROM snowflake.account_usage.copy_history
WHERE LAST_LOAD_TIME >  CURRENT_DATE()
  AND TABLE_CATALOG_NAME = 'CPE_PROD'
  AND ROW_COUNT > 0
ORDER BY last_load_time DESC
LIMIT 1000;