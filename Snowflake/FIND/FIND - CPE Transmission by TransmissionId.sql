-- Get Original Transmission
USE SCHEMA STAGING;

USE WAREHOUSE WH_RESEARCH;
-- USE WAREHOUSE COMPUTE_WH;

-- USE DATABASE CPE_DEV;
USE DATABASE CPE_PROD;


SELECT
    data:transmissionId::STRING AS transmissionId,
    data:serviceDate::STRING AS serviceDate,
    data

    FROM
        STAGING.STAGE_CPE_TRANSMISSIONS as t
    WHERE
        transmissionId in
        (
    '1380038840502063104'
        )
        AND INGESTED_TIMESTAMP > '2025-06-04 04:21:39.457'
     LIMIT 2
;