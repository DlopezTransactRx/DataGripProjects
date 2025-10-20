-- USE DATABASE CPE_DEV; USE DATABASE CPE_PROD;
-- 10/09 (Thu) =  13 (No Timeouts/Validation Error Only)
-- 10/10 (Fri) =  8 (No Timeouts/Validation Error Only)
-- 10/13 (Mon) =  10 (No Timeouts/Validation Error Only)
-- 10/14 (Tue) = 116 Time Out (Query tool longer than 30 seconds)
-- 10/15 (Wed) = 185 Time OUt (Snowflake Took Long than 30 seconds)

USE ROLE SYSADMIN;
USE DATABASE CPE_PROD;
USE SCHEMA DATA;

SET start_date = TO_TIMESTAMP_NTZ('2025-10-15 00:00:00');  -- inclusive
SET num_days   = 1;
SET end_date   = DATEADD(DAY, $num_days, $start_date);     -- exclusive

WITH BadHttpRequests AS (
  SELECT
      http_request_id,
      request_time,
      response_time,
      status        AS http_status,
      service,
      method,
      elapse_time   AS http_elapsed_raw
  FROM DATA.HTTPS_REQUEST_HISTORY
  WHERE request_time BETWEEN $start_date AND $end_date
    AND status <> 'OK'
    AND service = 'patientrxhistory'
    AND method  = 'query'
),
PatientRxRequest AS (
  SELECT *
  FROM DATA.PATIENT_RX_HISTORY_REQUESTS
  WHERE event_time BETWEEN $start_date AND $end_date
  -- If dup request_ids exist, keep the latest per request_id:
  QUALIFY ROW_NUMBER() OVER (PARTITION BY request_id ORDER BY event_time DESC) = 1
)
SELECT
    p.request_id AS MillimanRequestId,
    h.http_elapsed_raw as HttpElapsedTime,
    p.ELAPSED_TIME_MS as PatRxHistoryElapsedTime,
    q.TOTAL_ELAPSED_TIME As SnwFlkQryElapsedTime,
    h.*,
    p.*,
    q.*
FROM BadHttpRequests AS h
LEFT JOIN PatientRxRequest AS p
  -- use the correct key; if your table has http_request_id, keep that,
  -- otherwise map request_id -> http_request_id.
  ON p.http_request_id = h.http_request_id
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY AS q
  -- no start_time filter; rely on the key
  ON q.query_id = p.query_id
ORDER BY h.request_time DESC;