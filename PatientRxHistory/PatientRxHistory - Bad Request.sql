USE ROLE SYSADMIN;
USE DATABASE CPE_DEV;
--USE DATABASE CPE_PROD;

SET start_date = CURRENT_DATE();
--     SET start_date = TO_TIMESTAMP_NTZ('2025-10-15 00:00:00');  -- inclusive
SET num_days   = 1;                                        -- e.g., 1 day
SET end_date   = DATEADD(DAY, $num_days, $start_date);     -- exclusive

-- PatientRxHistory - Bad Requests
WITH BadHttpRequests AS (
  SELECT
      http_request_id,
      request_time,
      response_time,
      status        AS http_status,
      service,
      method,
      elapse_time   AS http_elapsed_raw
  FROM   DATA.HTTPS_REQUEST_HISTORY
  WHERE  request_time >= $start_date
     AND request_time <  $end_date
     AND status <> 'OK'
     AND service = 'patientrxhistory'
     AND method  = 'query'
),
PatientRxRequest AS (
  SELECT
      bhr.http_request_id,
      bhr.request_time,

      /* Normalize HTTP elapsed to milliseconds:
         "35.000876665s" -> 35000.876665
         "123 ms"        -> 123
         "456"           -> 456
         NULL/garbage    -> diff(request, response)
      */
      COALESCE(
        CASE
          WHEN bhr.http_elapsed_raw ILIKE '%ms' THEN
            TRY_TO_DOUBLE(REGEXP_REPLACE(bhr.http_elapsed_raw, '[^0-9.]+', ''))
          WHEN bhr.http_elapsed_raw ILIKE '%s' THEN
            TRY_TO_DOUBLE(REGEXP_REPLACE(bhr.http_elapsed_raw, '[^0-9.]+', '')) * 1000
          ELSE
            TRY_TO_DOUBLE(REGEXP_REPLACE(bhr.http_elapsed_raw, '[^0-9.]+', ''))
        END,
        DATEDIFF('millisecond', bhr.request_time, bhr.response_time)
      ) AS http_elapsed_ms,

      bhr.http_status,

      /* Keep the latest PHR row per HTTP request */
      phr.query_id,
      phr.status           AS service_status,
      phr.elapsed_time_ms  AS service_elapsed_ms,
      phr.match_found,
      phr.service_error,
      phr.event_time
  FROM BadHttpRequests AS bhr
  JOIN DATA.PATIENT_RX_HISTORY_REQUESTS AS phr
    USING (http_request_id)
  QUALIFY ROW_NUMBER() OVER (
            PARTITION BY bhr.http_request_id
            ORDER BY phr.event_time DESC
          ) = 1
),
WithQueryTime AS (
  SELECT
      query_id,
      start_time,
      total_elapsed_time  AS sf_total_ms,
      compilation_time    AS sf_compile_ms,
      execution_time      AS sf_exec_ms,
      warehouse_name
  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
  WHERE start_time >= $start_date
    AND start_time  < $end_date
)

SELECT
  -- Join key
  p.http_request_id,

  -- HTTP layer
  p.request_time                 AS http_request_time,
  p.http_status,
  p.http_elapsed_ms,

  -- Service layer
  p.service_status,
  p.service_elapsed_ms,
  p.match_found                  AS service_match_found,
  IFF(p.service_error IS NULL, NULL, LEFT(p.service_error, 200)) AS service_error_200,

  -- Snowflake layer
  p.query_id                     AS sf_query_id,
  q.start_time                   AS sf_start_time,
  q.sf_total_ms,
  q.sf_compile_ms,
  q.sf_exec_ms,
  q.warehouse_name               AS sf_warehouse

FROM PatientRxRequest AS p
LEFT JOIN WithQueryTime AS q
  ON q.query_id = p.query_id
ORDER BY p.request_time DESC;