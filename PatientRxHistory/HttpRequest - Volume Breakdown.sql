USE DATABASE CPE_PROD;

SET start_date = TO_TIMESTAMP_NTZ('2025-10-15 00:00:00');  -- inclusive
SET num_days   = 1;                                        -- e.g., 1 day
SET end_date   = DATEADD(DAY, $num_days, $start_date);     -- exclusive

-- Set this to TRUE for hourly, FALSE for daily
SET group_by_hour = TRUE;

WITH params AS (
  SELECT $group_by_hour::BOOLEAN AS by_hour
),
base AS (
  SELECT 'TOTAL'              AS CATEGORY, REQUEST_TIME
  FROM DATA.HTTPS_REQUEST_HISTORY
  WHERE REQUEST_TIME BETWEEN $start_date AND $end_date

  UNION ALL
  SELECT 'PatientRxHistory'   AS CATEGORY, REQUEST_TIME
  FROM DATA.HTTPS_REQUEST_HISTORY
  WHERE REQUEST_TIME BETWEEN $start_date AND $end_date
    AND SERVICE = 'patientrxhistory'

  UNION ALL
  SELECT 'ClinicalPlus'       AS CATEGORY, REQUEST_TIME
  FROM DATA.HTTPS_REQUEST_HISTORY
  WHERE REQUEST_TIME BETWEEN $start_date AND $end_date
    AND SERVICE = 'educate'
),
agg AS (
  SELECT
    CATEGORY,
    CASE
      WHEN (SELECT by_hour FROM params)
        THEN DATE_TRUNC('HOUR', REQUEST_TIME)
      ELSE CAST(REQUEST_TIME AS DATE)
    END AS REQUEST_BUCKET,
    COUNT(*) AS TOTAL_REQUESTS
  FROM base
  GROUP BY CATEGORY, REQUEST_BUCKET
)
SELECT
  CATEGORY,
  REQUEST_BUCKET,            -- Date if daily, timestamp (hour) if hourly
  TOTAL_REQUESTS
FROM agg

-- FILTER
WHERE CATEGORY = 'TOTAL' OR  CATEGORY = 'PatientRxHistory'
ORDER BY REQUEST_BUCKET, CATEGORY;