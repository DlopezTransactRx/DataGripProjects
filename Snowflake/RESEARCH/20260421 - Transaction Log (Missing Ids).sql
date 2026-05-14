--Determine Transmission Ids that do not exist in both tables.
USE WAREHOUSE WH_RESEARCH;

-- Create a table to store missing transmission ids from transaction log.
CREATE OR REPLACE TABLE SANDBOX.DLOPEZ.MISSING_TRANSMISSION_IDS AS
WITH claims_ids AS (
    SELECT transmission_id
    FROM cpe_prod.data.claims_complete_ro
    WHERE transmission_id IS NOT NULL
      AND transmission_id <> ''
    GROUP BY transmission_id
),
txn_ids AS (
    SELECT cph_transmission_id AS transmission_id
    FROM cpe_prod.data.transaction_log
    WHERE cph_transmission_id IS NOT NULL
      AND cph_transmission_id <> ''
    GROUP BY cph_transmission_id
)
SELECT
    c.transmission_id,
    'ONLY_IN_CLAIMS_COMPLETE_RO' AS location
FROM claims_ids c
LEFT JOIN txn_ids t
    ON c.transmission_id = t.transmission_id
WHERE t.transmission_id IS NULL;


    SELECT COUNT(*) FROM SANDBOX.DLOPEZ.MISSING_TRANSMISSION_IDS;
    SELECT * FROM SANDBOX.DLOPEZ.MISSING_TRANSMISSION_IDS LIMIT 10;


-- Missing Transmission Ids Only In Claims Complete By Date
-- WITH transLogIds AS (
--     SELECT TRANSMISSION_ID
--     FROM SANDBOX.DLOPEZ.MISSING_TRANSMISSION_IDS
--     WHERE LOCATION = 'ONLY_IN_CLAIMS_COMPLETE_RO'
-- )
-- SELECT DATE(DATE_TIME_TRANSACTION_PROCESSED) as transDate, COUNT(*)
-- from cpe_prod.data.claims_complete_ro
-- WHERE TRANSMISSION_ID in (SELECT TRANSMISSION_ID FROM transLogIds)
-- GROUP BY DATE(DATE_TIME_TRANSACTION_PROCESSED)
-- ORDER BY transDate ASC;

--     -- Select Sample Entries That Exist Only In Claims Complete
--     WITH transLogIds AS (
--         SELECT TRANSMISSION_ID
--         FROM SANDBOX.DLOPEZ.MISSING_TRANSMISSION_IDS
--         WHERE LOCATION = 'ONLY_IN_CLAIMS_COMPLETE_RO'
--     )
--     SELECT TRANSMISSION_ID, DATE_TIME_TRANSACTION_PROCESSED
--     from cpe_prod.data.claims_complete_ro
--     WHERE TRANSMISSION_ID in (SELECT TRANSMISSION_ID FROM transLogIds)
--     AND DATE(DATE_TIME_TRANSACTION_PROCESSED) = '2026-04-21'
--     ORDER BY DATE_TIME_TRANSACTION_PROCESSED ASC
--     LIMIT 10;

CREATE OR REPLACE TABLE SANDBOX.DLOPEZ.TRANSLOG_REPROCESS_EVENTS_3 AS
WITH transLogIds AS (
    SELECT TRANSMISSION_ID
    FROM SANDBOX.DLOPEZ.MISSING_TRANSMISSION_IDS
    WHERE LOCATION = 'ONLY_IN_CLAIMS_COMPLETE_RO'
),
events AS (
    SELECT
        INGESTED_TIMESTAMP,
        data:transmissionId::STRING AS transmissionId,
        data:serviceDate::STRING AS serviceDate,
        data
    FROM
        CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS as t
    WHERE
        transmissionId in
        (
            SELECT TRANSMISSION_ID FROM transLogIds
        )
)
SELECT * FROM events;


-- Missing Transaction Ids By Date
SELECT DATE(INGESTED_TIMESTAMP) as ingestDate, COUNT(*)
FROM SANDBOX.DLOPEZ.TRANSLOG_REPROCESS_EVENTS_3
GROUP BY ingestDate;


SELECT COUNT(*) FROM SANDBOX.DLOPEZ.MISSING_TRANSMISSION_IDS WHERE LOCATION = 'ONLY_IN_CLAIMS_COMPLETE_RO';

select *
from cpe_prod.data.transaction_log
where cph_transmission_id = '1492203583595311104' LIMIT 1;


SELECT COUNT(*) FROM SANDBOX.DLOPEZ.TRANSLOG_REPROCESS_EVENTS;





-- CREATE OR REPLACE TABLE SANDBOX.DLOPEZ.MISSING_TRANS_STATS AS
WITH MISSING AS (
    SELECT TRANSMISSION_ID FROM SANDBOX.DLOPEZ.MISSING_TRANSMISSION_IDS
    UNION ALL
-- Records I have since fixed.
    SELECT CPH_TRANSMISSION_ID FROM SANDBOX.DLOPEZ.TRANSACTION_LOG_FIXED_RECORDS
)
SELECT
    (SELECT COUNT(*) FROM MISSING) AS MISSING_FROM_TRANSACTION_LOG,
    (SELECT COUNT(DISTINCT TRANSMISSION_ID) FROM CPE_CLAIM_REQUESTS
     WHERE TRANSMISSION_ID IN (SELECT TRANSMISSION_ID FROM MISSING)) AS FOUND_IN_CPE_CLAIM_REQUESTS,
    (SELECT COUNT(DISTINCT TRANSMISSION_ID) FROM CPE_CLAIM_RESPONSES
     WHERE TRANSMISSION_ID IN (SELECT TRANSMISSION_ID FROM MISSING)) AS FOUND_IN_CPE_CLAIM_RESPONSES,
    (SELECT COUNT(DISTINCT TRANSMISSION_ID) FROM CLAIMS_COMPLETE
     WHERE TRANSMISSION_ID IN (SELECT TRANSMISSION_ID FROM MISSING)) AS FOUND_IN_CLAIMS_COMPLETE,
    (SELECT COUNT(*) FROM MISSING M
     WHERE NOT EXISTS (SELECT 1 FROM CPE_CLAIM_REQUESTS  R WHERE R.TRANSMISSION_ID = M.TRANSMISSION_ID)
       AND NOT EXISTS (SELECT 1 FROM CPE_CLAIM_RESPONSES P WHERE P.TRANSMISSION_ID = M.TRANSMISSION_ID)
       AND NOT EXISTS (SELECT 1 FROM CLAIMS_COMPLETE     C WHERE C.TRANSMISSION_ID = M.TRANSMISSION_ID)
    ) AS NOT_FOUND_IN_ANY_TABLE;


//=====================================================================
// Counts Of Missing Requests
//=====================================================================
SELECT * FROM SANDBOX.DLOPEZ.MISSING_TRANS_STATS;



-- Get Transmission IDs by day.
SELECT date(CPH_INGESTED_TIMESTAMP) as ingestDate, COUNT(*) as cnt
FROM SANDBOX.DLOPEZ.TRANSACTION_LOG_FIXED_RECORDS
GROUP BY ingestDate
ORDER BY ingestDate DESC;


-- Missing Transactions
CREATE OR REPLACE TABLE SANDBOX.DLOPEZ.SAMPLE_INCOMPLETE_PAIRS AS

-- Records Identified As Missing Transactions (Not in Transaction Log)
WITH MISSING_TRANSACTIONS AS (
    SELECT CPH_TRANSMISSION_ID
    FROM SANDBOX.DLOPEZ.TRANSACTION_LOG_FIXED_RECORDS
)
-- Requests related to missing transactions.
, REQUESTS AS (
    SELECT RECORD_ID
    FROM CPE_PROD.DATA.CPE_CLAIM_REQUESTS
    WHERE TRANSMISSION_ID IN (SELECT CPH_TRANSMISSION_ID FROM MISSING_TRANSACTIONS)
)
-- Response related to missing transactions. Exclude Rejected Requests (Not real transactions that need to be fixed.
,RESPONSES AS (
    SELECT RECORD_ID
    FROM CPE_PROD.DATA.CPE_CLAIM_RESPONSES
    WHERE TRANSMISSION_ID IN (SELECT CPH_TRANSMISSION_ID FROM MISSING_TRANSACTIONS)
    AND RESPONSE_STATUS_CODE != 'R' -- Exclude Rejected Requests (Not real transactions that need to be fixed.
)
-- Match Requests/Response to find those that are missing from either table
,INCOMPLETE_PAIR AS (
    SELECT
        COALESCE(req.RECORD_ID, res.RECORD_ID) AS RECORD_ID,
        CASE
            WHEN req.RECORD_ID IS NULL THEN 'Missing from Requests'
            WHEN res.RECORD_ID IS NULL THEN 'Missing from Responses'
            ELSE 'In both'
            END AS status
    FROM REQUESTS req
             FULL OUTER JOIN RESPONSES res ON req.RECORD_ID = res.RECORD_ID
    WHERE status <> 'In both'
    ORDER BY status, RECORD_ID
    LIMIT 100 --Grab a sample of 100 records for review.
)
-- Get those Claims Complete Records to see the combined view.
SELECT *
FROM CPE_PROD.DATA.CLAIMS_COMPLETE
WHERE RECORD_ID IN (SELECT RECORD_ID FROM INCOMPLETE_PAIR);




//=====================================================================
// Show Claims Complete Sample along Raw Event (For those Missing Requests)
//=====================================================================
SELECT *
FROM SANDBOX.DLOPEZ.SAMPLE_INCOMPLETE_PAIRS ip
JOIN SANDBOX.DLOPEZ.TRANSLOG_REPROCESS_EVENTS e
ON e.transmissionId = ip.TRANSMISSION_ID;



//=====================================================================
// LIVE: Query Tweak Sample
//=====================================================================
SELECT * FROM SANDBOX.DLOPEZ.SAMPLE_RECORD;

    -- Sample Transmission
    WITH SOURCE AS (

      SELECT *,
         DATA:transmissionId::STRING as TRANSMISSION_ID,
         TRY_TO_TIMESTAMP_NTZ(DATA:created::STRING) AS TIME_RECEIVED_AT_SWITCH
--       FROM SANDBOX.DLOPEZ.TRANSLOG_REPROCESS_EVENTS_3
FROM SANDBOX.DLOPEZ.SAMPLE_RECORD

      -- Exclude transmissions with no transactions (e.g. cancel-on-cycle stubs from Powerline).
      -- They contribute no log rows and would otherwise win the recency dedup below.
      WHERE ARRAY_SIZE(DATA:transactions) > 0

      -- Select the latest Transmission based on Time Received at Switch.  (Latest Ingested Timestamp as tie-breaker)
      QUALIFY ROW_NUMBER() OVER (PARTITION BY TRANSMISSION_ID ORDER BY TIME_RECEIVED_AT_SWITCH DESC NULLS LAST, INGESTED_TIMESTAMP DESC NULLS LAST) = 1
    )

    -- Flatten transactions only.
    ,TXN_FLAT AS (
        SELECT
            t.TRANSMISSION_ID,
            t.DATA,
            t.INGESTED_TIMESTAMP,
            txnObj.value AS TXN,
            txnObj.value:rawData::STRING AS RAW_DATA,
            UPPER(txnObj.value:type::STRING)  AS TXN_TYPE,
            UPPER(txnObj.value:state::STRING) AS TXN_STATE,
            -- A3 Transaction Code, extracted from the fixed header position.
            -- Only computed for REQUEST/CREATED transactions, since the AM07 regex
            -- normalization downstream is request-specific. Responses are NULL here.
            -- Header layout: BIN(6) + Version(2) + TxnCode(2) → bytes 9-10
            CASE
                WHEN UPPER(txnObj.value:type::STRING) = 'REQUEST'
                 AND UPPER(txnObj.value:state::STRING) = 'CREATED'
                THEN TRIM(SUBSTR(txnObj.value:rawData::STRING, 9, 2))
            END AS REQ_TXN_CODE
        FROM SOURCE t,
             LATERAL FLATTEN(INPUT => t.DATA:transactions) AS txnObj
        WHERE
            (UPPER(txnObj.value:type::STRING) = 'REQUEST'  AND UPPER(txnObj.value:state::STRING) = 'CREATED')
         OR (UPPER(txnObj.value:type::STRING) = 'RESPONSE' AND UPPER(txnObj.value:state::STRING) = 'RESPONSETOPHARMACY')
    )
-- SELECT COUNT(*) FROM TXN_FLAT;

    -- Identify Request/Response Claim Pairs
    ,NCPDP_DATA AS (
       SELECT
           -- Transmission Id
           t.TRANSMISSION_ID,

           -- Record Id
           t.TRANSMISSION_ID || IFF(SUBSTR(LTRIM(EXTRACT_NCPDP_FIELD(ncpdpData.value, 'D2', 1), '0'), 0, 12) IS NULL, '', '-' || SUBSTR(LTRIM(EXTRACT_NCPDP_FIELD(ncpdpData.value, 'D2', 1), '0'), 0, 12)) AS RECORD_ID,

           -- Data
           t.DATA,

           -- Ingested Timestamp
           t.INGESTED_TIMESTAMP,

           -- Request Data
           CASE WHEN t.TXN_TYPE = 'REQUEST' AND t.TXN_STATE = 'CREATED' THEN ncpdpData.THIS[0] || CHR(29) || ncpdpData.VALUE END AS REQUEST,

           -- Response Data
           CASE WHEN t.TXN_TYPE = 'RESPONSE' AND t.TXN_STATE = 'RESPONSETOPHARMACY' THEN ncpdpData.THIS[0] || CHR(29) || ncpdpData.VALUE END AS RESPONSE

       FROM TXN_FLAT t,
           LATERAL FLATTEN(INPUT => SPLIT(

-- BUSTED LOGIC
CASE
    -- Only B1 billing REQUESTS need AM07 segment-separator normalization.
    -- The REGEX ensures that individual CLAIM segment groups contain
    -- the GROUP SEPARATOR. Responses and non-B1 requests pass through
    -- unchanged.
    WHEN t.TXN_TYPE = 'REQUEST'
     AND t.TXN_STATE = 'CREATED'
     AND t.REQ_TXN_CODE = 'B1'
    THEN
        REGEXP_REPLACE(
            t.RAW_DATA,
            -- Match: any AM07 segment
            '([^' || CHR(29) || '])(' || CHR(28) || 'AM07)',
            -- Replace with: that char, GS, then FS+AM07
            '\\1' || CHR(29) || '\\2'
        )
    ELSE t.RAW_DATA
END,

               -- Clean
--                 t.RAW_DATA,
                CHR(29)
            )) AS ncpdpData
       WHERE ncpdpData.INDEX > 0
     )
-- SELECT * FROM NCPDP_DATA;

    -- Individual NCPDP Requests (RECORD_ID)
    ,REQUESTS as (
         SELECT
             TRANSMISSION_ID,
             RECORD_ID,
             MAX(REQUEST) as REQUEST
         FROM NCPDP_DATA
         WHERE REQUEST IS NOT NULL
         GROUP BY TRANSMISSION_ID, RECORD_ID
     )

    -- Individual NCPDP Responses (RECORD_ID)
    ,RESPONSES as (
         SELECT
             TRANSMISSION_ID,
             RECORD_ID,
             MAX(RESPONSE) as RESPONSE
         FROM NCPDP_DATA
         WHERE RESPONSE IS NOT NULL
         GROUP BY TRANSMISSION_ID, RECORD_ID
     )

    -- Transaction Level Data (Shared Response)
    ,TRANS as (
         SELECT
             s.TRANSMISSION_ID,
             s.INGESTED_TIMESTAMP as INGESTED_TIMESTAMP,
             s.TIME_RECEIVED_AT_SWITCH,
             s.DATA as DATA,

             MAX(res.RESPONSE) as SHARED_RESPONSE
         FROM SOURCE s
            LEFT JOIN RESPONSES as res
              ON s.TRANSMISSION_ID = res.TRANSMISSION_ID
         GROUP BY ALL
    )

    -- Final Claims Table Combining Requests and Responses
    ,TRANS_PAIRS AS (
         SELECT
             trx.TRANSMISSION_ID,
             req.RECORD_ID,
             trx.INGESTED_TIMESTAMP,
             IFF(res.RESPONSE IS NOT NULL, 'RECORD_MATCH', 'TXN_SHARED') AS response_match_type,
             req.REQUEST,
             COALESCE(res.RESPONSE, trx.SHARED_RESPONSE) AS RESPONSE,
             MD5(trx.TRANSMISSION_ID || '|' || COALESCE(REQUEST, '') || '|' || COALESCE(COALESCE(res.RESPONSE, trx.SHARED_RESPONSE), ''))  AS HASH_KEY,
             trx.DATA
         FROM REQUESTS as req
            LEFT JOIN TRANS as trx
              ON req.TRANSMISSION_ID = trx.TRANSMISSION_ID
            LEFT JOIN RESPONSES as res
              ON req.TRANSMISSION_ID = res.TRANSMISSION_ID
            AND req.RECORD_ID = res.RECORD_ID
     )

    ,CLAIMS AS (
        SELECT
        ----------------------------------------------------------------------------------------------------
        --[CLAIMS HEADER PAYLOAD FIELDS]
        ----------------------------------------------------------------------------------------------------
        HASH_KEY,
        TRANSMISSION_ID                                                               AS CPH_TRANSMISSION_ID,
        RECORD_ID,
        INGESTED_TIMESTAMP                                                            AS CPH_INGESTED_TIMESTAMP,
        DATA:routingAddress::STRING                                                   AS CPH_ROUTING_ADDRESS,
        DATA:origin::STRING                                                           AS CPH_ORIGIN,
        DATA:returned::STRING                                                         AS CPH_RETURNED_TIMESTAMP,
        DATA:created::STRING                                                          AS CPH_CREATED_TIMESTAMP,
        DATA:pcn::STRING                                                              AS CPH_A4_PCN,
        DATA:ncpdp::STRING                                                            AS CPH_B107_SERVICE_PROVIDER_NCPDP,
        DATA:npi::STRING                                                              AS CPH_B101_SERVICE_PROVIDER_NPI,

        TRIM(SUBSTR(REQUEST, 9, 2))                                                   AS CPH_A3_TRANSACTION_CODE_RAW,
        CASE
            WHEN UPPER(CPH_A3_TRANSACTION_CODE_RAW)  = 'Q1' THEN 'B1'  -- Claim
            WHEN UPPER(CPH_A3_TRANSACTION_CODE_RAW)  = 'Q2' THEN 'B2'  -- Reversal
            ELSE CPH_A3_TRANSACTION_CODE_RAW
        END AS CPH_A3_TRANSACTION_CODE,

        TRIM(DATA:bin::STRING)                                                              AS CPH_A1_IIN_RAW,
        CASE
            WHEN UPPER(CPH_A1_IIN_RAW) = 'INFORX' THEN '000000'
            WHEN UPPER(CPH_A1_IIN_RAW) = 'CASH' THEN '000000'
            WHEN UPPER(CPH_A1_IIN_RAW) = '747474' THEN '000000'
            ELSE CPH_A1_IIN_RAW
        END AS CPH_A1_IIN,

        TRIM(DATA:responseStatusCode::STRING)                                               AS CPH_AN_TRANSACTION_RESPONSE_STATUS_RAW,
        CASE
            WHEN CPH_A1_IIN = '000000' AND NULLIF(CPH_AN_TRANSACTION_RESPONSE_STATUS_RAW, '') IS NULL THEN 'C'
            ELSE CPH_AN_TRANSACTION_RESPONSE_STATUS_RAW
         END AS CPH_AN_TRANSACTION_RESPONSE_STATUS,

        ----------------------------------------------------------------------------------------------------
        --[REQUEST FIELDS]
        ----------------------------------------------------------------------------------------------------

        -- NCPDP SEGMENT (TRANSACTION HEADER)
        TRIM(SUBSTR(REQUEST, 0, 6))                                                   AS REQ_A1_IIN,                                                 //HEADER [Position: 1–6   = BIN (A1, 6 chars)]
        TRIM(SUBSTR(REQUEST, 7, 2))                                                   AS CPH_A2_VERSION,                                               //HEADER [Position: 7–8   = Version (A2, 2 chars)]
        TRIM(SUBSTR(REQUEST, 11, 10))                                                 AS REQ_A4_PCN,                                                 //HEADER [Position: 11–20 = Processor Control (A4, 10 chars)]
        TRY_TO_NUMBER(TRIM(SUBSTR(REQUEST, 21, 1)))                                   AS CPH_A9_TRANSACTION_COUNT,                                   //HEADER [Position: 21    = Transaction Count (A9, 1 char)]
        TRIM(SUBSTR(REQUEST, 22, 2))                                                  AS REQ_B2_SERVICE_PROVIDER_ID_QUALIFIER,                       //HEADER [Position: 22–23 = Service Provider Qualifier (B2, 2 chars)]
        TRIM(SUBSTR(REQUEST, 24, 15))                                                 AS REQ_B1_SERVICE_PROVIDER_ID,                                 //HEADER [Position: 24–38 = Service Provider ID (B1, 15 chars)]
        TRY_TO_DATE(TRIM(SUBSTR(REQUEST, 39, 8)), 'YYYYMMDD')                         AS REQ_D1_DATE_OF_SERVICE,                                     //HEADER [Position: 39–46 = Date of Service (D1, 8 chars)]
        TRIM(SUBSTR(REQUEST, 47, 10))                                                 AS REQ_AK_SOFTWARE_VENDOR_ID,                                  //HEADER [Position: 47–56 = Vendor/Cert ID (AK, 10 chars)]

        -- NCPDP SEGMENT (INSURANCE)
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C2', 1))                                   AS REQ_C2_CARDHOLDER_ID,                                       //INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C3', 1))                                   AS REQ_C3_PERSON_CODE,                                         //INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C6', 1))                                   AS REQ_C6_PATIENT_RELATIONSHIP_CODE,                           //INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CC', 1))                                   AS REQ_CC_CARDHOLDER_FIRST_NAME,                               //INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CD', 1))                                   AS REQ_CD_CARDHOLDER_LAST_NAME,                                //INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2A', 1))                                   AS REQ_2A_MEDIGAP_ID,                                          //INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C1', 1))                                   AS REQ_C1_GROUP_ID,                                            //INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C9', 1))                                   AS REQ_C9_ELIGIBILITY_CLARIFICATION_CODE,                      //INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'N5', 1))                                   AS REQ_N5_MEDICAID_ID_NUMBER,                                  //INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'FO', 1))                                   AS REQ_FO_PLAN_ID,                                             //INSURANCE

        -- NCPDP SEGMENT (PATIENT)
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CA', 1))                                   AS REQ_CA_PATIENT_FIRST_NAME,                                  //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CB', 1))                                   AS REQ_CB_PATIENT_LAST_NAME,                                   //PATIENT
        TRY_TO_DATE(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C4', 1)), 'YYYYMMDD')         AS REQ_C4_PATIENT_DATE_OF_BIRTH,                               //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C5', 1))                                   AS REQ_C5_PATIENT_GENDER_CODE,                                 //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CY', 1))                                   AS REQ_CY_PATIENT_ID,                                          //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CX', 1))                                   AS REQ_CX_PATIENT_ID_QUALIFIER,                                //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CM', 1))                                   AS REQ_CM_PATIENT_STREET_ADDRESS,                              //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CN', 1))                                   AS REQ_CN_PATIENT_CITY,                                        //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CO', 1))                                   AS REQ_CO_PATIENT_STATE,                                       //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CP', 1))                                   AS REQ_CP_PATIENT_ZIP,                                         //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C7', 1))                                   AS REQ_C7_PLACE_OF_SERVICE,                                    //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '4X', 1))                                   AS REQ_4X_PATIENT_RESIDENCE,                                   //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CQ', 1))                                   AS REQ_CQ_PATIENT_TELEPHONE_NUMBER,                            //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2C', 1))                                   AS REQ_2C_PREGNANCY_INDICATOR,                                 //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CZ', 1))                                   AS REQ_CZ_EMPLOYER_ID,                                         //PATIENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'HN', 1))                                   AS REQ_HN_PATIENT_EMAIL_ADDRESS,                               //PATIENT

        --=[GROUPED SEGMENTS]=--

        -- NCPDP SEGMENT (CLAIM)
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '28', 1))                                   AS REQ_28_UNIT_OF_MEASURE,                                     //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C8', 1))                                   AS REQ_C8_OTHER_COVERAGE_CODE,                                 //CLAIM
        SUBSTR(LTRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D2', 1), '0'), 0, 12)              AS REQ_D2_RX_NUMBER,                                           //CLAIM
        TRY_TO_NUMBER(EXTRACT_NCPDP_FIELD(REQUEST, 'D3', 1))                          AS REQ_D3_FILL_NUMBER,                                         //CLAIM
        IFF(LTRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D3', 1), '0') = '' OR LTRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D3', 1), '0') IS NULL, '0', LTRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D3', 1), '0')) AS FILL_NUMBER, //CLAIM
        TRY_TO_NUMBER(EXTRACT_NCPDP_FIELD(REQUEST, 'D5', 1))                          AS REQ_D5_DAYS_SUPPLY,                                         //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D6', 1))                                   AS REQ_D6_COMPOUND_CODE,                                       //CLAIM
        TRY_TO_NUMBER(EXTRACT_NCPDP_FIELD(REQUEST, 'DF', 1))                          AS REQ_DF_NUMBER_OF_REFILLS_AUTHORIZED,                        //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DI', 1))                                   AS REQ_DI_LEVEL_OF_SERVICE,                                    //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DT', 1))                                   AS REQ_DT_SPECIAL_PACKAGING_INDICATOR,                         //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DJ', 1))                                   AS REQ_DJ_PRESCRIPTION_ORIGIN_CODE,                            //CLAIM
        TRY_TO_DATE(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DE', 1)), 'YYYYMMDD')         AS REQ_DE_DATE_PRESCRIPTION_WRITTEN,                           //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EA', 1))                                   AS REQ_EA_ORIGINALLY_PRESCRIBED_PRODUCT_CODE,                  //CLAIM
        TRY_TO_NUMBER(EXTRACT_NCPDP_FIELD(REQUEST, 'EB', 1))                          AS REQ_EB_ORIGINALLY_PRESCRIBED_QUANTITY,                      //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EJ', 1))                                   AS REQ_EJ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER,          //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EN', 1))                                   AS REQ_EN_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER,            //CLAIM
        TRY_TO_DATE(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EP', 1)), 'YYYYMMDD')         AS REQ_EP_ASSOCIATED_PRESCRIPTION_DATE,                        //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EM', 1))                                   AS REQ_EM_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER,             //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EU', 1))                                   AS REQ_EU_PRIOR_AUTHORIZATION_TYPE_CODE,                       //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D7', 1))                                   AS REQ_D7_PRODUCT_ID,                                          //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'E1', 1))                                   AS REQ_E1_PRODUCT_ID_QUALIFIER,                                //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D8', 1))                                   AS REQ_D8_DAW_PRODUCT_SELECTION_CODE,                          //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DK', 1))                                   AS REQ_DK_SUBMISSION_CLARIFICATION_CODE,                       //CLAIM
        TRY_TO_NUMBER(EXTRACT_NCPDP_FIELD(REQUEST, 'E7', 1)) / 1000                   AS REQ_E7_QUANTITY_DISPENSED,                                  //CLAIM
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EK', 1)))                    AS REQ_EK_SCHEDULED_PRESCRIPTION_ID_NUMBER,                    //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'K5', 1))                                   AS REQ_K5_TRANSACTION_REFERENCE_NUMBER,                        //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'HD', 1))                                   AS REQ_HD_DISPENSING_STATUS,                                   //CLAIM
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'U7', 1))                                   AS REQ_U7_PHARMACY_SERVICE_TYPE,                               //CLAIM
        CASE WHEN REQ_E1_PRODUCT_ID_QUALIFIER = '03' THEN REQ_D7_PRODUCT_ID END       AS REQ_D703_NDC,                                               //CLAIM

        -- NCPDP SEGMENT (PRICING)
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'DQ', 1))                   AS REQ_DQ_USUAL_AND_CUSTOMARY,                                 //PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'DX', 1))                   AS REQ_DX_PATIENT_PAY_AMOUNT_REPORTED,                         //PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'D9', 1))                   AS REQ_D9_INGREDIENT_COST_SUBMITTED,                           //PRICING
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DN', 1))                                   AS REQ_DN_BASIS_OF_COST_DETERMINATION,                         //PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'DC', 1))                   AS REQ_DC_DISPENSING_FEE_SUBMITTED,                            //PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'E3', 1))                   AS REQ_E3_INCENTIVE_AMOUNT_SUBMITTED,                          //PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'BE', 1))                   AS REQ_BE_PROFESSIONAL_SERVICE_FEE_SUBMITTED,                  //PRICING
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'H8', 1))                                   AS REQ_H8_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER,            //PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'H9', 1))                   AS REQ_H9_OTHER_AMOUNT_CLAIMED_SUBMITTED,                      //PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'HA', 1))                   AS REQ_HA_REGULATORY_FEE_AMOUNT_SUBMITTED,                     //PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'GE', 1))                   AS REQ_GE_PERCENTAGE_TAX_AMOUNT_SUBMITTED,                     //PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'DU', 1))                   AS REQ_DU_GROSS_AMOUNT_DUE,                                    //PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'JE', 1))                   AS REQ_JE_PERCENTAGE_TAX_BASIS_SUBMITTED,                      //PRICING

        -- NCPDP SEGMENT (FACILITY)
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '8C', 1))                                   AS REQ_8C_FACILITY_ID,                                         //FACILITY
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '6D', 1))                                   AS REQ_6D_PHARMACY_ZIP,                                        //FACILITY

        -- NCPDP SEGMENT (PRESCRIBER)
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EZ', 1))                                   AS REQ_EZ_PRESCRIBER_ID_QUALIFIER,                             //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DR', 1))                                   AS REQ_DR_PRESCRIBER_LAST_NAME,                                //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2J', 1))                                   AS REQ_2J_PRESCRIBER_FIRST_NAME,                               //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2K', 1))                                   AS REQ_2K_PRESCRIBER_STREET_ADDRESS,                           //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2M', 1))                                   AS REQ_2M_PRESCRIBER_CITY,                                     //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2N', 1))                                   AS REQ_2N_PRESCRIBER_STATE,                                    //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2P', 1))                                   AS REQ_2P_PRESCRIBER_ZIP,                                      //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'PM', 1))                                   AS REQ_PM_PRESCRIBER_TELEPHONE_NUMBER,                         //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DL', 1))                                   AS REQ_DL_PRIMARY_CARE_PROVIDER_ID,                            //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2E', 1))                                   AS REQ_2E_PRIMARY_CARE_PROVIDER_ID_QUALIFIER,                  //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DB', 1))                                   AS REQ_DB_PRESCRIBER_ID,                                       //PRESCRIBER
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '4E', 1))                                   AS REQ_4E_PRIMARY_CARE_PROVIDER_LAST_NAME,                     //PRESCRIBER
        CASE WHEN REQ_EZ_PRESCRIBER_ID_QUALIFIER = '01' THEN REQ_DB_PRESCRIBER_ID END AS REQ_DB01_PRESCRIBER_NPI,                                    //PRESCRIBER

        -- NCPDP SEGMENT (COORDINATION)
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '5E', 1)))                    AS REQ_5E_OTHER_PAYER_REJECT_COUNT,                            //COORDINATION OF BENEFITS
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(REQUEST, '6E', '~~~'), '~~~'), x -> TRIM(x)) AS REQ_6E_OTHER_PAYER_REJECT_CODE,     //COORDINATION OF BENEFITS
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'DV', 1))                   AS REQ_DV_OTHER_PAYER_AMOUNT_PAID,                             //COORDINATION OF BENEFITS
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(REQUEST, 'NP', '~~~'), '~~~'), x -> TRIM(x)) AS REQ_NP_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_QUALIFIER,           //COORDINATION OF BENEFITS
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'NR', 1)))                    AS REQ_NR_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_COUNT,                                      //COORDINATION OF BENEFITS
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED(REQUEST, 'NQ')), x -> PARSE_NCPDP_CURRENCY(x)) AS REQ_NQ_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT,       //COORDINATION OF BENEFITS
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(REQUEST, '6C', '~~~'), '~~~'), x -> TRIM(x)) AS REQ_6C_OTHER_PAYER_ID_QUALIFIER,                                      //COORDINATION OF BENEFITS
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'HC', 1))                                   AS REQ_HC_OTHER_PAYER_AMOUNT_PAID_QUALIFIER,                   //COORDINATION OF BENEFITS
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '4C', 1)))                    AS REQ_4C_COORDINATION_OF_BENEFITS_COUNT,                      //COORDINATION OF BENEFITS
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '5C', 1))                                   AS REQ_5C_OTHER_PAYER_COVERAGE_TYPE,                           //COORDINATION OF BENEFITS
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(REQUEST, '7C', '~~~'), '~~~'), x -> TRIM(x)) AS REQ_7C_OTHER_PAYER_ID,                //COORDINATION OF BENEFITS

        -- NCPDP SEGMENT (WORKERS COMPENSATION)
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'TZ', 1))                                   AS REQ_TZ_GENERIC_EQUIVALENT_PRODUCT_ID_QUALIFIER,             //WORKERS COMPENSATION
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'UA', 1))                                   AS REQ_UA_GENERIC_EQUIVALENT_PRODUCT_ID,                       //WORKERS COMPENSATION
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CF', 1))                                   AS REQ_CF_EMPLOYER_NAME,                                       //WORKERS COMPENSATION
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CG', 1))                                   AS REQ_CG_EMPLOYER_STREET_ADDRESS,                             //WORKERS COMPENSATION
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CH', 1))                                   AS REQ_CH_EMPLOYER_CITY,                                       //WORKERS COMPENSATION
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CI', 1))                                   AS REQ_CI_EMPLOYER_STATE,                                      //WORKERS COMPENSATION
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CJ', 1))                                   AS REQ_CJ_EMPLOYER_ZIP,                                        //WORKERS COMPENSATION
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CK', 1))                                   AS REQ_CK_EMPLOYER_TELEPHONE_NUMBER,                           //WORKERS COMPENSATION
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DZ', 1))                                   AS REQ_DZ_WORKERS_COMP_CLAIM_ID,                               //WORKERS COMPENSATION
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CR', 1))                                   AS REQ_CR_CARRIER_ID,                                          //WORKERS COMPENSATION
        TRY_TO_DATE(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DY', 1)), 'YYYYMMDD')         AS REQ_DY_DATE_OF_INJURY,                                      //WORKERS COMPENSATION

        -- NCPDP SEGMENT (DUR/PPS)
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'E4', 1))                                   AS REQ_E4_REASON_FOR_SERVICE_CODE,                             //DUR/PPS SEGMENT
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'E5', 1))                                   AS REQ_E5_PROFESSIONAL_SERVICE_CODE,                           //DUR/PPS SEGMENT

        -- NCPDP SEGMENT (COMPOUND)
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EC', 1)))                    AS REQ_EC_COMPOUND_INGREDIENT_COMPONENT_COUNT,                 //COMPOUND
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'ED', 1)))                    AS REQ_ED_COMPOUND_INGREDIENT_QUANTITY,                        //COMPOUND
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'EE', 1))                   AS REQ_EE_COMPOUND_INGREDIENT_DRUG_COST,                       //COMPOUND
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'RE', 1))                                   AS REQ_RE_COMPOUND_PRODUCT_ID_QUALIFIER,                       //COMPOUND
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(REQUEST, 'TE', '~~~'), '~~~'), x -> TRIM(x)) AS REQ_TE_COMPOUND_PRODUCT_ID,          //COMPOUND

        -- NCPDP SEGMENT (CLINICAL)
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(REQUEST, 'DO', '~~~'), '~~~'), x -> TRIM(x)) AS REQ_DO_DIAGNOSIS_CODE,               //CLINICAL
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(REQUEST, 'WE', '~~~'), '~~~'), x -> TRIM(x)) AS REQ_WE_DIAGNOSIS_CODE_QUALIFIER,     //CLINICAL
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'VE', 1)))                    AS REQ_VE_DIAGNOSIS_CODE_COUNT,                                //CLINICAL

        -- NCPDP SEGMENT (FACILITY)
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '5J', 1))                                   AS REQ_5J_PHARMACY_CITY,                                       //FACILITY
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '3Q', 1))                                   AS REQ_3Q_PHARMACY_NAME,                                       //FACILITY
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '3U', 1))                                   AS REQ_3U_PHARMACY_STREET_ADDRESS,                             //FACILITY
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '3V', 1))                                   AS REQ_3V_PHARMACY_STATE,                                      //FACILITY

        -- NCPDP SEGMENT (NARRATIVE)
        TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'BM', 1))                                   AS REQ_BM_NARRATIVE_MESSAGE,                                   //NARRATIVE

        ----------------------------------------------------------------------------------------------------
        --[RESPONSE FIELDS]
        ----------------------------------------------------------------------------------------------------

        -- NCPDP SEGMENT (RESPONSE MESSAGE)
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'F4', 1))                                  AS RES_F4_MESSAGE,                                             //RESPONSE MESSAGE

        -- NCPDP SEGMENT (RESPONSE INSURANCE)
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'C1', 1))                                  AS RES_C1_GROUP_ID,                                            //RESPONSE INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, '2F', 1))                                  AS RES_2F_NETWORK_REIMBURSEMENT_ID,                            //RESPONSE INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'J8', 1))                                  AS RES_J8_PAYER_ID,                                            //RESPONSE INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'J7', 1))                                  AS RES_J7_PAYER_ID_QUALIFIER,                                  //RESPONSE INSURANCE
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'FO', 1))                                  AS RES_FO_PLAN_ID,                                             //RESPONSE INSURANCE

        -- NCPDP SEGMENT (RESPONSE STATUS)
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'FA', 1)))                   AS RES_FA_REJECT_COUNT,                                        //RESPONSE STATUS
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'F3', 1))                                  AS RES_F3_AUTHORIZATION_NUMBER,                                //RESPONSE STATUS
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'UH', '~~~'), '~~~'), x -> TRIM(x))   AS RES_UH_ADDITIONAL_MESSAGE_INFORMATION_QUALIFIER,            //RESPONSE STATUS
        TRIM(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'UG', ','))                      AS RES_UG_ADDITIONAL_MESSAGE_INFORMATION_CONTINUITY,           //RESPONSE STATUS
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, '5F', 1)))                   AS RES_5F_APPROVED_MESSAGE_COUNT,                          //RESPONSE STATUS
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, '6F', '~~~'), '~~~'), x -> TRIM(x)) AS RES_6F_APPROVED_MESSAGE_CODE, //RESPONSE STATUS
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'UF', 1)))                   AS RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT,                //RESPONSE STATUS
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'FB', '~~~'), '~~~'), x -> TRIM(x)) AS RES_FB_REJECT_CODE,                 //RESPONSE STATUS
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'AN', 1))                                  AS RES_AN_TRANSACTION_RESPONSE_STATUS,                         //RESPONSE STATUS
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'FQ', '~~~'), '~~~'), x -> TRIM(x)) AS RES_FQ_ADDITIONAL_MESSAGE_INFORMATION,                      //RESPONSE STATUS

        -- NCPDP SEGMENT (RESPONSE PRICING)
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FH', 1))                  AS RES_FH_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE,               //RESPONSE PRICING
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'AV', 1))                                  AS RES_AV_PERCENTAGE_TAX_EXEMPT_INDICATOR,                     //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'F5', 1))                  AS RES_F5_PATIENT_PAY_AMOUNT,                                  //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'F6', 1))                  AS RES_F6_INGREDIENT_COST_PAID,                                //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'F7', 1))                  AS RES_F7_DISPENSING_FEE_PAID,                                 //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FL', 1))                  AS RES_FL_INCENTIVE_AMOUNT_PAID,                               //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'J1', 1))                  AS RES_J1_PROFESSIONAL_SERVICE_FEE_PAID,                       //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'J5', 1))                  AS RES_J5_OTHER_PAYER_AMOUNT_RECOGNIZED,                       //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'AW', 1))                  AS RES_AW_REGULATORY_FEE_AMOUNT_PAID,                          //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'AX', 1))                  AS RES_AX_PERCENTAGE_TAX_AMOUNT_PAID,                          //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'F9', 1))                  AS RES_F9_TOTAL_AMOUNT_PAID,                                   //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FC', 1))                  AS RES_FC_ACCUMULATED_DEDUCTIBLE_AMOUNT,                       //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FD', 1))                  AS RES_FD_REMAINING_DEDUCTIBLE_AMOUNT,                         //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FE', 1))                  AS RES_FE_REMAINING_BENEFIT_AMOUNT,                            //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FI', 1))                  AS RES_FI_AMOUNT_OF_COPAY,                                     //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FK', 1))                  AS RES_FK_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM,           //RESPONSE PRICING
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'FM', 1))                                  AS RES_FM_BASIS_OF_REIMBURSEMENT_DETERMINATION,                //RESPONSE PRICING
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'J3', '~~~'), '~~~'), x -> TRIM(x)) AS RES_J3_OTHER_AMOUNT_PAID_QUALIFIER, //RESPONSE PRICING
        TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED(RESPONSE, 'J4')), x -> PARSE_NCPDP_CURRENCY(x)) AS RES_J4_OTHER_AMOUNT_PAID,            //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'UM', 1))                  AS RES_UM_AMOUNT_ATTRIBUTED_TO_NON_PREFERRED_SELECTION,        //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'UK', 1))                  AS RES_UK_AMOUNT_ATTRIBUTED_TO_BRAND_DRUG,                     //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'UJ', 1))                  AS RES_UJ_AMOUNT_ATTRIBUTED_TO_PROVIDER_NETWORK_SELECTION,     //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'UC', 1))                  AS RES_UC_SPENDING_ACCOUNT_AMOUNT_REMAINING,                   //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'U9', 1))                  AS RES_U9_DISPENSING_FEE_REIMBURSABLE_AMOUNT,                  //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'U8', 1))                  AS RES_U8_INGREDIENT_COST_REIMBURSABLE_AMOUNT,                 //RESPONSE PRICING
        TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'J2', 1)))                   AS RES_J2_OTHER_AMOUNT_PAID_COUNT,                             //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'NZ', 1))                  AS RES_NZ_AMOUNT_ATTRIBUTED_TO_PROCESSOR_FEE,                  //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'EQ', 1))                  AS RES_EQ_PATIENT_PERCENTAGE_TAX_AMOUNT,                       //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'AZ', 1))                  AS RES_AZ_PERCENTAGE_TAX_BASIS_PAID,                           //RESPONSE PRICING
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, '4V', 1))                                  AS RES_4V_BASIS_OF_CALCULATION_COINSURANCE,                    //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, '4U', 1))                  AS RES_4U_AMOUNT_OF_COINSURANCE,                               //RESPONSE PRICING
        PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'AY', 1))                  AS RES_AY_PERCENTAGE_TAX_RATE_PAID,                            //RESPONSE PRICING

        -- NCPDP SEGMENT (RESPONSE PRIOR AUTHORIZATION SEGMENT)
        TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'PY', 1))                                  AS RES_PY_PRIOR_AUTHORIZATION_ID_ASSIGNED,                     //RESPONSE PRIOR AUTHORIZATION SEGMENT

        -- NCPDP SEGMENT (RESPONSE COORDINATION OF BENEFITS)
       TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'MH', 1))                                   AS RES_MH_OTHER_PAYER_PROCESSOR_CONTROL_NUMBER,                //RESPONSE COORDINATION OF BENEFITS
       TRY_TO_NUMBER(TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'NT', 1)))                    AS RES_NT_OTHER_PAYER_ID_COUNT,                                //RESPONSE COORDINATION OF BENEFITS
       TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, '6C', '~~~'), '~~~'), x -> TRIM(x)) AS RES_6C_OTHER_PAYER_ID_QUALIFIER,     //RESPONSE COORDINATION OF BENEFITS
       TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, '7C', '~~~'), '~~~'), x -> TRIM(x)) AS RES_7C_OTHER_PAYER_ID                //RESPONSE COORDINATION OF BENEFITS

        FROM TRANS_PAIRS
   )
   SELECT CPH_A9_TRANSACTION_COUNT, * FROM CLAIMS;

-- With Fix = 13281


//=====================================================================
// Analysis of Fails by Client
//=====================================================================
SELECT DATA:origin::STRING as origin, COUNT(*) as CNT
FROM SANDBOX.DLOPEZ.TRANSLOG_REPROCESS_EVENTS_3
GROUP BY origin;


SELECT *
FROM SANDBOX.DLOPEZ.TRANSLOG_REPROCESS_EVENTS_3
WHERE SERVICEDATE > '2020-12-31'
 LIMIT 10;


//=====================================================================
// Sample Truly Rejected Events
//=====================================================================
SELECT
    DATA:error::BOOLEAN as ERROR,
    DATA:errorMessage::STRING as ERRORMESSAGE,
    DATA:failed::BOOLEAN as FAILED,
    DATA:failedReason::STRING as FAILEDREASON,
    DATA:origin::STRING as ORIGIN,
    DATA:clientId::STRING as CLIENTID,
    DATA:dataCollectionOnly::BOOLEAN as DATACOLLECTIONONLY,
    *
FROM SANDBOX.DLOPEZ.TRANSLOG_REPROCESS_EVENTS_3;



-- Toms Mysterious Record.
SELECT
    data:transmissionId::STRING AS TRANSMISSION_ID,
    TRY_TO_TIMESTAMP_NTZ(DATA:created::STRING) AS TIME_RECEIVED_AT_SWITCH,
    data:serviceDate::STRING AS serviceDate,
    data:Inge::STRING AS serviceDate,
    data
FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS as t
WHERE TRANSMISSION_ID in ( '1492203583595311104' )
 AND INGESTED_TIMESTAMP > '2025-06-04 04:21:39.457'
  AND data LIKE '%TRANSACTION CANCELLED. RETRY.%'
-- Select only latest the latest Transmission based on Time Received at Switch.  (Latest Ingested Timestamp as tie-breaker)
-- QUALIFY ROW_NUMBER() OVER (PARTITION BY TRANSMISSION_ID ORDER BY TIME_RECEIVED_AT_SWITCH DESC, INGESTED_TIMESTAMP DESC) = 1
-- QUALIFY ROW_NUMBER() OVER (PARTITION BY TRANSMISSION_ID ORDER BY TIME_RECEIVED_AT_SWITCH DESC NULLS LAST, INGESTED_TIMESTAMP DESC NULLS LAST) = 1
LIMIT 5;



SELECT
    data:transmissionId::STRING AS TRANSMISSION_ID,
    TRY_TO_TIMESTAMP_NTZ(DATA:created::STRING) AS TIME_RECEIVED_AT_SWITCH,
    data:serviceDate::STRING AS serviceDate,
    data:Inge::STRING AS serviceDate,
    INGESTED_TIMESTAMP,
    data
FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS as t
WHERE TRANSMISSION_ID in ( '1492203583595311104' )
 AND INGESTED_TIMESTAMP > '2026-03-01'
  AND data LIKE '%TRANSACTION CANCELLED. RETRY.%'
-- Select only latest the latest Transmission based on Time Received at Switch.  (Latest Ingested Timestamp as tie-breaker)
-- QUALIFY ROW_NUMBER() OVER (PARTITION BY TRANSMISSION_ID ORDER BY TIME_RECEIVED_AT_SWITCH DESC, INGESTED_TIMESTAMP DESC) = 1
-- QUALIFY ROW_NUMBER() OVER (PARTITION BY TRANSMISSION_ID ORDER BY TIME_RECEIVED_AT_SWITCH DESC NULLS LAST, INGESTED_TIMESTAMP DESC NULLS LAST) = 1
LIMIT 5;



SELECT * FROM CPE_PROD.DATA.TRANSACTION_LOG ORDER BY TASK_RUN_SCHEDULED_TIME DESC LIMIT 10;




WITH MISSING AS (
    SELECT TRANSMISSION_ID AS TRANSMISSION_ID FROM SANDBOX.DLOPEZ.MISSING_TRANSMISSION_IDS
    UNION ALL
-- Records I have since fixed.
    SELECT CPH_TRANSMISSION_ID  AS TRANSMISSION_ID FROM SANDBOX.DLOPEZ.TRANSACTION_LOG_FIXED_RECORDS
)SELECT * FROM MISSING
WHERE TRANSMISSION_ID = '1492203583595311104';



//=====================================================================
-- Missing Transactions By Ingest Date (For Last 3 Days)
WITH trans AS (
    SELECT data:transmissionId::STRING AS transmissionId
    FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS
    WHERE INGESTED_TIMESTAMP > CURRENT_DATE() - 3
)
SELECT
    DATE(CPH_INGESTED_TIMESTAMP) as ingestDate,
    COUNT(*) as CNT FROM TRANSACTION_LOG
    WHERE CPH_TRANSMISSION_ID NOT IN (SELECT transmissionId FROM trans)
    GROUP BY ingestDate
    ORDER BY ingestDate DESC;



SELECT DISTINCT data:transactionCode::STRING as transactionCode
FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS
WHERE INGESTED_TIMESTAMP > CURRENT_DATE() - 1;


-- This tells me the that transactionCode at the envelope level is not 100% in line with the actual transaction code in the raw data.
WITH WEIRD_TRANSACTIONS AS (
    SELECT
        data:transmissionId::STRING as transmissionId,
        data:origin::STRING as origin,
        data:transactionCode::STRING as transactionCode,
        TRIM(SUBSTR(DATA, 9, 2)) AS raw_transaction_code,
        data
    FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS
    WHERE INGESTED_TIMESTAMP > CURRENT_DATE() - 1
    AND transactionCode IN ('er', '', '}C', '01')
)
SELECT * FROM WEIRD_TRANSACTIONS;

SELECT *
FROM CPE_PROD.DATA.TRANSACTION_LOG
WHERE CPH_CREATED_TIMESTAMP > CURRENT_DATE() -1
AND CPH_TRANSMISSION_ID IN (SELECT transmissionId FROM WEIRD_TRANSACTIONS);


USE WAREHOUSE COMPUTE_WH;
SELECT COUNT(*) FROM CPE_DEV.DATA.STREAM_TRANSACTION_LOG;

--318055373
SELECT COUNT(*) FROM CPE_DEV.DATA.TRANSACTION_LOG WHERE CPH_INGESTED_TIMESTAMP > CURRENT_TIMESTAMP() - INTERVAL '120 MINUTES';



// Research Cacnelled Transactions
USE WAREHOUSE WH_RESEARCH;

// Capture All Cancelled Transactions Since March 1st (When I believe the issue started) for analysis.
CREATE OR REPLACE TABLE SANDBOX.DLOPEZ.TRANSACTION_CANCELLED_RETRY AS
SELECT *
FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS
WHERE INGESTED_TIMESTAMP >  '2026-03-01'
  AND DATA LIKE '%TRANSACTION CANCELLED. RETRY.%';


//====================================================================================================
// RESEARCH: Find Transactions that have been canecled and determine where they exist.
//====================================================================================================

// Get ALL Cancelled Transactions Found.
WITH CANCELLED_TRANS AS (
    SELECT
           TRY_TO_TIMESTAMP_NTZ(DATA:created::STRING) AS TIME_RECEIVED_AT_SWITCH,
           data:transmissionId::STRING                AS TRANSMISSION_ID,
           *,
           '2026-04-27' AS TARGET_DATE
    FROM SANDBOX.DLOPEZ.TRANSACTION_CANCELLED_RETRY
--     WHERE INGESTED_TIMESTAMP BETWEEN DATE(TARGET_DATE) AND DATE(TARGET_DATE) + 1 -- TARGET SUBSET
    ORDER BY INGESTED_TIMESTAMP DESC
)
-- SELECT * FROM CANCELLED_TRANS;

,ALL_TRANS_REALTED_TO_CANCELLED AS (
    SELECT
           ARRAY_SIZE(t.data:transactions::VARIANT) AS TRANSACTION_COUNT,
           TRY_TO_TIMESTAMP_NTZ(t.DATA:created::STRING) AS TIME_RECEIVED_AT_SWITCH,
           t.data:transmissionId::STRING                AS TRANSMISSION_ID,
           t.*,
           s.TARGET_DATE
    FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS t
    INNER JOIN CANCELLED_TRANS s
    ON t.data:transmissionId::STRING = s.TRANSMISSION_ID
    WHERE t.INGESTED_TIMESTAMP BETWEEN DATE(s.TARGET_DATE) AND DATE(s.TARGET_DATE) + 1
)
SELECT * FROM ALL_TRANS_REALTED_TO_CANCELLED
    // OG
--     QUALIFY ROW_NUMBER() OVER (PARTITION BY TRANSMISSION_ID ORDER BY TIME_RECEIVED_AT_SWITCH DESC, INGESTED_TIMESTAMP DESC) = 1;

// TWEAK (Add
      WHERE ARRAY_SIZE(DATA:transactions) > 0
      QUALIFY ROW_NUMBER() OVER (PARTITION BY TRANSMISSION_ID ORDER BY TIME_RECEIVED_AT_SWITCH DESC NULLS LAST, INGESTED_TIMESTAMP DESC NULLS LAST) = 1;

----------------------------------------------------------------------------------------------------
// [NOTE]: The "created" element has different names across transactions.
// REQUESTS -> DATE_TIME_TRANSACTION_PROCESSED
// RESPONSES -> TIME_RECEIVED_AT_SWITCH
// TRANSACTION_LOG - > CPH_CREATED_TIMESTAMP
----------------------------------------------------------------------------------------------------

// CPE CLAIM_REQUESTS
SELECT
    '<!!!SAMPLE!!!>' AS "TABLE_SAMPLE",
    s.*,
    '<!!!CPE_CLAIM_REQUESTS!!!>' AS "TABLE_REQUESTS",
    req.*
FROM ALL_TRANS_REALTED_TO_CANCELLED s
         LEFT JOIN CPE_PROD.DATA.CPE_CLAIM_REQUESTS req
                   ON s.TRANSMISSION_ID = req.TRANSMISSION_ID
WHERE req.DATE_TIME_TRANSACTION_PROCESSED BETWEEN DATE(TARGET_DATE) AND DATE(TARGET_DATE) + 1
  -- This following filter lets you know if the record with actual transactions was selected
--   AND req.CLAIM_RESPONSE IS NOT NULL
ORDER BY s.TRANSMISSION_ID, s.TIME_RECEIVED_AT_SWITCH;


// CPE CLAIM_RESPONSES
-- SELECT
--     '<!!!SAMPLE!!!>' AS "TABLE_SAMPLE",
--     s.*,
--     '<!!!CPE_CLAIM_RESPONSES!!!>' AS "TABLE_RESPONSE",
--     res.*
-- FROM ALL_TRANS_REALTED_TO_CANCELLED s
--          LEFT JOIN CPE_PROD.DATA.CPE_CLAIM_RESPONSES res
--                    ON s.TRANSMISSION_ID = res.TRANSMISSION_ID
-- WHERE res.TIME_RECEIVED_AT_SWITCH BETWEEN DATE(TARGET_DATE) AND DATE(TARGET_DATE) + 1
-- -- This following filter lets you know if the record with actual transactions was selected
-- --   AND res.CLAIM_RESPONSE IS NOT NULL
-- ORDER BY s.TRANSMISSION_ID, s.TIME_RECEIVED_AT_SWITCH;


// TRANSACTION LOG
-- SELECT
--     '<!!!SAMPLE!!!>' AS "TABLE_SAMPLE",
--     s.*,
--     '<!!!TRANSACTION_LOG!!!>' AS "TABLE_TRANSACTION_LOG",
--     log.*
-- FROM ALL_TRANS_REALTED_TO_CANCELLED s
--          LEFT JOIN CPE_PROD.DATA.TRANSACTION_LOG log
--                    ON s.TRANSMISSION_ID = log.CPH_TRANSMISSION_ID
-- WHERE log.CPH_CREATED_TIMESTAMP BETWEEN DATE(TARGET_DATE) AND DATE(TARGET_DATE) + 1
-- -- This following filter lets you know if the record with actual transactions was selected
-- --   AND log.CLAIM_RESPONSE IS NOT NULL
-- ORDER BY s.TRANSMISSION_ID, s.TIME_RECEIVED_AT_SWITCH;

CREATE TEMPORARY TABLE SANDBOX.DLOPEZ.SAMPLE_RECORD AS SELECT * FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS LIMIT 1;


SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY LIMIT 1;



// Task Change History
WITH task_runs AS (
    SELECT
        name AS task_name,
        database_name,
        schema_name,
        scheduled_time,
        query_text,
        query_id,
        -- Detect when query_text changes from the previous run for this task
        CASE
            WHEN query_text = LAG(query_text) OVER (
                PARTITION BY database_name, schema_name, name
                ORDER BY scheduled_time
            )
            THEN 0
            ELSE 1
        END AS is_change
    FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
    WHERE scheduled_time BETWEEN '2026-04-29' AND '2026-04-30'
      AND name = 'STREAM_TASK_TRANSACTION_LOG'
      AND database_name = 'CPE_PROD'
      AND query_text IS NOT NULL
)
, versioned AS (
    SELECT
        task_name,
        database_name,
        schema_name,
        scheduled_time,
        query_text,
        query_id,
        -- Running sum gives each "island" of identical consecutive query_text a unique id
        SUM(is_change) OVER (
            PARTITION BY database_name, schema_name, task_name
            ORDER BY scheduled_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS version_group
    FROM task_runs
)
SELECT
    database_name,
    schema_name,
    task_name,
    version_group,
    MIN(scheduled_time) AS first_scheduled_time,
    MAX(scheduled_time) AS last_scheduled_time,
    COUNT(*) AS run_count,
    ANY_VALUE(query_text) AS query_text
FROM versioned
GROUP BY database_name, schema_name, task_name, version_group
ORDER BY database_name, schema_name, task_name, first_scheduled_time;



// =====================================================
// Get Ingested B1 transactions around a target date.
// =====================================================
USE WAREHOUSE WH_RESEARCH;
SET TARGET_DATE = '2026-04-29 19:03:55.003000000 -04:00';

CREATE OR REPLACE TABLE SANDBOX.DLOPEZ.B1_TRANSACTIONS_TO_INVESTIGATE AS
SELECT * FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS
WHERE INGESTED_TIMESTAMP BETWEEN DATEADD(hour, -2, $TARGET_DATE) AND  DATEADD(hour, 2, $TARGET_DATE)
AND DATA:transactionCode = 'B1';


SELECT COUNT(*) FROM SANDBOX.DLOPEZ.B1_TRANSACTIONS_TO_INVESTIGATE;