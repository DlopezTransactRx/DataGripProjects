----------------------------------------------------------------------------------------------------
-- Walgreens Traffic By Day
----------------------------------------------------------------------------------------------------
 WITH scopeDate AS (
     SELECT DATEADD('day', -3, CURRENT_TIMESTAMP) AS scopeDate
 ),
  walgreensTransmissions as (
      SELECT  DATE(st.INGESTED_TIMESTAMP) as date, count(*) as cnt
      FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS st
      CROSS JOIN scopeDate s
      WHERE st.INGESTED_TIMESTAMP >= s.scopeDate
      AND st.data:clientId::STRING = 'walgreens'
      GROUP BY ALL
  )
 SELECT * FROM walgreensTransmissions;


----------------------------------------------------------------------------------------------------
-- Walgreens Transmissions
----------------------------------------------------------------------------------------------------
 WITH scopeDate AS (
     SELECT DATEADD('day', -3, CURRENT_TIMESTAMP) AS scopeDate
 ),
 walgreensTransmissions as (
    SELECT st.data:transmissionId::STRING AS transmissionId,
          st.data:serviceDate::STRING    AS serviceDate,
          st.data
    FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS st
    CROSS JOIN scopeDate s
    WHERE
      st.INGESTED_TIMESTAMP >= s.scopeDate
      AND st.data:clientId::STRING = 'walgreens'
)
SELECT * FROM walgreensTransmissions;


----------------------------------------------------------------------------------------------------
-- Walgreens Transactions Log
----------------------------------------------------------------------------------------------------
 WITH scopeDate AS (
     SELECT DATEADD('day', -1, CURRENT_TIMESTAMP) AS scopeDate
 ),
walgreensTransLog AS (
  SELECT *
  FROM CPE_PROD.DATA.TRANSACTION_LOG t
           CROSS JOIN scopeDate s
  WHERE t.TASK_RUN_SCHEDULED_TIME > s.scopeDate
    AND t.REQ_A1_IIN = '019752'
    AND CPH_ORIGIN = 'Walgreens'
)
SELECT * FROM walgreensTransLog;
