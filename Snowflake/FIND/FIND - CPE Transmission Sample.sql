-- Get Original Transmission
USE SCHEMA STAGING;
USE WAREHOUSE COMPUTE_WH;

USE DATABASE CPE_DEV;
-- USE DATABASE CPE_PROD;

SELECT
    data:transmissionId::STRING AS transmissionId,
    data:serviceDate::STRING AS serviceDate,
    data,
    *

    FROM
        STAGING.STAGE_CPE_TRANSMISSIONS as t
    ORDER BY
            INGESTED_TIMESTAMP DESC
    LIMIT 10
;