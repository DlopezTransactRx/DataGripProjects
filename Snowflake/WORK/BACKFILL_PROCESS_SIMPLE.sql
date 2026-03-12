USE DATABASE CPE_DEV;
USE WAREHOUSE COMPUTE_WH;

-- USE DATABASE CPE_PROD;
-- USE WAREHOUSE WH_RESEARCH;

USE SCHEMA DATA;


--======================================================================================================================================================
--======================================================================================================================================================
-- LOG TABLE (To Help Debugging)
--======================================================================================================================================================
--======================================================================================================================================================
CREATE OR REPLACE TABLE BACKFILL_LOG (
  ts            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  step          STRING,
  detail        STRING
);

--======================================================================================================================================================
--======================================================================================================================================================
-- CONTROL TABLE FOR CLAIMS LOG BACKFILL PROCESS
--======================================================================================================================================================
--======================================================================================================================================================
CREATE OR REPLACE TABLE BACKFILL_CONTROL (
  task_name         STRING PRIMARY KEY,          -- e.g. 'CLAIMSLOG_BACKFILL'
  start_date     DATE NOT NULL,
  end_date       DATE NOT NULL,
  next_date   DATE NOT NULL,               -- next day to process
  state          STRING NOT NULL,             -- READY / RUNNING / DONE / ERROR
  updated_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  last_message   STRING,
  error_message  STRING
);


--======================================================================================================================================================
--======================================================================================================================================================
-- Register Backfill Procedure
--======================================================================================================================================================
--======================================================================================================================================================
CREATE OR REPLACE PROCEDURE REGISTER_BACKFILL(
    P_TASK_NAME STRING,
    P_START_DATE DATE,
    P_END_DATE DATE
)
    RETURNS STRING
    LANGUAGE SQL
    EXECUTE AS OWNER
AS
$$
BEGIN

IF (:P_START_DATE > :P_END_DATE) THEN
    RETURN 'ERROR - Start Date after End Date';
END IF;

MERGE INTO BACKFILL_CONTROL c
    USING (
        SELECT :P_TASK_NAME AS task_name
    ) s
    ON c.task_name = s.task_name
    WHEN MATCHED THEN
        UPDATE SET
            start_date = :P_START_DATE,
            end_date = :P_END_DATE,
            next_date = :P_START_DATE,
            state = 'READY',
            updated_at = CURRENT_TIMESTAMP(),
            last_message = 'Re-Registered'
    WHEN NOT MATCHED THEN
        INSERT (task_name, start_date, end_date, next_date, state, last_message)
            VALUES (:P_TASK_NAME, :P_START_DATE, :P_END_DATE, :P_START_DATE, 'READY', 'Registered');
    RETURN 'Registered Backfill ' || :P_TASK_NAME || ' from ' || TO_VARCHAR(:P_START_DATE) || ' to ' || TO_VARCHAR(:P_END_DATE);
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR - Registered Backfill ' || :P_TASK_NAME || ' from ' || TO_VARCHAR(:P_START_DATE) || ' to ' || TO_VARCHAR(:P_END_DATE);
END;
$$;



--======================================================================================================================================================
--======================================================================================================================================================
-- Execute Backfill Process
--====================================================================================================================================================== --======================================================================================================================================================
CREATE OR REPLACE PROCEDURE EXECUTE_BACKFILL(
    P_TASK_NAME STRING,
    P_PROCEDURE STRING
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  v_start_date   DATE;
  v_end_date     DATE;
  v_next_date DATE;
  v_rows         NUMBER;
BEGIN

--     INSERT INTO BACKFILL_LOG( step, detail) VALUES ('START', 'In EXECUTE_BACKFILL procedure');

    -- Lock-ish behavior: mark RUNNING up front INSERT INTO BACKFILL_LOG( step, detail) VALUES ('Lock The Control Table', 'Setting control to Running.');
    UPDATE BACKFILL_CONTROL
     SET state = 'RUNNING',
         updated_at = CURRENT_TIMESTAMP(),
         error_message = NULL
    WHERE task_name = :P_TASK_NAME
     AND state IN ('READY','RUNNING');

    -- Check
--     INSERT INTO BACKFILL_LOG( step, detail) VALUES ('Claim Log', 'Updated Control Table');
    SELECT start_date, end_date, next_date
        INTO v_start_date, v_end_date, v_next_date
    FROM BACKFILL_CONTROL
        WHERE task_name = :P_TASK_NAME;

    IF (v_next_date IS NULL) THEN
        INSERT INTO BACKFILL_LOG( step, detail) VALUES ('Break Condition', 'No Control Row');
    RETURN 'No control row found.';

    END IF;

    IF (v_next_date > v_end_date) THEN INSERT INTO BACKFILL_LOG( step, detail) VALUES ('Complete', 'BackFill Complete ' || TO_VARCHAR(:P_TASK_NAME));
        UPDATE BACKFILL_CONTROL
           SET state = 'DONE',
               updated_at = CURRENT_TIMESTAMP(),
               last_message = 'Import Complete ' || TO_VARCHAR(:v_end_date)
         WHERE task_name = :P_TASK_NAME;

       //TODO: This should be dynamic based on possible TASK NAME registration in the Backfill Control Table in the future.
        INSERT INTO BACKFILL_LOG( step, detail) VALUES ('Suspend Task', 'Suspending Task ' || TO_VARCHAR(:P_TASK_NAME));
        EXECUTE IMMEDIATE 'ALTER TASK ' || TO_VARCHAR(:P_TASK_NAME) || ' SUSPEND;';

        RETURN 'Import Complete ' || TO_VARCHAR(:v_start_date) || ' to ' || TO_VARCHAR(:v_end_date);
    END IF;

    -----------------------------------------------------------------------
    -- Execute the Backfill Procedure
    -----------------------------------------------------------------------
    INSERT INTO BACKFILL_LOG( step, detail) VALUES ('Executing Procedure', :P_PROCEDURE || '(''' || TO_VARCHAR(:v_next_date) || ''')');
    EXECUTE IMMEDIATE 'CALL ' || :P_PROCEDURE || '(''' || TO_VARCHAR(:v_next_date) || ''')';

--     v_rows := SQLROWCOUNT;
--     INSERT INTO BACKFILL_LOG( step, detail) VALUES ('ROWS', 'ROWS Imported = ' || TO_VARCHAR(:v_rows));

  -----------------------------------------------------------------------
  -- Advance cursor (only after success)
  -----------------------------------------------------------------------
--     INSERT INTO BACKFILL_LOG( step, detail) VALUES ('Advanced Cursor', 'Advancing From ' || TO_VARCHAR(:v_next_date));
    UPDATE BACKFILL_CONTROL
     SET next_date = DATEADD(day, 1, :v_next_date),
         updated_at   = CURRENT_TIMESTAMP(),
         last_message = 'Processed ' || TO_VARCHAR(:v_next_date) || ' rows=' || TO_VARCHAR(:v_rows)
    WHERE task_name = :P_TASK_NAME;
    RETURN 'Processed ' || TO_VARCHAR(:v_next_date) || ' rows=' || TO_VARCHAR(:v_rows);

EXCEPTION
  WHEN OTHER THEN
    INSERT INTO BACKFILL_LOG( step, detail) VALUES ('Exception', 'Error');
    UPDATE BACKFILL_CONTROL
    SET state = 'ERROR',
       updated_at = CURRENT_TIMESTAMP(),
       error_message = 'Failed on ' || TO_VARCHAR(:v_next_date)
    WHERE task_name = :P_TASK_NAME;

    RETURN 'ERROR on ' || TO_VARCHAR(:v_next_date);
END;
$$;

--======================================================================================================================================================
--======================================================================================================================================================
-- Main Backlog Process. (Per Day).  Called by EXECUTE_BACKFILL Procedure
--======================================================================================================================================================
--======================================================================================================================================================
CREATE OR REPLACE PROCEDURE BACKFILL_CLAIMS_LOG(
    P_TARGET_DATE DATE
)
    RETURNS STRING
    LANGUAGE SQL
    EXECUTE AS OWNER
AS
$$
BEGIN

MERGE INTO CPE_CLAIMS_LOG AS TARGET
USING (

   -- Sample Transmission
    WITH SOURCE AS (
      SELECT *,
         DATA:transmissionId::STRING as TRANSMISSION_ID,
         TRY_TO_TIMESTAMP_NTZ(DATA:created::STRING) AS TIME_RECEIVED_AT_SWITCH
      FROM STAGING.STAGE_CPE_TRANSMISSIONS AS T
      WHERE DATE(INGESTED_TIMESTAMP) = :P_TARGET_DATE


      -- Select only latest the latest Transmission based on Time Received at Switch.  (Latest Ingested Timestamp as tie-breaker)
      QUALIFY ROW_NUMBER() OVER (PARTITION BY TRANSMISSION_ID ORDER BY TIME_RECEIVED_AT_SWITCH DESC, INGESTED_TIMESTAMP DESC) = 1
    )

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
           CASE WHEN UPPER(txnObj.value:type::STRING) = 'REQUEST' AND UPPER(txnObj.value:state::STRING) = 'CREATED' THEN ncpdpData.THIS[0] || '' || ncpdpData.VALUE END AS REQUEST,

           -- Response Data
           CASE WHEN UPPER(txnObj.value:type::STRING) = 'RESPONSE' AND UPPER(txnObj.value:state::STRING) = 'RESPONSETOPHARMACY' THEN ncpdpData.THIS[0] || '' || ncpdpData.VALUE END AS RESPONSE

       FROM (SELECT * FROM SOURCE) as t,
            LATERAL FLATTEN(INPUT => t.DATA:transactions) AS txnObj,
            LATERAL FLATTEN(INPUT => SPLIT(txnObj.value:rawData::STRING, '')) AS ncpdpData

       WHERE
         -- Target Request/Response Transactions
           ncpdpData.INDEX > 0
         AND (
           UPPER(txnObj.value:type::STRING) = 'REQUEST' AND UPPER(txnObj.value:state::STRING) = 'CREATED'
               OR
           UPPER(txnObj.value:type::STRING) = 'RESPONSE' AND UPPER(txnObj.value:state::STRING) = 'RESPONSETOPHARMACY'
       )
     )

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
   SELECT * FROM CLAIMS
) as source
ON (target.HASH_KEY = source.HASH_KEY)
WHEN NOT MATCHED THEN
    INSERT (
        HASH_KEY,
        REQ_A1_IIN,
        CPH_TRANSMISSION_ID,
        CPH_ROUTING_ADDRESS,
        CPH_RETURNED_TIMESTAMP,
        CPH_ORIGIN,
        CPH_INGESTED_TIMESTAMP,
        CPH_CREATED_TIMESTAMP,
        CPH_B107_SERVICE_PROVIDER_NCPDP,
        CPH_B101_SERVICE_PROVIDER_NPI,
        CPH_AN_TRANSACTION_RESPONSE_STATUS,
        CPH_A9_TRANSACTION_COUNT,
        CPH_A4_PCN,
        CPH_A3_TRANSACTION_CODE,
        CPH_A2_VERSION,
        CPH_A1_IIN,
        RECORD_ID,
        REQ_A4_PCN,
        REQ_N5_MEDICAID_ID_NUMBER,
        REQ_TZ_GENERIC_EQUIVALENT_PRODUCT_ID_QUALIFIER,
        REQ_UA_GENERIC_EQUIVALENT_PRODUCT_ID,
        REQ_B1_SERVICE_PROVIDER_ID,
        REQ_B2_SERVICE_PROVIDER_ID_QUALIFIER,
        REQ_C1_GROUP_ID,
        REQ_C2_CARDHOLDER_ID,
        REQ_C3_PERSON_CODE,
        REQ_C4_PATIENT_DATE_OF_BIRTH,
        REQ_C5_PATIENT_GENDER_CODE,
        REQ_C6_PATIENT_RELATIONSHIP_CODE,
        REQ_C7_PLACE_OF_SERVICE,
        REQ_C8_OTHER_COVERAGE_CODE,
        REQ_C9_ELIGIBILITY_CLARIFICATION_CODE,
        REQ_CA_PATIENT_FIRST_NAME,
        REQ_CB_PATIENT_LAST_NAME,
        REQ_CC_CARDHOLDER_FIRST_NAME,
        REQ_CD_CARDHOLDER_LAST_NAME,
        REQ_CF_EMPLOYER_NAME,
        REQ_CG_EMPLOYER_STREET_ADDRESS,
        REQ_CH_EMPLOYER_CITY,
        REQ_CI_EMPLOYER_STATE,
        REQ_CJ_EMPLOYER_ZIP,
        REQ_CK_EMPLOYER_TELEPHONE_NUMBER,
        REQ_CM_PATIENT_STREET_ADDRESS,
        REQ_CN_PATIENT_CITY,
        REQ_CO_PATIENT_STATE,
        REQ_CP_PATIENT_ZIP,
        REQ_CQ_PATIENT_TELEPHONE_NUMBER,
        REQ_CR_CARRIER_ID,
        REQ_CX_PATIENT_ID_QUALIFIER,
        REQ_CY_PATIENT_ID,
        REQ_CZ_EMPLOYER_ID,
        REQ_2C_PREGNANCY_INDICATOR,
        REQ_8C_FACILITY_ID,
        REQ_4C_COORDINATION_OF_BENEFITS_COUNT,
        REQ_5C_OTHER_PAYER_COVERAGE_TYPE,
        REQ_6C_OTHER_PAYER_ID_QUALIFIER,
        REQ_7C_OTHER_PAYER_ID,
        REQ_HC_OTHER_PAYER_AMOUNT_PAID_QUALIFIER,
        REQ_HD_DISPENSING_STATUS,
        REQ_HN_PATIENT_EMAIL_ADDRESS,
        REQ_NP_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_QUALIFIER,
        REQ_NQ_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT,
        REQ_NR_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_COUNT,
        REQ_2A_MEDIGAP_ID,
        REQ_2J_PRESCRIBER_FIRST_NAME,
        REQ_2K_PRESCRIBER_STREET_ADDRESS,
        REQ_2M_PRESCRIBER_CITY,
        REQ_2N_PRESCRIBER_STATE,
        REQ_2P_PRESCRIBER_ZIP,
        REQ_4X_PATIENT_RESIDENCE,
        REQ_3Q_PHARMACY_NAME,
        REQ_3U_PHARMACY_STREET_ADDRESS,
        REQ_3V_PHARMACY_STATE,
        REQ_5J_PHARMACY_CITY,
        REQ_6D_PHARMACY_ZIP,
        REQ_BM_NARRATIVE_MESSAGE,
        REQ_D1_DATE_OF_SERVICE,
        REQ_D2_RX_NUMBER,
        REQ_D3_FILL_NUMBER,
        REQ_D5_DAYS_SUPPLY,
        REQ_D6_COMPOUND_CODE,
        REQ_D7_PRODUCT_ID,
        REQ_D703_NDC,
        REQ_D8_DAW_PRODUCT_SELECTION_CODE,
        REQ_D9_INGREDIENT_COST_SUBMITTED,
        REQ_DB_PRESCRIBER_ID,
        REQ_DB01_PRESCRIBER_NPI,
        REQ_DC_DISPENSING_FEE_SUBMITTED,
        REQ_DE_DATE_PRESCRIPTION_WRITTEN,
        REQ_DF_NUMBER_OF_REFILLS_AUTHORIZED,
        REQ_DI_LEVEL_OF_SERVICE,
        REQ_DJ_PRESCRIPTION_ORIGIN_CODE,
        REQ_DK_SUBMISSION_CLARIFICATION_CODE,
        REQ_DL_PRIMARY_CARE_PROVIDER_ID,
        REQ_DN_BASIS_OF_COST_DETERMINATION,
        REQ_DO_DIAGNOSIS_CODE,
        REQ_DQ_USUAL_AND_CUSTOMARY,
        REQ_DR_PRESCRIBER_LAST_NAME,
        REQ_DT_SPECIAL_PACKAGING_INDICATOR,
        REQ_DU_GROSS_AMOUNT_DUE,
        REQ_DV_OTHER_PAYER_AMOUNT_PAID,
        REQ_DX_PATIENT_PAY_AMOUNT_REPORTED,
        REQ_DY_DATE_OF_INJURY,
        REQ_DZ_WORKERS_COMP_CLAIM_ID,
        REQ_E1_PRODUCT_ID_QUALIFIER,
        REQ_E3_INCENTIVE_AMOUNT_SUBMITTED,
        REQ_E4_REASON_FOR_SERVICE_CODE,
        REQ_E5_PROFESSIONAL_SERVICE_CODE,
        REQ_E7_QUANTITY_DISPENSED,
        REQ_EA_ORIGINALLY_PRESCRIBED_PRODUCT_CODE,
        REQ_EB_ORIGINALLY_PRESCRIBED_QUANTITY,
        REQ_EC_COMPOUND_INGREDIENT_COMPONENT_COUNT,
        REQ_ED_COMPOUND_INGREDIENT_QUANTITY,
        REQ_EE_COMPOUND_INGREDIENT_DRUG_COST,
        REQ_EJ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER,
        REQ_EK_SCHEDULED_PRESCRIPTION_ID_NUMBER,
        REQ_EM_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER,
        REQ_EN_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER,
        REQ_EP_ASSOCIATED_PRESCRIPTION_DATE,
        REQ_EU_PRIOR_AUTHORIZATION_TYPE_CODE,
        REQ_EZ_PRESCRIBER_ID_QUALIFIER,
        REQ_2E_PRIMARY_CARE_PROVIDER_ID_QUALIFIER,
        REQ_4E_PRIMARY_CARE_PROVIDER_LAST_NAME,
        REQ_5E_OTHER_PAYER_REJECT_COUNT,
        REQ_6E_OTHER_PAYER_REJECT_CODE,
        REQ_BE_PROFESSIONAL_SERVICE_FEE_SUBMITTED,
        REQ_H8_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER,
        REQ_H9_OTHER_AMOUNT_CLAIMED_SUBMITTED,
        REQ_HA_REGULATORY_FEE_AMOUNT_SUBMITTED,
        REQ_GE_PERCENTAGE_TAX_AMOUNT_SUBMITTED,
        REQ_JE_PERCENTAGE_TAX_BASIS_SUBMITTED,
        REQ_RE_COMPOUND_PRODUCT_ID_QUALIFIER,
        REQ_TE_COMPOUND_PRODUCT_ID,
        REQ_VE_DIAGNOSIS_CODE_COUNT,
        REQ_WE_DIAGNOSIS_CODE_QUALIFIER,
        REQ_PM_PRESCRIBER_TELEPHONE_NUMBER,
        RES_PY_PRIOR_AUTHORIZATION_ID_ASSIGNED,
        REQ_28_UNIT_OF_MEASURE,
        REQ_K5_TRANSACTION_REFERENCE_NUMBER,
        RES_UM_AMOUNT_ATTRIBUTED_TO_NON_PREFERRED_SELECTION,
        RES_UK_AMOUNT_ATTRIBUTED_TO_BRAND_DRUG,
        RES_UJ_AMOUNT_ATTRIBUTED_TO_PROVIDER_NETWORK_SELECTION,
        RES_UH_ADDITIONAL_MESSAGE_INFORMATION_QUALIFIER,
        RES_UG_ADDITIONAL_MESSAGE_INFORMATION_CONTINUITY,
        RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT,
        RES_UC_SPENDING_ACCOUNT_AMOUNT_REMAINING,
        RES_U9_DISPENSING_FEE_REIMBURSABLE_AMOUNT,
        RES_U8_INGREDIENT_COST_REIMBURSABLE_AMOUNT,
        REQ_U7_PHARMACY_SERVICE_TYPE,
        RES_NZ_AMOUNT_ATTRIBUTED_TO_PROCESSOR_FEE,
        RES_J8_PAYER_ID,
        RES_J7_PAYER_ID_QUALIFIER,
        RES_J5_OTHER_PAYER_AMOUNT_RECOGNIZED,
        RES_J4_OTHER_AMOUNT_PAID,
        RES_J3_OTHER_AMOUNT_PAID_QUALIFIER,
        RES_J2_OTHER_AMOUNT_PAID_COUNT,
        RES_J1_PROFESSIONAL_SERVICE_FEE_PAID,
        RES_FQ_ADDITIONAL_MESSAGE_INFORMATION,
        RES_FO_PLAN_ID,
        RES_FM_BASIS_OF_REIMBURSEMENT_DETERMINATION,
        RES_FL_INCENTIVE_AMOUNT_PAID,
        RES_FK_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM,
        RES_FI_AMOUNT_OF_COPAY,
        RES_FH_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE,
        RES_FE_REMAINING_BENEFIT_AMOUNT,
        RES_FD_REMAINING_DEDUCTIBLE_AMOUNT,
        RES_FC_ACCUMULATED_DEDUCTIBLE_AMOUNT,
        RES_FB_REJECT_CODE,
        RES_FA_REJECT_COUNT,
        RES_F9_TOTAL_AMOUNT_PAID,
        RES_F7_DISPENSING_FEE_PAID,
        RES_F6_INGREDIENT_COST_PAID,
        RES_F5_PATIENT_PAY_AMOUNT,
        RES_F4_MESSAGE,
        RES_F3_AUTHORIZATION_NUMBER,
        RES_EQ_PATIENT_PERCENTAGE_TAX_AMOUNT,
        RES_C1_GROUP_ID,
        RES_AZ_PERCENTAGE_TAX_BASIS_PAID,
        RES_AY_PERCENTAGE_TAX_RATE_PAID,
        RES_AX_PERCENTAGE_TAX_AMOUNT_PAID,
        RES_AW_REGULATORY_FEE_AMOUNT_PAID,
        RES_AV_PERCENTAGE_TAX_EXEMPT_INDICATOR,
        RES_AN_TRANSACTION_RESPONSE_STATUS,
        REQ_AK_SOFTWARE_VENDOR_ID,
        RES_5F_APPROVED_MESSAGE_COUNT,
        RES_6F_APPROVED_MESSAGE_CODE,
        RES_4V_BASIS_OF_CALCULATION_COINSURANCE,
        RES_4U_AMOUNT_OF_COINSURANCE,
        RES_2F_NETWORK_REIMBURSEMENT_ID,
        REQ_FO_PLAN_ID,
        RES_MH_OTHER_PAYER_PROCESSOR_CONTROL_NUMBER,
        RES_NT_OTHER_PAYER_ID_COUNT,
        RES_6C_OTHER_PAYER_ID_QUALIFIER,
        RES_7C_OTHER_PAYER_ID
    )
    VALUES (
       source.HASH_KEY,
       source.REQ_A1_IIN,
       source.CPH_TRANSMISSION_ID,
       source.CPH_ROUTING_ADDRESS,
       source.CPH_RETURNED_TIMESTAMP,
       source.CPH_ORIGIN,
       source.CPH_INGESTED_TIMESTAMP,
       source.CPH_CREATED_TIMESTAMP,
       source.CPH_B107_SERVICE_PROVIDER_NCPDP,
       source.CPH_B101_SERVICE_PROVIDER_NPI,
       source.CPH_AN_TRANSACTION_RESPONSE_STATUS,
       source.CPH_A9_TRANSACTION_COUNT,
       source.CPH_A4_PCN,
       source.CPH_A3_TRANSACTION_CODE,
       source.CPH_A2_VERSION,
       source.CPH_A1_IIN,
       source.RECORD_ID,
       source.REQ_A4_PCN,
       source.REQ_N5_MEDICAID_ID_NUMBER,
       source.REQ_TZ_GENERIC_EQUIVALENT_PRODUCT_ID_QUALIFIER,
       source.REQ_UA_GENERIC_EQUIVALENT_PRODUCT_ID,
       source.REQ_B1_SERVICE_PROVIDER_ID,
       source.REQ_B2_SERVICE_PROVIDER_ID_QUALIFIER,
       source.REQ_C1_GROUP_ID,
       source.REQ_C2_CARDHOLDER_ID,
       source.REQ_C3_PERSON_CODE,
       source.REQ_C4_PATIENT_DATE_OF_BIRTH,
       source.REQ_C5_PATIENT_GENDER_CODE,
       source.REQ_C6_PATIENT_RELATIONSHIP_CODE,
       source.REQ_C7_PLACE_OF_SERVICE,
       source.REQ_C8_OTHER_COVERAGE_CODE,
       source.REQ_C9_ELIGIBILITY_CLARIFICATION_CODE,
       source.REQ_CA_PATIENT_FIRST_NAME,
       source.REQ_CB_PATIENT_LAST_NAME,
       source.REQ_CC_CARDHOLDER_FIRST_NAME,
       source.REQ_CD_CARDHOLDER_LAST_NAME,
       source.REQ_CF_EMPLOYER_NAME,
       source.REQ_CG_EMPLOYER_STREET_ADDRESS,
       source.REQ_CH_EMPLOYER_CITY,
       source.REQ_CI_EMPLOYER_STATE,
       source.REQ_CJ_EMPLOYER_ZIP,
       source.REQ_CK_EMPLOYER_TELEPHONE_NUMBER,
       source.REQ_CM_PATIENT_STREET_ADDRESS,
       source.REQ_CN_PATIENT_CITY,
       source.REQ_CO_PATIENT_STATE,
       source.REQ_CP_PATIENT_ZIP,
       source.REQ_CQ_PATIENT_TELEPHONE_NUMBER,
       source.REQ_CR_CARRIER_ID,
       source.REQ_CX_PATIENT_ID_QUALIFIER,
       source.REQ_CY_PATIENT_ID,
       source.REQ_CZ_EMPLOYER_ID,
       source.REQ_2C_PREGNANCY_INDICATOR,
       source.REQ_8C_FACILITY_ID,
       source.REQ_4C_COORDINATION_OF_BENEFITS_COUNT,
       source.REQ_5C_OTHER_PAYER_COVERAGE_TYPE,
       source.REQ_6C_OTHER_PAYER_ID_QUALIFIER,
       source.REQ_7C_OTHER_PAYER_ID,
       source.REQ_HC_OTHER_PAYER_AMOUNT_PAID_QUALIFIER,
       source.REQ_HD_DISPENSING_STATUS,
       source.REQ_HN_PATIENT_EMAIL_ADDRESS,
       source.REQ_NP_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_QUALIFIER,
       source.REQ_NQ_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT,
       source.REQ_NR_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_COUNT,
       source.REQ_2A_MEDIGAP_ID,
       source.REQ_2J_PRESCRIBER_FIRST_NAME,
       source.REQ_2K_PRESCRIBER_STREET_ADDRESS,
       source.REQ_2M_PRESCRIBER_CITY,
       source.REQ_2N_PRESCRIBER_STATE,
       source.REQ_2P_PRESCRIBER_ZIP,
       source.REQ_4X_PATIENT_RESIDENCE,
       source.REQ_3Q_PHARMACY_NAME,
       source.REQ_3U_PHARMACY_STREET_ADDRESS,
       source.REQ_3V_PHARMACY_STATE,
       source.REQ_5J_PHARMACY_CITY,
       source.REQ_6D_PHARMACY_ZIP,
       source.REQ_BM_NARRATIVE_MESSAGE,
       source.REQ_D1_DATE_OF_SERVICE,
       source.REQ_D2_RX_NUMBER,
       source.REQ_D3_FILL_NUMBER,
       source.REQ_D5_DAYS_SUPPLY,
       source.REQ_D6_COMPOUND_CODE,
       source.REQ_D7_PRODUCT_ID,
       source.REQ_D703_NDC,
       source.REQ_D8_DAW_PRODUCT_SELECTION_CODE,
       source.REQ_D9_INGREDIENT_COST_SUBMITTED,
       source.REQ_DB_PRESCRIBER_ID,
       source.REQ_DB01_PRESCRIBER_NPI,
       source.REQ_DC_DISPENSING_FEE_SUBMITTED,
       source.REQ_DE_DATE_PRESCRIPTION_WRITTEN,
       source.REQ_DF_NUMBER_OF_REFILLS_AUTHORIZED,
       source.REQ_DI_LEVEL_OF_SERVICE,
       source.REQ_DJ_PRESCRIPTION_ORIGIN_CODE,
       source.REQ_DK_SUBMISSION_CLARIFICATION_CODE,
       source.REQ_DL_PRIMARY_CARE_PROVIDER_ID,
       source.REQ_DN_BASIS_OF_COST_DETERMINATION,
       source.REQ_DO_DIAGNOSIS_CODE,
       source.REQ_DQ_USUAL_AND_CUSTOMARY,
       source.REQ_DR_PRESCRIBER_LAST_NAME,
       source.REQ_DT_SPECIAL_PACKAGING_INDICATOR,
       source.REQ_DU_GROSS_AMOUNT_DUE,
       source.REQ_DV_OTHER_PAYER_AMOUNT_PAID,
       source.REQ_DX_PATIENT_PAY_AMOUNT_REPORTED,
       source.REQ_DY_DATE_OF_INJURY,
       source.REQ_DZ_WORKERS_COMP_CLAIM_ID,
       source.REQ_E1_PRODUCT_ID_QUALIFIER,
       source.REQ_E3_INCENTIVE_AMOUNT_SUBMITTED,
       source.REQ_E4_REASON_FOR_SERVICE_CODE,
       source.REQ_E5_PROFESSIONAL_SERVICE_CODE,
       source.REQ_E7_QUANTITY_DISPENSED,
       source.REQ_EA_ORIGINALLY_PRESCRIBED_PRODUCT_CODE,
       source.REQ_EB_ORIGINALLY_PRESCRIBED_QUANTITY,
       source.REQ_EC_COMPOUND_INGREDIENT_COMPONENT_COUNT,
       source.REQ_ED_COMPOUND_INGREDIENT_QUANTITY,
       source.REQ_EE_COMPOUND_INGREDIENT_DRUG_COST,
       source.REQ_EJ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER,
       source.REQ_EK_SCHEDULED_PRESCRIPTION_ID_NUMBER,
       source.REQ_EM_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER,
       source.REQ_EN_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER,
       source.REQ_EP_ASSOCIATED_PRESCRIPTION_DATE,
       source.REQ_EU_PRIOR_AUTHORIZATION_TYPE_CODE,
       source.REQ_EZ_PRESCRIBER_ID_QUALIFIER,
       source.REQ_2E_PRIMARY_CARE_PROVIDER_ID_QUALIFIER,
       source.REQ_4E_PRIMARY_CARE_PROVIDER_LAST_NAME,
       source.REQ_5E_OTHER_PAYER_REJECT_COUNT,
       source.REQ_6E_OTHER_PAYER_REJECT_CODE,
       source.REQ_BE_PROFESSIONAL_SERVICE_FEE_SUBMITTED,
       source.REQ_H8_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER,
       source.REQ_H9_OTHER_AMOUNT_CLAIMED_SUBMITTED,
       source.REQ_HA_REGULATORY_FEE_AMOUNT_SUBMITTED,
       source.REQ_GE_PERCENTAGE_TAX_AMOUNT_SUBMITTED,
       source.REQ_JE_PERCENTAGE_TAX_BASIS_SUBMITTED,
       source.REQ_RE_COMPOUND_PRODUCT_ID_QUALIFIER,
       source.REQ_TE_COMPOUND_PRODUCT_ID,
       source.REQ_VE_DIAGNOSIS_CODE_COUNT,
       source.REQ_WE_DIAGNOSIS_CODE_QUALIFIER,
       source.REQ_PM_PRESCRIBER_TELEPHONE_NUMBER,
       source.RES_PY_PRIOR_AUTHORIZATION_ID_ASSIGNED,
       source.REQ_28_UNIT_OF_MEASURE,
       source.REQ_K5_TRANSACTION_REFERENCE_NUMBER,
       source.RES_UM_AMOUNT_ATTRIBUTED_TO_NON_PREFERRED_SELECTION,
       source.RES_UK_AMOUNT_ATTRIBUTED_TO_BRAND_DRUG,
       source.RES_UJ_AMOUNT_ATTRIBUTED_TO_PROVIDER_NETWORK_SELECTION,
       source.RES_UH_ADDITIONAL_MESSAGE_INFORMATION_QUALIFIER,
       source.RES_UG_ADDITIONAL_MESSAGE_INFORMATION_CONTINUITY,
       source.RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT,
       source.RES_UC_SPENDING_ACCOUNT_AMOUNT_REMAINING,
       source.RES_U9_DISPENSING_FEE_REIMBURSABLE_AMOUNT,
       source.RES_U8_INGREDIENT_COST_REIMBURSABLE_AMOUNT,
       source.REQ_U7_PHARMACY_SERVICE_TYPE,
       source.RES_NZ_AMOUNT_ATTRIBUTED_TO_PROCESSOR_FEE,
       source.RES_J8_PAYER_ID,
       source.RES_J7_PAYER_ID_QUALIFIER,
       source.RES_J5_OTHER_PAYER_AMOUNT_RECOGNIZED,
       source.RES_J4_OTHER_AMOUNT_PAID,
       source.RES_J3_OTHER_AMOUNT_PAID_QUALIFIER,
       source.RES_J2_OTHER_AMOUNT_PAID_COUNT,
       source.RES_J1_PROFESSIONAL_SERVICE_FEE_PAID,
       source.RES_FQ_ADDITIONAL_MESSAGE_INFORMATION,
       source.RES_FO_PLAN_ID,
       source.RES_FM_BASIS_OF_REIMBURSEMENT_DETERMINATION,
       source.RES_FL_INCENTIVE_AMOUNT_PAID,
       source.RES_FK_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM,
       source.RES_FI_AMOUNT_OF_COPAY,
       source.RES_FH_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE,
       source.RES_FE_REMAINING_BENEFIT_AMOUNT,
       source.RES_FD_REMAINING_DEDUCTIBLE_AMOUNT,
       source.RES_FC_ACCUMULATED_DEDUCTIBLE_AMOUNT,
       source.RES_FB_REJECT_CODE,
       source.RES_FA_REJECT_COUNT,
       source.RES_F9_TOTAL_AMOUNT_PAID,
       source.RES_F7_DISPENSING_FEE_PAID,
       source.RES_F6_INGREDIENT_COST_PAID,
       source.RES_F5_PATIENT_PAY_AMOUNT,
       source.RES_F4_MESSAGE,
       source.RES_F3_AUTHORIZATION_NUMBER,
       source.RES_EQ_PATIENT_PERCENTAGE_TAX_AMOUNT,
       source.RES_C1_GROUP_ID,
       source.RES_AZ_PERCENTAGE_TAX_BASIS_PAID,
       source.RES_AY_PERCENTAGE_TAX_RATE_PAID,
       source.RES_AX_PERCENTAGE_TAX_AMOUNT_PAID,
       source.RES_AW_REGULATORY_FEE_AMOUNT_PAID,
       source.RES_AV_PERCENTAGE_TAX_EXEMPT_INDICATOR,
       source.RES_AN_TRANSACTION_RESPONSE_STATUS,
       source.REQ_AK_SOFTWARE_VENDOR_ID,
       source.RES_5F_APPROVED_MESSAGE_COUNT,
       source.RES_6F_APPROVED_MESSAGE_CODE,
       source.RES_4V_BASIS_OF_CALCULATION_COINSURANCE,
       source.RES_4U_AMOUNT_OF_COINSURANCE,
       source.RES_2F_NETWORK_REIMBURSEMENT_ID,
       source.REQ_FO_PLAN_ID,
       source.RES_MH_OTHER_PAYER_PROCESSOR_CONTROL_NUMBER,
       source.RES_NT_OTHER_PAYER_ID_COUNT,
       source.RES_6C_OTHER_PAYER_ID_QUALIFIER,
       source.RES_7C_OTHER_PAYER_ID
)

-- !!! NOTE: THIS IS EXCLUSIVELY FOR BACK FILLING PURPOSES. !!!
WHEN MATCHED THEN
    UPDATE SET
        target.HASH_KEY = source.HASH_KEY,
        target.REQ_A1_IIN = source.REQ_A1_IIN,
        target.CPH_TRANSMISSION_ID = source.CPH_TRANSMISSION_ID,
        target.CPH_ROUTING_ADDRESS = source.CPH_ROUTING_ADDRESS,
        target.CPH_RETURNED_TIMESTAMP = source.CPH_RETURNED_TIMESTAMP,
        target.CPH_ORIGIN = source.CPH_ORIGIN,
        target.CPH_INGESTED_TIMESTAMP = source.CPH_INGESTED_TIMESTAMP,
        target.CPH_CREATED_TIMESTAMP = source.CPH_CREATED_TIMESTAMP,
        target.CPH_B107_SERVICE_PROVIDER_NCPDP = source.CPH_B107_SERVICE_PROVIDER_NCPDP,
        target.CPH_B101_SERVICE_PROVIDER_NPI = source.CPH_B101_SERVICE_PROVIDER_NPI,
        target.CPH_AN_TRANSACTION_RESPONSE_STATUS = source.CPH_AN_TRANSACTION_RESPONSE_STATUS,
        target.CPH_A9_TRANSACTION_COUNT = source.CPH_A9_TRANSACTION_COUNT,
        target.CPH_A4_PCN = source.CPH_A4_PCN,
        target.CPH_A3_TRANSACTION_CODE = source.CPH_A3_TRANSACTION_CODE,
        target.CPH_A2_VERSION = source.CPH_A2_VERSION,
        target.CPH_A1_IIN = source.CPH_A1_IIN,
        target.RECORD_ID = source.RECORD_ID,
        target.REQ_A4_PCN = source.REQ_A4_PCN,
        target.REQ_N5_MEDICAID_ID_NUMBER = source.REQ_N5_MEDICAID_ID_NUMBER,
        target.REQ_TZ_GENERIC_EQUIVALENT_PRODUCT_ID_QUALIFIER = source.REQ_TZ_GENERIC_EQUIVALENT_PRODUCT_ID_QUALIFIER,
        target.REQ_UA_GENERIC_EQUIVALENT_PRODUCT_ID = source.REQ_UA_GENERIC_EQUIVALENT_PRODUCT_ID,
        target.REQ_B1_SERVICE_PROVIDER_ID = source.REQ_B1_SERVICE_PROVIDER_ID,
        target.REQ_B2_SERVICE_PROVIDER_ID_QUALIFIER = source.REQ_B2_SERVICE_PROVIDER_ID_QUALIFIER,
        target.REQ_C1_GROUP_ID = source.REQ_C1_GROUP_ID,
        target.REQ_C2_CARDHOLDER_ID = source.REQ_C2_CARDHOLDER_ID,
        target.REQ_C3_PERSON_CODE = source.REQ_C3_PERSON_CODE,
        target.REQ_C4_PATIENT_DATE_OF_BIRTH = source.REQ_C4_PATIENT_DATE_OF_BIRTH,
        target.REQ_C5_PATIENT_GENDER_CODE = source.REQ_C5_PATIENT_GENDER_CODE,
        target.REQ_C6_PATIENT_RELATIONSHIP_CODE = source.REQ_C6_PATIENT_RELATIONSHIP_CODE,
        target.REQ_C7_PLACE_OF_SERVICE = source.REQ_C7_PLACE_OF_SERVICE,
        target.REQ_C8_OTHER_COVERAGE_CODE = source.REQ_C8_OTHER_COVERAGE_CODE,
        target.REQ_C9_ELIGIBILITY_CLARIFICATION_CODE = source.REQ_C9_ELIGIBILITY_CLARIFICATION_CODE,
        target.REQ_CA_PATIENT_FIRST_NAME = source.REQ_CA_PATIENT_FIRST_NAME,
        target.REQ_CB_PATIENT_LAST_NAME = source.REQ_CB_PATIENT_LAST_NAME,
        target.REQ_CC_CARDHOLDER_FIRST_NAME = source.REQ_CC_CARDHOLDER_FIRST_NAME,
        target.REQ_CD_CARDHOLDER_LAST_NAME = source.REQ_CD_CARDHOLDER_LAST_NAME,
        target.REQ_CF_EMPLOYER_NAME = source.REQ_CF_EMPLOYER_NAME,
        target.REQ_CG_EMPLOYER_STREET_ADDRESS = source.REQ_CG_EMPLOYER_STREET_ADDRESS,
        target.REQ_CH_EMPLOYER_CITY = source.REQ_CH_EMPLOYER_CITY,
        target.REQ_CI_EMPLOYER_STATE = source.REQ_CI_EMPLOYER_STATE,
        target.REQ_CJ_EMPLOYER_ZIP = source.REQ_CJ_EMPLOYER_ZIP,
        target.REQ_CK_EMPLOYER_TELEPHONE_NUMBER = source.REQ_CK_EMPLOYER_TELEPHONE_NUMBER,
        target.REQ_CM_PATIENT_STREET_ADDRESS = source.REQ_CM_PATIENT_STREET_ADDRESS,
        target.REQ_CN_PATIENT_CITY = source.REQ_CN_PATIENT_CITY,
        target.REQ_CO_PATIENT_STATE = source.REQ_CO_PATIENT_STATE,
        target.REQ_CP_PATIENT_ZIP = source.REQ_CP_PATIENT_ZIP,
        target.REQ_CQ_PATIENT_TELEPHONE_NUMBER = source.REQ_CQ_PATIENT_TELEPHONE_NUMBER,
        target.REQ_CR_CARRIER_ID = source.REQ_CR_CARRIER_ID,
        target.REQ_CX_PATIENT_ID_QUALIFIER = source.REQ_CX_PATIENT_ID_QUALIFIER,
        target.REQ_CY_PATIENT_ID = source.REQ_CY_PATIENT_ID,
        target.REQ_CZ_EMPLOYER_ID = source.REQ_CZ_EMPLOYER_ID,
        target.REQ_2C_PREGNANCY_INDICATOR = source.REQ_2C_PREGNANCY_INDICATOR,
        target.REQ_8C_FACILITY_ID = source.REQ_8C_FACILITY_ID,
        target.REQ_4C_COORDINATION_OF_BENEFITS_COUNT = source.REQ_4C_COORDINATION_OF_BENEFITS_COUNT,
        target.REQ_5C_OTHER_PAYER_COVERAGE_TYPE = source.REQ_5C_OTHER_PAYER_COVERAGE_TYPE,
        target.REQ_6C_OTHER_PAYER_ID_QUALIFIER = source.REQ_6C_OTHER_PAYER_ID_QUALIFIER,
        target.REQ_7C_OTHER_PAYER_ID = source.REQ_7C_OTHER_PAYER_ID,
        target.REQ_HC_OTHER_PAYER_AMOUNT_PAID_QUALIFIER = source.REQ_HC_OTHER_PAYER_AMOUNT_PAID_QUALIFIER,
        target.REQ_HD_DISPENSING_STATUS = source.REQ_HD_DISPENSING_STATUS,
        target.REQ_HN_PATIENT_EMAIL_ADDRESS = source.REQ_HN_PATIENT_EMAIL_ADDRESS,
        target.REQ_NP_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_QUALIFIER = source.REQ_NP_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_QUALIFIER,
        target.REQ_NQ_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT = source.REQ_NQ_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT,
        target.REQ_NR_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_COUNT = source.REQ_NR_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_COUNT,
        target.REQ_2A_MEDIGAP_ID = source.REQ_2A_MEDIGAP_ID,
        target.REQ_2J_PRESCRIBER_FIRST_NAME = source.REQ_2J_PRESCRIBER_FIRST_NAME,
        target.REQ_2K_PRESCRIBER_STREET_ADDRESS = source.REQ_2K_PRESCRIBER_STREET_ADDRESS,
        target.REQ_2M_PRESCRIBER_CITY = source.REQ_2M_PRESCRIBER_CITY,
        target.REQ_2N_PRESCRIBER_STATE = source.REQ_2N_PRESCRIBER_STATE,
        target.REQ_2P_PRESCRIBER_ZIP = source.REQ_2P_PRESCRIBER_ZIP,
        target.REQ_4X_PATIENT_RESIDENCE = source.REQ_4X_PATIENT_RESIDENCE,
        target.REQ_3Q_PHARMACY_NAME = source.REQ_3Q_PHARMACY_NAME,
        target.REQ_3U_PHARMACY_STREET_ADDRESS = source.REQ_3U_PHARMACY_STREET_ADDRESS,
        target.REQ_3V_PHARMACY_STATE = source.REQ_3V_PHARMACY_STATE,
        target.REQ_5J_PHARMACY_CITY = source.REQ_5J_PHARMACY_CITY,
        target.REQ_6D_PHARMACY_ZIP = source.REQ_6D_PHARMACY_ZIP,
        target.REQ_BM_NARRATIVE_MESSAGE = source.REQ_BM_NARRATIVE_MESSAGE,
        target.REQ_D1_DATE_OF_SERVICE = source.REQ_D1_DATE_OF_SERVICE,
        target.REQ_D2_RX_NUMBER = source.REQ_D2_RX_NUMBER,
        target.REQ_D3_FILL_NUMBER = source.REQ_D3_FILL_NUMBER,
        target.REQ_D5_DAYS_SUPPLY = source.REQ_D5_DAYS_SUPPLY,
        target.REQ_D6_COMPOUND_CODE = source.REQ_D6_COMPOUND_CODE,
        target.REQ_D7_PRODUCT_ID = source.REQ_D7_PRODUCT_ID,
        target.REQ_D703_NDC = source.REQ_D703_NDC,
        target.REQ_D8_DAW_PRODUCT_SELECTION_CODE = source.REQ_D8_DAW_PRODUCT_SELECTION_CODE,
        target.REQ_D9_INGREDIENT_COST_SUBMITTED = source.REQ_D9_INGREDIENT_COST_SUBMITTED,
        target.REQ_DB_PRESCRIBER_ID = source.REQ_DB_PRESCRIBER_ID,
        target.REQ_DB01_PRESCRIBER_NPI = source.REQ_DB01_PRESCRIBER_NPI,
        target.REQ_DC_DISPENSING_FEE_SUBMITTED = source.REQ_DC_DISPENSING_FEE_SUBMITTED,
        target.REQ_DE_DATE_PRESCRIPTION_WRITTEN = source.REQ_DE_DATE_PRESCRIPTION_WRITTEN,
        target.REQ_DF_NUMBER_OF_REFILLS_AUTHORIZED = source.REQ_DF_NUMBER_OF_REFILLS_AUTHORIZED,
        target.REQ_DI_LEVEL_OF_SERVICE = source.REQ_DI_LEVEL_OF_SERVICE,
        target.REQ_DJ_PRESCRIPTION_ORIGIN_CODE = source.REQ_DJ_PRESCRIPTION_ORIGIN_CODE,
        target.REQ_DK_SUBMISSION_CLARIFICATION_CODE = source.REQ_DK_SUBMISSION_CLARIFICATION_CODE,
        target.REQ_DL_PRIMARY_CARE_PROVIDER_ID = source.REQ_DL_PRIMARY_CARE_PROVIDER_ID,
        target.REQ_DN_BASIS_OF_COST_DETERMINATION = source.REQ_DN_BASIS_OF_COST_DETERMINATION,
        target.REQ_DO_DIAGNOSIS_CODE = source.REQ_DO_DIAGNOSIS_CODE,
        target.REQ_DQ_USUAL_AND_CUSTOMARY = source.REQ_DQ_USUAL_AND_CUSTOMARY,
        target.REQ_DR_PRESCRIBER_LAST_NAME = source.REQ_DR_PRESCRIBER_LAST_NAME,
        target.REQ_DT_SPECIAL_PACKAGING_INDICATOR = source.REQ_DT_SPECIAL_PACKAGING_INDICATOR,
        target.REQ_DU_GROSS_AMOUNT_DUE = source.REQ_DU_GROSS_AMOUNT_DUE,
        target.REQ_DV_OTHER_PAYER_AMOUNT_PAID = source.REQ_DV_OTHER_PAYER_AMOUNT_PAID,
        target.REQ_DX_PATIENT_PAY_AMOUNT_REPORTED = source.REQ_DX_PATIENT_PAY_AMOUNT_REPORTED,
        target.REQ_DY_DATE_OF_INJURY = source.REQ_DY_DATE_OF_INJURY,
        target.REQ_DZ_WORKERS_COMP_CLAIM_ID = source.REQ_DZ_WORKERS_COMP_CLAIM_ID,
        target.REQ_E1_PRODUCT_ID_QUALIFIER = source.REQ_E1_PRODUCT_ID_QUALIFIER,
        target.REQ_E3_INCENTIVE_AMOUNT_SUBMITTED = source.REQ_E3_INCENTIVE_AMOUNT_SUBMITTED,
        target.REQ_E4_REASON_FOR_SERVICE_CODE = source.REQ_E4_REASON_FOR_SERVICE_CODE,
        target.REQ_E5_PROFESSIONAL_SERVICE_CODE = source.REQ_E5_PROFESSIONAL_SERVICE_CODE,
        target.REQ_E7_QUANTITY_DISPENSED = source.REQ_E7_QUANTITY_DISPENSED,
        target.REQ_EA_ORIGINALLY_PRESCRIBED_PRODUCT_CODE = source.REQ_EA_ORIGINALLY_PRESCRIBED_PRODUCT_CODE,
        target.REQ_EC_COMPOUND_INGREDIENT_COMPONENT_COUNT = source.REQ_EC_COMPOUND_INGREDIENT_COMPONENT_COUNT,
        target.REQ_ED_COMPOUND_INGREDIENT_QUANTITY = source.REQ_ED_COMPOUND_INGREDIENT_QUANTITY,
        target.REQ_EE_COMPOUND_INGREDIENT_DRUG_COST = source.REQ_EE_COMPOUND_INGREDIENT_DRUG_COST,
        target.REQ_EJ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER = source.REQ_EJ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER,
        target.REQ_EK_SCHEDULED_PRESCRIPTION_ID_NUMBER = source.REQ_EK_SCHEDULED_PRESCRIPTION_ID_NUMBER,
        target.REQ_EM_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER = source.REQ_EM_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER,
        target.REQ_EN_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER = source.REQ_EN_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER,
        target.REQ_EP_ASSOCIATED_PRESCRIPTION_DATE = source.REQ_EP_ASSOCIATED_PRESCRIPTION_DATE,
        target.REQ_EU_PRIOR_AUTHORIZATION_TYPE_CODE = source.REQ_EU_PRIOR_AUTHORIZATION_TYPE_CODE,
        target.REQ_EZ_PRESCRIBER_ID_QUALIFIER = source.REQ_EZ_PRESCRIBER_ID_QUALIFIER,
        target.REQ_2E_PRIMARY_CARE_PROVIDER_ID_QUALIFIER = source.REQ_2E_PRIMARY_CARE_PROVIDER_ID_QUALIFIER,
        target.REQ_4E_PRIMARY_CARE_PROVIDER_LAST_NAME = source.REQ_4E_PRIMARY_CARE_PROVIDER_LAST_NAME,
        target.REQ_5E_OTHER_PAYER_REJECT_COUNT = source.REQ_5E_OTHER_PAYER_REJECT_COUNT,
        target.REQ_6E_OTHER_PAYER_REJECT_CODE = source.REQ_6E_OTHER_PAYER_REJECT_CODE,
        target.REQ_BE_PROFESSIONAL_SERVICE_FEE_SUBMITTED = source.REQ_BE_PROFESSIONAL_SERVICE_FEE_SUBMITTED,
        target.REQ_H8_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER = source.REQ_H8_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER,
        target.REQ_H9_OTHER_AMOUNT_CLAIMED_SUBMITTED = source.REQ_H9_OTHER_AMOUNT_CLAIMED_SUBMITTED,
        target.REQ_HA_REGULATORY_FEE_AMOUNT_SUBMITTED = source.REQ_HA_REGULATORY_FEE_AMOUNT_SUBMITTED,
        target.REQ_GE_PERCENTAGE_TAX_AMOUNT_SUBMITTED = source.REQ_GE_PERCENTAGE_TAX_AMOUNT_SUBMITTED,
        target.REQ_JE_PERCENTAGE_TAX_BASIS_SUBMITTED = source.REQ_JE_PERCENTAGE_TAX_BASIS_SUBMITTED,
        target.REQ_RE_COMPOUND_PRODUCT_ID_QUALIFIER = source.REQ_RE_COMPOUND_PRODUCT_ID_QUALIFIER,
        target.REQ_TE_COMPOUND_PRODUCT_ID = source.REQ_TE_COMPOUND_PRODUCT_ID,
        target.REQ_VE_DIAGNOSIS_CODE_COUNT = source.REQ_VE_DIAGNOSIS_CODE_COUNT,
        target.REQ_WE_DIAGNOSIS_CODE_QUALIFIER = source.REQ_WE_DIAGNOSIS_CODE_QUALIFIER,
        target.REQ_PM_PRESCRIBER_TELEPHONE_NUMBER = source.REQ_PM_PRESCRIBER_TELEPHONE_NUMBER,
        target.RES_PY_PRIOR_AUTHORIZATION_ID_ASSIGNED = source.RES_PY_PRIOR_AUTHORIZATION_ID_ASSIGNED,
        target.REQ_28_UNIT_OF_MEASURE = source.REQ_28_UNIT_OF_MEASURE,
        target.REQ_K5_TRANSACTION_REFERENCE_NUMBER = source.REQ_K5_TRANSACTION_REFERENCE_NUMBER,
        target.RES_UM_AMOUNT_ATTRIBUTED_TO_NON_PREFERRED_SELECTION = source.RES_UM_AMOUNT_ATTRIBUTED_TO_NON_PREFERRED_SELECTION,
        target.RES_UK_AMOUNT_ATTRIBUTED_TO_BRAND_DRUG = source.RES_UK_AMOUNT_ATTRIBUTED_TO_BRAND_DRUG,
        target.RES_UJ_AMOUNT_ATTRIBUTED_TO_PROVIDER_NETWORK_SELECTION = source.RES_UJ_AMOUNT_ATTRIBUTED_TO_PROVIDER_NETWORK_SELECTION,
        target.RES_UH_ADDITIONAL_MESSAGE_INFORMATION_QUALIFIER = source.RES_UH_ADDITIONAL_MESSAGE_INFORMATION_QUALIFIER,
        target.RES_UG_ADDITIONAL_MESSAGE_INFORMATION_CONTINUITY = source.RES_UG_ADDITIONAL_MESSAGE_INFORMATION_CONTINUITY,
        target.RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT = source.RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT,
        target.RES_UC_SPENDING_ACCOUNT_AMOUNT_REMAINING = source.RES_UC_SPENDING_ACCOUNT_AMOUNT_REMAINING,
        target.RES_U9_DISPENSING_FEE_REIMBURSABLE_AMOUNT = source.RES_U9_DISPENSING_FEE_REIMBURSABLE_AMOUNT,
        target.RES_U8_INGREDIENT_COST_REIMBURSABLE_AMOUNT = source.RES_U8_INGREDIENT_COST_REIMBURSABLE_AMOUNT,
        target.REQ_U7_PHARMACY_SERVICE_TYPE = source.REQ_U7_PHARMACY_SERVICE_TYPE,
        target.RES_NZ_AMOUNT_ATTRIBUTED_TO_PROCESSOR_FEE = source.RES_NZ_AMOUNT_ATTRIBUTED_TO_PROCESSOR_FEE,
        target.RES_J8_PAYER_ID = source.RES_J8_PAYER_ID,
        target.RES_J7_PAYER_ID_QUALIFIER = source.RES_J7_PAYER_ID_QUALIFIER,
        target.RES_J5_OTHER_PAYER_AMOUNT_RECOGNIZED = source.RES_J5_OTHER_PAYER_AMOUNT_RECOGNIZED,
        target.RES_J4_OTHER_AMOUNT_PAID = source.RES_J4_OTHER_AMOUNT_PAID,
        target.RES_J3_OTHER_AMOUNT_PAID_QUALIFIER = source.RES_J3_OTHER_AMOUNT_PAID_QUALIFIER,
        target.RES_J2_OTHER_AMOUNT_PAID_COUNT = source.RES_J2_OTHER_AMOUNT_PAID_COUNT,
        target.RES_J1_PROFESSIONAL_SERVICE_FEE_PAID = source.RES_J1_PROFESSIONAL_SERVICE_FEE_PAID,
        target.RES_FQ_ADDITIONAL_MESSAGE_INFORMATION = source.RES_FQ_ADDITIONAL_MESSAGE_INFORMATION,
        target.RES_FO_PLAN_ID = source.RES_FO_PLAN_ID,
        target.RES_FM_BASIS_OF_REIMBURSEMENT_DETERMINATION = source.RES_FM_BASIS_OF_REIMBURSEMENT_DETERMINATION,
        target.RES_FL_INCENTIVE_AMOUNT_PAID = source.RES_FL_INCENTIVE_AMOUNT_PAID,
        target.RES_FK_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM = source.RES_FK_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM,
        target.RES_FI_AMOUNT_OF_COPAY = source.RES_FI_AMOUNT_OF_COPAY,
        target.RES_FH_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE = source.RES_FH_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE,
        target.RES_FE_REMAINING_BENEFIT_AMOUNT = source.RES_FE_REMAINING_BENEFIT_AMOUNT,
        target.RES_FD_REMAINING_DEDUCTIBLE_AMOUNT = source.RES_FD_REMAINING_DEDUCTIBLE_AMOUNT,
        target.RES_FC_ACCUMULATED_DEDUCTIBLE_AMOUNT = source.RES_FC_ACCUMULATED_DEDUCTIBLE_AMOUNT,
        target.RES_FB_REJECT_CODE = source.RES_FB_REJECT_CODE,
        target.RES_FA_REJECT_COUNT = source.RES_FA_REJECT_COUNT,
        target.RES_F9_TOTAL_AMOUNT_PAID = source.RES_F9_TOTAL_AMOUNT_PAID,
        target.RES_F7_DISPENSING_FEE_PAID = source.RES_F7_DISPENSING_FEE_PAID,
        target.RES_F6_INGREDIENT_COST_PAID = source.RES_F6_INGREDIENT_COST_PAID,
        target.RES_F5_PATIENT_PAY_AMOUNT = source.RES_F5_PATIENT_PAY_AMOUNT,
        target.RES_F4_MESSAGE = source.RES_F4_MESSAGE,
        target.RES_F3_AUTHORIZATION_NUMBER = source.RES_F3_AUTHORIZATION_NUMBER,
        target.RES_EQ_PATIENT_PERCENTAGE_TAX_AMOUNT = source.RES_EQ_PATIENT_PERCENTAGE_TAX_AMOUNT,
        target.RES_C1_GROUP_ID = source.RES_C1_GROUP_ID,
        target.RES_AZ_PERCENTAGE_TAX_BASIS_PAID = source.RES_AZ_PERCENTAGE_TAX_BASIS_PAID,
        target.RES_AY_PERCENTAGE_TAX_RATE_PAID = source.RES_AY_PERCENTAGE_TAX_RATE_PAID,
        target.RES_AX_PERCENTAGE_TAX_AMOUNT_PAID = source.RES_AX_PERCENTAGE_TAX_AMOUNT_PAID,
        target.RES_AW_REGULATORY_FEE_AMOUNT_PAID = source.RES_AW_REGULATORY_FEE_AMOUNT_PAID,
        target.RES_AV_PERCENTAGE_TAX_EXEMPT_INDICATOR = source.RES_AV_PERCENTAGE_TAX_EXEMPT_INDICATOR,
        target.RES_AN_TRANSACTION_RESPONSE_STATUS = source.RES_AN_TRANSACTION_RESPONSE_STATUS,
        target.REQ_AK_SOFTWARE_VENDOR_ID = source.REQ_AK_SOFTWARE_VENDOR_ID,
        target.RES_5F_APPROVED_MESSAGE_COUNT = source.RES_5F_APPROVED_MESSAGE_COUNT,
        target.RES_6F_APPROVED_MESSAGE_CODE = source.RES_6F_APPROVED_MESSAGE_CODE,
        target.RES_4V_BASIS_OF_CALCULATION_COINSURANCE = source.RES_4V_BASIS_OF_CALCULATION_COINSURANCE,
        target.RES_4U_AMOUNT_OF_COINSURANCE = source.RES_4U_AMOUNT_OF_COINSURANCE,
        target.RES_2F_NETWORK_REIMBURSEMENT_ID = source.RES_2F_NETWORK_REIMBURSEMENT_ID,
        target.REQ_FO_PLAN_ID = source.REQ_FO_PLAN_ID,
        target.RES_NT_OTHER_PAYER_ID_COUNT = source.RES_NT_OTHER_PAYER_ID_COUNT,
        target.RES_6C_OTHER_PAYER_ID_QUALIFIER = source.RES_6C_OTHER_PAYER_ID_QUALIFIER,
        target.RES_7C_OTHER_PAYER_ID = source.RES_7C_OTHER_PAYER_ID,
        target.RES_MH_OTHER_PAYER_PROCESSOR_CONTROL_NUMBER = source.RES_MH_OTHER_PAYER_PROCESSOR_CONTROL_NUMBER,
        target.REQ_EB_ORIGINALLY_PRESCRIBED_QUANTITY = source.REQ_EB_ORIGINALLY_PRESCRIBED_QUANTITY
;

EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR - CLAIMS IMPORT ERROR ' || TO_VARCHAR(:P_TARGET_DATE);
END;
$$;




--======================================================================================================================================================
--======================================================================================================================================================
-- CLEAN UP
--======================================================================================================================================================
--======================================================================================================================================================
DROP TABLE IF EXISTS BACKFILL_LOG;
DROP TABLE IF EXISTS BACKFILL_CONTROL;
ALTER TASK IF EXISTS TASK_BACKLOG_CLAIMS_LOG SUSPEND;
DROP TASK IF EXISTS TASK_BACKLOG_CLAIMS_LOG;
DROP PROCEDURE IF EXISTS REGISTER_BACKFILL(STRING, DATE, DATE);
DROP PROCEDURE IF EXISTS BACKFILL_CLAIMS_LOG(DATE);
--TRUNCATE TABLE CPE_CLAIMS_LOG;

--======================================================================================================================================================
--======================================================================================================================================================
-- SUPPORT
--======================================================================================================================================================
--======================================================================================================================================================
SELECT DISTINCT DATE(INGESTED_TIMESTAMP) AS DATE, COUNT(*) AS CNT FROM STAGING.STAGE_CPE_TRANSMISSIONS WHERE INGESTED_TIMESTAMP BETWEEN DATE('2025-12-15') AND DATE('2025-12-20') GROUP BY DATE ORDER BY DATE DESC;
SELECT DISTINCT DATE(CPH_INGESTED_TIMESTAMP) AS DATE, COUNT(*) AS CNT  FROM CPE_CLAIMS_LOG GROUP BY DATE ORDER BY DATE DESC;

SELECT * FROM BACKFILL_LOG;

SELECT COUNT(*) FROM CPE_CLAIMS_LOG;
SELECT * FROM CPE_CLAIMS_LOG LIMIT 100;

-- EXECUTE BACKFILL PROCESS
CALL BACKFILL_CLAIMS_LOG('2026-02-11');
SELECT * FROM CPE_CLAIMS_LOG LIMIT 100;


--======================================================================================================================================================
--======================================================================================================================================================
-- TASK TO AUTOMATE BACKFILL PROCESS
--======================================================================================================================================================
--======================================================================================================================================================
--TRUNCATE TABLE BACKFILL_CONTROL;
--TRUNCATE TABLE BACKFILL_LOG;

-- REGISTER BACKFILL TASK
SET DAYS_FROM_TODAY = -5;
CALL REGISTER_BACKFILL('TASK_BACKLOG_CLAIMS_LOG', DATEADD(DAY, $DAYS_FROM_TODAY, CURRENT_DATE()), CURRENT_DATE());
SELECT * FROM BACKFILL_CONTROL;

-- CREATE TASK #1
CREATE OR REPLACE TASK TASK_BACKLOG_CLAIMS_LOG
--     WAREHOUSE = WH_RESEARCH
    SCHEDULE = 'USING CRON * * * * * UTC'  AS
    CALL EXECUTE_BACKFILL('TASK_BACKLOG_CLAIMS_LOG', 'BACKFILL_CLAIMS_LOG');
ALTER TASK TASK_BACKLOG_CLAIMS_LOG SUSPEND;
ALTER TASK TASK_BACKLOG_CLAIMS_LOG RESUME;
EXECUTE TASK TASK_BACKLOG_CLAIMS_LOG;

-- Full Back Log
CALL REGISTER_BACKFILL('TASK_BACKLOG_CLAIMS_LOG', '2021-01-01', '2025-10-29');


CALL REGISTER_BACKFILL('TASK_BACKLOG_CLAIMS_LOG', '2025-10-29', CURRENT_DATE());

SELECT * FROM BACKFILL_CONTROL;
SELECT COUNT(*) FROM CPE_CLAIMS_LOG;

SELECT * FROM CPE_CLAIMS_LOG LIMIT 100;

SELECT REQ_EB_ORIGINALLY_PRESCRIBED_QUANTITY, RES_MH_OTHER_PAYER_PROCESSOR_CONTROL_NUMBER, *
FROM CPE_PROD.DATA.CPE_CLAIMS_LOG
WHERE REQ_EB_ORIGINALLY_PRESCRIBED_QUANTITY IS NOT NULL
   OR RES_MH_OTHER_PAYER_PROCESSOR_CONTROL_NUMBER IS NOT NULL;

