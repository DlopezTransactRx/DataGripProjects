-- Get Original Transmission
USE SCHEMA DATA;
USE WAREHOUSE WH_RESEARCH;

--USE DATABASE CPE_DEV;
USE DATABASE CPE_PROD;

SELECT
     c.RX_NUMBER, c.FILL_NUMBER, c.SERVICE_PROVIDER_NPI, c.DATE_OF_SERVICE, c.REVERSED, c.BIN, c.RESP_MESSAGE, c.RESP_ADDITIONAL_MESSAGE_INFORMATION, r.RESPONSE_STATUS_CODE AS REV_RESPONSE_STATUS_CODE
    --COUNT(*)
    FROM
        DATA.CPE_CLAIM_REVERSAL_REQUESTS as r
    JOIN DATA.CLAIMS_COMPLETE as c
    ON
        c.DATE_TIME_TRANSACTION_PROCESSED >= '2025-01-01'  -- Added time filter
        AND c.DATE_TIME_TRANSACTION_PROCESSED < r.DATE_TIME_TRANSACTION_PROCESSED
        AND c.RX_NUMBER = r.RX_NUMBER
        AND c.FILL_NUMBER = r.FILL_NUMBER
        AND c.DATE_OF_SERVICE = r.DATE_OF_SERVICE
        AND c.SERVICE_PROVIDER_NPI = r.SERVICE_PROVIDER_NPI
        -- Updated logic to handle BIN 747474 without RESPONSE_STATUS_CODE
        AND c.RESPONSE_STATUS_CODE in ('P', 'C', 'A')
        AND c.BIN != '747474'
        AND r.RESPONSE_STATUS_CODE IN ('D', 'Q', 'S') --Duplicates Transactions (Not real ones that need to be reversed)
        AND c.REVERSED = FALSE
limit 10
;


//----------------------------------------------------------------------------------------------------
// Find Voucher Reversals to to attempt to apply new reversal logic to.
// Count (955)  where r.RESPONSE_STATUS_CODE IN ('P', 'C', 'A', 'D', 'Q', 'S')
//---------------------------------------------------------------------------------------------------e
SELECT
    --c.RX_NUMBER, c.FILL_NUMBER, c.SERVICE_PROVIDER_NPI, c.DATE_OF_SERVICE, c.REVERSED, c.BIN, c.RESP_MESSAGE, c.RESP_ADDITIONAL_MESSAGE_INFORMATION, r.RESPONSE_STATUS_CODE AS REV_RESPONSE_STATUS_CODE
    COUNT(*)
    FROM
        DATA.CPE_CLAIM_REVERSAL_REQUESTS as r
    JOIN DATA.CLAIMS_COMPLETE as c
    ON
        --c.DATE_TIME_TRANSACTION_PROCESSED >= '2025-01-01'  -- Added time filter
        --AND
        c.DATE_TIME_TRANSACTION_PROCESSED < r.DATE_TIME_TRANSACTION_PROCESSED
        AND c.RX_NUMBER = r.RX_NUMBER
        AND c.FILL_NUMBER = r.FILL_NUMBER
        AND c.DATE_OF_SERVICE = r.DATE_OF_SERVICE
        AND c.SERVICE_PROVIDER_NPI = r.SERVICE_PROVIDER_NPI
        AND c.RESPONSE_STATUS_CODE in ('P', 'C', 'A') -- Target Paid Claims...
        AND c.REVERSED = FALSE -- That have not been reversed....
        AND r.RESPONSE_STATUS_CODE IN ('P', 'C', 'A', 'D', 'Q', 'S') --Where the status of the REVERSAL is one that would trigger the reversal process....
        --AND (UPPER(c.RESP_MESSAGE) LIKE '%RXADV-A%' OR UPPER(c.RESP_ADDITIONAL_MESSAGE_INFORMATION) LIKE '%RXADV-A%') -- And is a Voucher...
;


SELECT
    COUNT(*)
--cc.RESPONSE_STATUS_CODE, cc.RESP_RESPONSE_STATUS_CODE, cc.TRANSACTION_COUNT
FROM
    DATA.CLAIMS_COMPLETE as cc
WHERE
    cc.RESPONSE_STATUS_CODE != cc.RESP_RESPONSE_STATUS_CODE
    AND cc.TRANSACTION_COUNT = 1
limit 1
;
-- STEP1 -