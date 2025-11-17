SHOW ALERTS;

/**
====================================================================================================
View Most recently failed tasks from a given date.
====================================================================================================
**/

--Find Tasks That Have Failed.
set FAIL_DATE = GETDATE();  //Current Time. (Used by Alert)
-- set FAIL_DATE = '2024-10-09 04:56:45.381 -0700';  //Use this when you know the exact task fail date.

SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE STATE IN ('FAILED', 'CANCELLED', 'FAILED_AND_AUTO_SUSPENDED')
AND COMPLETED_TIME >= DATEADD(MINUTE, -90, DATE_TRUNC('minute', TO_TIMESTAMP($FAIL_DATE)))
ORDER BY COMPLETED_TIME DESC
LIMIT 10;


/**
====================================================================================================
View Most Recent attempted by rasdataservices_sql from a given time period.
NOTE: TRIGGERED state indicates the condtion was True, and the Action was Executured.
====================================================================================================
**/
-- set START_DATE = DATEADD(HOUR, -24, GETDATE());     //By Hours
-- set START_DATE = DATEADD(DAY, -3, GETDATE());    //By Days
-- set START_DATE = DATEADD(HOUR, -1, TO_TIMESTAMP(GETDATE())); //Rewind Time an Hour from Right Now.
set START_DATE = DATEADD(HOUR, -1, TO_TIMESTAMP($FAIL_DATE)); //Rewind Time an Hour from Task Fail Date
SELECT $START_DATE;

SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.ALERT_HISTORY
WHERE NAME = 'ALERT_TASK_FAILURE'
AND COMPLETED_TIME >= TO_TIMESTAMP($START_DATE)
ORDER BY COMPLETED_TIME DESC;




/**
====================================================================================================
Test Alert Condition At Points In TIme.  (SCHEDULE_TIME)
====================================================================================================
**/
//ALERT_SCHEDULE_TIME  Simulates When Alert Was Fired.
set ALERT_SCHEDULE_TIME = GETDATE();    //Now
-- set ALERT_SCHEDULE_TIME = '2024-10-09 05:00:00.040 -0700'; //At A Particular Alert SCHEDULRED_TIME.

--Show The Time Being Used For The Condition Query
SELECT DATEADD(MINUTE, -32, DATE_TRUNC('minute', TO_TIMESTAMP($ALERT_SCHEDULE_TIME))) AS CONDITION_TIME;

-- SELECT STATE
SELECT STATE
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE STATE IN ('FAILED', 'CANCELLED', 'FAILED_AND_AUTO_SUSPENDED')
AND COMPLETED_TIME >= DATEADD(MINUTE, -90, DATE_TRUNC('minute', TO_TIMESTAMP($ALERT_SCHEDULE_TIME)))
LIMIT 1;

/**
====================================================================================================
Use to try an locate the original alert query id.
====================================================================================================
**/
set QUERY_ID = '01b792d2-030b-0d72-003e-278704bb042a';
SELECT *
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE QUERY_ID = $QUERY_ID;




/**
====================================================================================================
The following scripsts are used for investingating all aspects of our SnowFlake Fail Task Alert configuration.
====================================================================================================
**/

//Show Integrations
SHOW INTEGRATIONS;

//Get Details of TASK_FAILED_EMAIL_INTEGRATION
DESCRIBE INTEGRATION TASK_FAILED_EMAIL_INTEGRATION;

DESCRIBE INTEGRATION DB_ADMINS_EMAIL_INTEGRATION;
DESCRIBE INTEGRATION DB_ADMINS_EMAIL_INTEGRATION;
DESCRIBE INTEGRATION DB_ADMINS_EMAIL_INTEGRATION;


//Show Alerts
SHOW ALERTS;

//Get Details on Failure Alert.
DESCRIBE ALERT ALERT_TASK_FAILURE;

//Toggle Alert
ALTER ALERT ALERT_TASK_FAILURE SUSPEND;
ALTER ALERT ALERT_TASK_FAILURE RESUME;

--Invoke Alert Manually
EXECUTE ALERT ALERT_TASK_FAILURE;

--Test: Condition of Alert
SELECT STATE
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE STATE IN ('FAILED', 'CANCELLED', 'FAILED_AND_AUTO_SUSPENDED')
AND COMPLETED_TIME >= DATEADD(MINUTE, -90, DATE_TRUNC('minute', TO_TIMESTAMP(GETDATE())))
LIMIT 1

--Test: Invoke Action of Fail Alert (SEND_TASK_FAILURE_NOTIFICATION)
CALL CPE_DEV.DATA.SEND_TASK_FAILURE_NOTIFICATION();

--Show Create Statement of underalying Action for Task Failure Notification.
SHOW PROCEDURES LIKE 'SEND_TASK_FAILURE_NOTIFICATION';
SELECT GET_DDL('PROCEDURE', 'CPE_DEV.DATA.SEND_TASK_FAILURE_NOTIFICATION()');