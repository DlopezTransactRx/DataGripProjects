//==========================================================================
// META - Claims Complete
// Target Records = 1615
//==========================================================================
SELECT COUNT(*)
-- SELECT
    -- cc.record_id AS CC_RECORD_ID,
    -- r.record_id AS REV_RECORD_ID,
    -- r.date_time_transaction_processed AS REV_DATE_TIME_TRANSACTION_PROCESSED,
    -- *

FROM CPE_PROD.DATA.CLAIMS_COMPLETE as cc

JOIN CPE_PROD.DATA.CPE_CLAIM_REVERSAL_REQUESTS as r
    ON cc.RX_NUMBER = r.RX_NUMBER
    AND cc.FILL_NUMBER = r.FILL_NUMBER
    AND cc.DATE_OF_SERVICE = r.DATE_OF_SERVICE
    AND cc.SERVICE_PROVIDER_NPI = r.SERVICE_PROVIDER_NPI

WHERE cc.REVERSED = false
    AND cc.RESPONSE_RECEIVED = false
    AND cc.DATE_TIME_TRANSACTION_PROCESSED >= '2025-04-10 00:00:00'
    AND cc.DATE_TIME_TRANSACTION_PROCESSED <= '2025-04-15 00:00:00'
    AND cc.DATE_TIME_TRANSACTION_PROCESSED < r.DATE_TIME_TRANSACTION_PROCESSED
    AND r.DATE_TIME_TRANSACTION_PROCESSED < CURRENT_DATE
    AND cc.RESPONSE_STATUS_CODE IN ('A', 'P', 'C')
    AND r.RESPONSE_STATUS_CODE IN ('A', 'P', 'C')
;

//==========================================================================
// BACKFILL - Claims Complete
// QueryId: https://app.snowflake.com/us-east-1/bob29911/#/compute/history/queries/01bbeea6-010d-2709-003e-27870b38fe16/profile
//==========================================================================
UPDATE CPE_PROD.DATA.CLAIMS_COMPLETE AS target
SET
    target.REVERSED = TRUE,
    target.REVERSED_RECORD_ID = source.REV_RECORD_ID,
    target.REVERSAL_TIME = source.REV_DATE_TIME_TRANSACTION_PROCESSED
FROM
(
    SELECT
        cc.record_id AS CC_RECORD_ID,
        r.record_id AS REV_RECORD_ID,
        r.date_time_transaction_processed AS REV_DATE_TIME_TRANSACTION_PROCESSED
    FROM CPE_PROD.DATA.CLAIMS_COMPLETE as cc
    JOIN CPE_PROD.DATA.CPE_CLAIM_REVERSAL_REQUESTS as r
        ON cc.RX_NUMBER = r.RX_NUMBER
        AND cc.FILL_NUMBER = r.FILL_NUMBER
        AND cc.DATE_OF_SERVICE = r.DATE_OF_SERVICE
        AND cc.SERVICE_PROVIDER_NPI = r.SERVICE_PROVIDER_NPI

    WHERE cc.REVERSED = false
        AND cc.RESPONSE_RECEIVED = false
        AND cc.DATE_TIME_TRANSACTION_PROCESSED >= '2025-04-10 00:00:00'
        AND cc.DATE_TIME_TRANSACTION_PROCESSED <= '2025-04-15 00:00:00'
        AND cc.DATE_TIME_TRANSACTION_PROCESSED < r.DATE_TIME_TRANSACTION_PROCESSED
        AND r.DATE_TIME_TRANSACTION_PROCESSED < CURRENT_DATE
        AND cc.RESPONSE_STATUS_CODE IN ('A', 'P', 'C')
        AND r.RESPONSE_STATUS_CODE IN ('A', 'P', 'C')
) source
WHERE target.RECORD_ID = source.CC_RECORD_ID
;


//^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// Everything Above This Line Was Run In Prod on 20250425
//^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^