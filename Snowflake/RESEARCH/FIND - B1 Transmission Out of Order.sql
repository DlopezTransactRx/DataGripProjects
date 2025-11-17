-- Get Original Transmission
USE SCHEMA STAGING;
USE WAREHOUSE WH_RESEARCH;
-- USE DATABASE CPE_DEV;
USE DATABASE CPE_PROD;


SELECT
  data,
  data:transmissionId AS TRANSMISSION_ID
FROM
  CPE_PROD.STAGING.stage_cpe_transmissions
WHERE
  data:transactionCode::STRING = 'B1'
  AND
  (
      UPPER(data:transactions[0]:state::STRING) != 'CREATED'
      OR
      UPPER(data:transactions[0]:type::STRING) != 'REQUEST'
  )
LIMIT 1;