-- Get Original Transmission
USE SCHEMA STAGING;

USE WAREHOUSE WH_RESEARCH;
-- USE WAREHOUSE COMPUTE_WH;

-- USE DATABASE CPE_DEV;
USE DATABASE CPE_PROD;

SELECT
    count(*)
    FROM
        STAGING.STAGE_CPE_TRANSMISSIONS as t
    WHERE
        data:transactionCode::STRING = 'B1'
        AND data:responseStatusCode::STRING = ''
;
