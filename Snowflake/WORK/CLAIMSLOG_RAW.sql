------------------------------------------------------------------------------------------------------------------------------------------------------
-- COLLECT SAMPLE DATA
------------------------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE SAMPLE_DATA AS
    SELECT * FROM (
        SELECT *,
              DATA:transmissionId::STRING   as TRANSMISSION_ID,
              TRY_TO_TIMESTAMP_NTZ(DATA:created::STRING) AS TIME_RECEIVED_AT_SWITCH
           FROM CPE_PROD.STAGING.STAGE_CPE_TRANSMISSIONS as t
           WHERE INGESTED_TIMESTAMP BETWEEN '2026-01-22' AND '2026-01-23'
           LIMIT 100
    )
    -- Select only latest the latest Transmission based on Time Received at Switch.  (Latest Ingested Timestamp as tie-breaker)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY TRANSMISSION_ID ORDER BY TIME_RECEIVED_AT_SWITCH DESC, INGESTED_TIMESTAMP DESC) = 1;


    -- Sample Transmission
    WITH SOURCE AS (
        SELECT * FROM SAMPLE_DATA
    )

   -- Identify Request/Response Claim Pairs
   ,NCPDP_DATA AS (
        SELECT
            -- Transmission Id
            t.TRANSMISSION_ID,

            -- Record Id
            t.TRANSMISSION_ID || IFF(SUBSTR(LTRIM(EXTRACT_NCPDP_FIELD(ncpdpData.value, 'D2', 1), '0'), 0, 12) IS NULL, '', '-' || SUBSTR(LTRIM(EXTRACT_NCPDP_FIELD(ncpdpData.value, 'D2', 1), '0'), 0, 12)) AS "RECORD_ID",

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
    , REQUESTS as (
        SELECT
            TRANSMISSION_ID,
            RECORD_ID,
            MAX(REQUEST) as REQUEST
        FROM NCPDP_DATA
        WHERE REQUEST IS NOT NULL
        GROUP BY TRANSMISSION_ID, RECORD_ID
    )


    -- Individual NCPDP Responses (RECORD_ID)
    , RESPONSES as (
        SELECT
            TRANSMISSION_ID,
            RECORD_ID,
            MAX(RESPONSE) as RESPONSE
        FROM NCPDP_DATA
        WHERE RESPONSE IS NOT NULL
        GROUP BY TRANSMISSION_ID, RECORD_ID
    )

    -- Transaction Level Data (Shared Response)
    , TRX as (
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
   , CLAIMS AS (
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
          LEFT JOIN TRX as trx
             ON req.TRANSMISSION_ID = trx.TRANSMISSION_ID
          LEFT JOIN RESPONSES as res
            ON req.TRANSMISSION_ID = res.TRANSMISSION_ID
            AND req.RECORD_ID = res.RECORD_ID
    )

    , FINAL AS (

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
            TRY_TO_TIMESTAMP_NTZ(DATA:returned::STRING)                                   AS CPH_RETURNED_TIMESTAMP,
            TRY_TO_TIMESTAMP_NTZ(DATA:created::STRING)                                    AS CPH_CREATED_TIMESTAMP,
            DATA:pcn::STRING                                                              AS CPH_A4_PCN,
            DATA:ncpdp::STRING                                                            AS CPH_B107_SERVICE_PROVIDER_NCPDP,
            DATA:npi::STRING                                                              AS CPH_B101_SERVICE_PROVIDER_NPI,
            DATA:responseStatusCode::STRING                                               AS CPH_AN_TRANSACTION_RESPONSE_STATUS,
            DATA:bin::STRING                                                              AS CPH_A1_IIN,

            ----------------------------------------------------------------------------------------------------
            --[REQUEST FIELDS]
            ----------------------------------------------------------------------------------------------------

            -- NCPDP SEGMENT (TRANSACTION HEADER)
            TRIM(SUBSTR(REQUEST, 0, 6))                                                   AS REQ_A1_IIN,                                                   //HEADER [Position: 1–6   = BIN (A1, 6 chars)]
            TRIM(SUBSTR(REQUEST, 7, 2))                                                   AS CPH_A2_VERSION,                                               //HEADER [Position: 7–8   = Version (A2, 2 chars)]
            TRIM(SUBSTR(REQUEST, 9, 2))                                                   AS CPH_A3_TRANSACTION_CODE,                                      //HEADER [Position: 9–10  = Transaction Code (A3, 2 chars)]
            TRIM(SUBSTR(REQUEST, 11, 10))                                                 AS REQ_A4_PCN,                                                   //HEADER [Position: 11–20 = Processor Control (A4, 10 chars)]
            TRIM(SUBSTR(REQUEST, 21, 1))                                                  AS CPH_A9_TRANSACTION_COUNT,                                     //HEADER [Position: 21    = Transaction Count (A9, 1 char)]
            TRIM(SUBSTR(REQUEST, 22, 2))                                                  AS REQ_B2_SERVICE_PROVIDER_ID_QUALIFIER,                         //HEADER [Position: 22–23 = Service Provider Qualifier (B2, 2 chars)]
            TRIM(SUBSTR(REQUEST, 24, 15))                                                 AS REQ_B1_SERVICE_PROVIDER_ID,                                   //HEADER [Position: 24–38 = Service Provider ID (B1, 15 chars)]
            TRIM(SUBSTR(REQUEST, 39, 8))                                                  AS REQ_D1_DATE_OF_SERVICE,                                       //HEADER [Position: 39–46 = Date of Service (D1, 8 chars)]
            TRIM(SUBSTR(REQUEST, 47, 10))                                                 AS REQ_AK_SOFTWARE_VENDOR_ID,                                    //HEADER [Position: 47–56 = Vendor/Cert ID (AK, 10 chars)]

            -- NCPDP SEGMENT (INSURANCE)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C2', 1))                                   AS "REQ_C2_CARDHOLDER_ID",                                       //INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C3', 1))                                   AS "REQ_C3_PERSON_CODE",                                         //INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C6', 1))                                   AS "REQ_C6_PATIENT_RELATIONSHIP_CODE",                           //INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CC', 1))                                   AS "REQ_CC_CARDHOLDER_FIRST_NAME",                               //INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CD', 1))                                   AS "REQ_CD_CARDHOLDER_LAST_NAME",                                //INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2A', 1))                                   AS "REQ_2A_MEDIGAP_ID",                                          //INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C1', 1))                                   AS "REQ_C1_GROUP_ID",                                            //INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C9', 1))                                   AS "REQ_C9_ELIGIBILITY_CLARIFICATION_CODE",                      //INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'N5', 1))                                   AS "REQ_N5_MEDICAID_ID_NUMBER",                                  //INSURANCE

            -- NCPDP SEGMENT (PATIENT)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CA', 1))                                   AS "REQ_CA_PATIENT_FIRST_NAME",                                  //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CB', 1))                                   AS "REQ_CB_PATIENT_LAST_NAME",                                   //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C4', 1))                                   AS "REQ_C4_PATIENT_DATE_OF_BIRTH",                               //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C5', 1))                                   AS "REQ_C5_PATIENT_GENDER_CODE",                                 //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CY', 1))                                   AS "REQ_CY_PATIENT_ID",                                          //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CX', 1))                                   AS "REQ_CX_PATIENT_ID_QUALIFIER",                                //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CM', 1))                                   AS "REQ_CM_PATIENT_STREET_ADDRESS",                              //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CN', 1))                                   AS "REQ_CN_PATIENT_CITY",                                        //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CO', 1))                                   AS "REQ_CO_PATIENT_STATE",                                       //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CP', 1))                                   AS "REQ_CP_PATIENT_ZIP",                                         //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C7', 1))                                   AS "REQ_C7_PLACE_OF_SERVICE",                                    //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '4X', 1))                                   AS "REQ_4X_PATIENT_RESIDENCE",                                   //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CQ', 1))                                   AS "REQ_CQ_PATIENT_TELEPHONE_NUMBER",                            //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2C', 1))                                   AS "REQ_2C_PREGNANCY_INDICATOR",                                 //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CZ', 1))                                   AS "REQ_CZ_EMPLOYER_ID",                                         //PATIENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'HN', 1))                                   AS "REQ_HN_PATIENT_EMAIL_ADDRESS",                               //PATIENT

            --=[GROUPED SEGMENTS]=--

            -- NCPDP SEGMENT (CLAIM)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '28', 1))                                   AS "REQ_28_UNIT_OF_MEASURE",                                     //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'C8', 1))                                   AS "REQ_C8_OTHER_COVERAGE_CODE",                                 //CLAIM
            SUBSTR(LTRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D2', 1), '0'), 0, 12)              AS "REQ_D2_RX_NUMBER",                                           //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D3', 1))                                   AS "REQ_D3_FILL_NUMBER",                                         //CLAIM

            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D5', 1))                                   AS "REQ_D5_DAYS_SUPPLY",                                         //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D6', 1))                                   AS "REQ_D6_COMPOUND_CODE",                                       //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DF', 1))                                   AS "REQ_DF_NUMBER_OF_REFILLS_AUTHORIZED",                        //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DI', 1))                                   AS "REQ_DI_LEVEL_OF_SERVICE",                                    //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DT', 1))                                   AS "REQ_DT_SPECIAL_PACKAGING_INDICATOR",                         //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DJ', 1))                                   AS "REQ_DJ_PRESCRIPTION_ORIGIN_CODE",                            //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DE', 1))                                   AS "REQ_DE_DATE_PRESCRIPTION_WRITTEN",                           //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EA', 1))                                   AS "REQ_EA_ORIGINALLY_PRESCRIBED_PRODUCT_CODE",                  //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EJ', 1))                                   AS "REQ_EJ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER",          //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EN', 1))                                   AS "REQ_EN_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER",            //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EP', 1))                                   AS "REQ_EP_ASSOCIATED_PRESCRIPTION_DATE",                        //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EM', 1))                                   AS "REQ_EM_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER",             //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EU', 1))                                   AS "REQ_EU_PRIOR_AUTHORIZATION_TYPE_CODE",                       //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D7', 1))                                   AS "REQ_D7_PRODUCT_ID",                                          //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'E1', 1))                                   AS "REQ_E1_PRODUCT_ID_QUALIFIER",                                //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'D8', 1))                                   AS "REQ_D8_DAW_PRODUCT_SELECTION_CODE",                          //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DK', 1))                                   AS "REQ_DK_SUBMISSION_CLARIFICATION_CODE",                       //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'E7', 1))                                   AS "REQ_E7_QUANTITY_DISPENSED",                                  //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EK', 1))                                   AS "REQ_EK_SCHEDULED_PRESCRIPTION_ID_NUMBER",                    //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'K5', 1))                                   AS "REQ_K5_TRANSACTION_REFERENCE_NUMBER",                        //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'HD', 1))                                   AS "REQ_HD_DISPENSING_STATUS",                                   //CLAIM
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'U7', 1))                                   AS "REQ_U7_PHARMACY_SERVICE_TYPE",                               //CLAIM
            CASE WHEN REQ_E1_PRODUCT_ID_QUALIFIER = '03' THEN REQ_D7_PRODUCT_ID END       AS REQ_D703_NDC,                                                 //CLAIM

            -- NCPDP SEGMENT (PRICING)
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'DQ', 1))                   AS "REQ_DQ_USUAL_AND_CUSTOMARY",                                 //PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'DX', 1))                   AS "REQ_DX_PATIENT_PAY_AMOUNT_REPORTED",                         //PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'D9', 1))                   AS "REQ_D9_INGREDIENT_COST_SUBMITTED",                           //PRICING
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DN', 1))                                   AS "REQ_DN_BASIS_OF_COST_DETERMINATION",                         //PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'DC', 1))                   AS "REQ_DC_DISPENSING_FEE_SUBMITTED",                            //PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'E3', 1))                   AS "REQ_E3_INCENTIVE_AMOUNT_SUBMITTED",                          //PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'BE', 1))                   AS "REQ_BE_PROFESSIONAL_SERVICE_FEE_SUBMITTED",                  //PRICING
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'H8', 1))                                   AS "REQ_H8_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER",            //PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'H9', 1))                   AS "REQ_H9_OTHER_AMOUNT_CLAIMED_SUBMITTED",                      //PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'HA', 1))                   AS "REQ_HA_REGULATORY_FEE_AMOUNT_SUBMITTED",                     //PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'GE', 1))                   AS "REQ_GE_PERCENTAGE_TAX_AMOUNT_SUBMITTED",                     //PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'DU', 1))                   AS "REQ_DU_GROSS_AMOUNT_DUE",                                    //PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'JE', 1))                   AS "REQ_JE_PERCENTAGE_TAX_BASIS_SUBMITTED",                      //PRICING

            -- NCPDP SEGMENT (FACILITY)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '8C', 1))                                   AS "REQ_8C_FACILITY_ID",                                         //FACILITY
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '6D', 1))                                   AS "REQ_6D_PHARMACY_ZIP",                                        //FACILITY

            -- NCPDP SEGMENT (PRESCRIBER)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EZ', 1))                                   AS "REQ_EZ_PRESCRIBER_ID_QUALIFIER",                             //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DR', 1))                                   AS "REQ_DR_PRESCRIBER_LAST_NAME",                                //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2J', 1))                                   AS "REQ_2J_PRESCRIBER_FIRST_NAME",                               //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2K', 1))                                   AS "REQ_2K_PRESCRIBER_STREET_ADDRESS",                           //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2M', 1))                                   AS "REQ_2M_PRESCRIBER_CITY",                                     //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2N', 1))                                   AS "REQ_2N_PRESCRIBER_STATE",                                    //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2P', 1))                                   AS "REQ_2P_PRESCRIBER_ZIP",                                      //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'PM', 1))                                   AS "REQ_PM_PRESCRIBER_TELEPHONE_NUMBER",                         //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DL', 1))                                   AS "REQ_DL_PRIMARY_CARE_PROVIDER_ID",                            //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '2E', 1))                                   AS "REQ_2E_PRIMARY_CARE_PROVIDER_ID_QUALIFIER",                  //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DB', 1))                                   AS "REQ_DB_PRESCRIBER_ID",                                       //PRESCRIBER
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '4E', 1))                                   AS "REQ_4E_PRIMARY_CARE_PROVIDER_LAST_NAME",                     //PRESCRIBER
            CASE
                WHEN REQ_EZ_PRESCRIBER_ID_QUALIFIER = '01'
                    THEN REQ_DB_PRESCRIBER_ID END                                         AS REQ_DB01_PRESCRIBER_NPI,                                      //PRESCRIBER

            -- NCPDP SEGMENT (COORDINATION)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '5E', 1))                                   AS "REQ_5E_OTHER_PAYER_REJECT_COUNT",                            //COORDINATION OF BENEFITS
            STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED(REQUEST, '6E'))                    AS "REQ_6E_OTHER_PAYER_REJECT_CODE",                             //COORDINATION OF BENEFITS
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'DV', 1))                   AS "REQ_DV_OTHER_PAYER_AMOUNT_PAID",                             //COORDINATION OF BENEFITS
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'NP', 1))                                   AS "REQ_NP_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_QUALIFIER", //COORDINATION OF BENEFITS
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'NR', 1))                                   AS "REQ_NR_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_COUNT",     //COORDINATION OF BENEFITS
            TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED(REQUEST, 'NQ')),
                      x -> PARSE_NCPDP_CURRENCY(x))                                       AS "REQ_NQ_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT",           //COORDINATION OF BENEFITS
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '6C', 1))                                   AS "REQ_6C_OTHER_PAYER_ID_QUALIFIER",                            //COORDINATION OF BENEFITS
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'HC', 1))                                   AS "REQ_HC_OTHER_PAYER_AMOUNT_PAID_QUALIFIER",                   //COORDINATION OF BENEFITS
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '4C', 1))                                   AS "REQ_4C_COORDINATION_OF_BENEFITS_COUNT",                      //COORDINATION OF BENEFITS
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'NT', 1))                                   AS "REQ_NT_OTHER_PAYER_ID_COUNT",                                //COORDINATION OF BENEFITS
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '5C', 1))                                   AS "REQ_5C_OTHER_PAYER_COVERAGE_TYPE",                           //COORDINATION OF BENEFITS
            STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED(REQUEST, '7C'))                    AS "REQ_7C_OTHER_PAYER_ID",                                      //COORDINATION OF BENEFITS

            -- NCPDP SEGMENT (WORKERS COMPENSATION)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'TZ', 1))                                   AS "REQ_TZ_GENERIC_EQUIVALENT_PRODUCT_ID_QUALIFIER",             //WORKERS COMPENSATION
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'UA', 1))                                   AS "REQ_UA_GENERIC_EQUIVALENT_PRODUCT_ID",                       //WORKERS COMPENSATION
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CF', 1))                                   AS "REQ_CF_EMPLOYER_NAME",                                       //WORKERS COMPENSATION
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CG', 1))                                   AS "REQ_CG_EMPLOYER_STREET_ADDRESS",                             //WORKERS COMPENSATION
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CH', 1))                                   AS "REQ_CH_EMPLOYER_CITY",                                       //WORKERS COMPENSATION
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CI', 1))                                   AS "REQ_CI_EMPLOYER_STATE",                                      //WORKERS COMPENSATION
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CJ', 1))                                   AS "REQ_CJ_EMPLOYER_ZIP",                                        //WORKERS COMPENSATION
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CK', 1))                                   AS "REQ_CK_EMPLOYER_TELEPHONE_NUMBER",                           //WORKERS COMPENSATION
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DZ', 1))                                   AS "REQ_DZ_WORKERS_COMP_CLAIM_ID",                               //WORKERS COMPENSATION
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'CR', 1))                                   AS "REQ_CR_CARRIER_ID",                                          //WORKERS COMPENSATION
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'DY', 1))                                   AS "REQ_DY_DATE_OF_INJURY",                                      //WORKERS COMPENSATION

            -- NCPDP SEGMENT (DUR/PPS)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'E4', 1))                                   AS "REQ_E4_REASON_FOR_SERVICE_CODE",                             //DUR/PPS SEGMENT
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'E5', 1))                                   AS "REQ_E5_PROFESSIONAL_SERVICE_CODE",                           //DUR/PPS SEGMENT

            -- NCPDP SEGMENT (COMPOUND)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'EC', 1))                                   AS "REQ_EC_COMPOUND_INGREDIENT_COMPONENT_COUNT",                 //COMPOUND
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'ED', 1))                                   AS "REQ_ED_COMPOUND_INGREDIENT_QUANTITY",                        //COMPOUND
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(REQUEST, 'EE', 1))                   AS "REQ_EE_COMPOUND_INGREDIENT_DRUG_COST",                       //COMPOUND
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'RE', 1))                                   AS "REQ_RE_COMPOUND_PRODUCT_ID_QUALIFIER",                       //COMPOUND
            STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED(REQUEST, 'TE'))                    AS "REQ_TE_COMPOUND_PRODUCT_ID",                                 //COMPOUND

            -- NCPDP SEGMENT (CLINICAL)
            STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED(REQUEST, 'DO'))                    AS "REQ_DO_DIAGNOSIS_CODE",                                      //CLINICAL
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'WE', 1))                                   AS "REQ_WE_DIAGNOSIS_CODE_QUALIFIER",                            //CLINICAL
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'VE', 1))                                   AS "REQ_VE_DIAGNOSIS_CODE_COUNT",                                //CLINICAL

            -- NCPDP SEGMENT (FACILITY)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '5J', 1))                                   AS "REQ_5J_PHARMACY_CITY",                                       //FACILITY
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '3Q', 1))                                   AS "REQ_3Q_PHARMACY_NAME",                                       //FACILITY
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '3U', 1))                                   AS "REQ_3U_PHARMACY_STREET_ADDRESS",                             //FACILITY
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, '3V', 1))                                   AS "REQ_3V_PHARMACY_STATE",                                      //FACILITY

            -- NCPDP SEGMENT (NARRATIVE)
            TRIM(EXTRACT_NCPDP_FIELD(REQUEST, 'BM', 1))                                   AS "REQ_BM_NARRATIVE_MESSAGE",                                   //NARRATIVE

            ----------------------------------------------------------------------------------------------------
            --[RESPONSE FIELDS]
            ----------------------------------------------------------------------------------------------------

            -- NCPDP SEGMENT (RESPONSE MESSAGE)
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'F4', 1))                                  AS "RES_F4_MESSAGE",                                             //RESPONSE MESSAGE

            -- NCPDP SEGMENT (RESPONSE INSURANCE)
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'C1', 1))                                  AS "RES_C1_GROUP_ID",                                            //RESPONSE INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, '2F', 1))                                  AS "RES_2F_NETWORK_REIMBURSEMENT_ID",                            //RESPONSE INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'J8', 1))                                  AS "RES_J8_PAYER_ID",                                            //RESPONSE INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'J7', 1))                                  AS "RES_J7_PAYER_ID_QUALIFIER",                                  //RESPONSE INSURANCE
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'FO', 1))                                  AS "RES_FO_PLAN_ID",                                             //RESPONSE INSURANCE

            -- NCPDP SEGMENT (RESPONSE STATUS)
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'FA', 1))                                  AS "RES_FA_REJECT_COUNT",                                        //RESPONSE STATUS
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'F3', 1))                                  AS "RES_F3_AUTHORIZATION_NUMBER",                                //RESPONSE STATUS
            TRIM(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'UH', ','))                      AS "RES_UH_ADDITIONAL_MESSAGE_INFORMATION_QUALIFIER",            //RESPONSE STATUS
            TRIM(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'UG', ','))                      AS "RES_UG_ADDITIONAL_MESSAGE_INFORMATION_CONTINUITY",           //RESPONSE STATUS
            TRIM(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, '6F', ','))                      AS "RES_6F_APPROVED_MESSAGE_CODE",                               //RESPONSE STATUS
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'UF', 1))                                  AS "RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT",                //RESPONSE STATUS
            STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED(RESPONSE, 'FB'))                   AS "RES_FB_REJECT_CODE",                                         //RESPONSE STATUS
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'AN', 1))                                  AS "RES_AN_TRANSACTION_RESPONSE_STATUS",                         //RESPONSE STATUS
            STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'FQ', '~SEP~'),
                            '~SEP~')                                                         RES_FQ_ADDITIONAL_MESSAGE_INFORMATION,                        //RESPONSE STATUS


            -- NCPDP SEGMENT (RESPONSE PRICING)
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FH', 1))                  AS "RES_FH_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE",               //RESPONSE PRICING
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'AV', 1))                                  AS "RES_AV_PERCENTAGE_TAX_EXEMPT_INDICATOR",                     //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'F5', 1))                  AS "RES_F5_PATIENT_PAY_AMOUNT",                                  //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'F6', 1))                  AS "RES_F6_INGREDIENT_COST_PAID",                                //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'F7', 1))                  AS "RES_F7_DISPENSING_FEE_PAID",                                 //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FL', 1))                  AS "RES_FL_INCENTIVE_AMOUNT_PAID",                               //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'J1', 1))                  AS "RES_J1_PROFESSIONAL_SERVICE_FEE_PAID",                       //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'J5', 1))                  AS "RES_J5_OTHER_PAYER_AMOUNT_RECOGNIZED",                       //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'AW', 1))                  AS "RES_AW_REGULATORY_FEE_AMOUNT_PAID",                          //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'AX', 1))                  AS "RES_AX_PERCENTAGE_TAX_AMOUNT_PAID",                          //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'F9', 1))                  AS "RES_F9_TOTAL_AMOUNT_PAID",                                   //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FC', 1))                  AS "RES_FC_ACCUMULATED_DEDUCTIBLE_AMOUNT",                       //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FD', 1))                  AS "RES_FD_REMAINING_DEDUCTIBLE_AMOUNT",                         //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FE', 1))                  AS "RES_FE_REMAINING_BENEFIT_AMOUNT",                            //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FI', 1))                  AS "RES_FI_AMOUNT_OF_COPAY",                                     //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FK', 1))                  AS "RES_FK_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM",           //RESPONSE PRICING
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'FM', 1))                                  AS "RES_FM_BASIS_OF_REIMBURSEMENT_DETERMINATION",                //RESPONSE PRICING
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'J3', 1))                                  AS "RES_J3_OTHER_AMOUNT_PAID_QUALIFIER",                         //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'FJ', 1))                  AS "RES_FJ_AMOUNT_ATTRIBUTED_TO_PRODUCT_SELECTION",              //RESPONSE PRICING
            TRANSFORM(STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED(RESPONSE, 'J4')),
                      x -> PARSE_NCPDP_CURRENCY(x))                                       AS "RES_J4_OTHER_AMOUNT_PAID",                                   //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'UM', 1))                  AS "RES_UM_AMOUNT_ATTRIBUTED_TO_NON_PREFERRED_SELECTION",        //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'UK', 1))                  AS "RES_UK_AMOUNT_ATTRIBUTED_TO_BRAND_DRUG",                     //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'UJ', 1))                  AS "RES_UJ_AMOUNT_ATTRIBUTED_TO_PROVIDER_NETWORK_SELECTION",     //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'UC', 1))                  AS "RES_UC_SPENDING_ACCOUNT_AMOUNT_REMAINING",                   //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'U9', 1))                  AS "RES_U9_DISPENSING_FEE_REIMBURSABLE_AMOUNT",                  //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'U8', 1))                  AS "RES_U8_INGREDIENT_COST_REIMBURSABLE_AMOUNT",                 //RESPONSE PRICING
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'J2', 1))                                  AS "RES_J2_OTHER_AMOUNT_PAID_COUNT",                             //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'NZ', 1))                  AS "RES_NZ_AMOUNT_ATTRIBUTED_TO_PROCESSOR_FEE",                  //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'EQ', 1))                  AS "RES_EQ_PATIENT_PERCENTAGE_TAX_AMOUNT",                       //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'AZ', 1))                  AS "RES_AZ_PERCENTAGE_TAX_BASIS_PAID",                           //RESPONSE PRICING
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, '4V', 1))                                  AS "RES_4V_BASIS_OF_CALCULATION_COINSURANCE",                    //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, '4U', 1))                  AS "RES_4U_AMOUNT_OF_COINSURANCE",                               //RESPONSE PRICING
            PARSE_NCPDP_CURRENCY(EXTRACT_NCPDP_FIELD(RESPONSE, 'AY', 1))                  AS "RES_AY_PERCENTAGE_TAX_RATE_PAID",                            //RESPONSE PRICING

            -- NCPDP SEGMENT (RESPONSE PRIOR AUTHORIZATION SEGMENT)
            TRIM(EXTRACT_NCPDP_FIELD(RESPONSE, 'PY', 1))                                  AS "RES_PY_PRIOR_AUTHORIZATION_ID_ASSIGNED"                      //RESPONSE PRIOR AUTHORIZATION SEGMENT

        FROM CLAIMS
    )
SELECT RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT, RES_FQ_ADDITIONAL_MESSAGE_INFORMATION
FROM FINAL
;
















------------------------------------------------------------------------------------------------------------------------------------------------------
-- FORMAT CLAIMS DATA
------------------------------------------------------------------------------------------------------------------------------------------------------
-- Sample Transmission
WITH SOURCE AS (
    SELECT * FROM SAMPLE_DATA
)

-- Identify Request/Response Claim Pairs
,NCPDP_DATA AS (
    SELECT
        -- Transmission Id
        t.TRANSMISSION_ID,

        -- Record Id
        t.TRANSMISSION_ID || IFF(SUBSTR(LTRIM(EXTRACT_NCPDP_FIELD(ncpdpData.value, 'D2', 1), '0'), 0, 12) IS NULL, '', '-' || SUBSTR(LTRIM(EXTRACT_NCPDP_FIELD(ncpdpData.value, 'D2', 1), '0'), 0, 12)) AS "RECORD_ID",

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
, REQUESTS as (
    SELECT
        TRANSMISSION_ID,
        RECORD_ID,
        MAX(REQUEST) as REQUEST
    FROM NCPDP_DATA
    WHERE REQUEST IS NOT NULL
    GROUP BY TRANSMISSION_ID, RECORD_ID
)


-- Individual NCPDP Responses (RECORD_ID)
, RESPONSES as (
    SELECT
        TRANSMISSION_ID,
        RECORD_ID,
        MAX(RESPONSE) as RESPONSE
    FROM NCPDP_DATA
    WHERE RESPONSE IS NOT NULL
    GROUP BY TRANSMISSION_ID, RECORD_ID
)

-- Transaction Level Data (Shared Response)
, TRX as (
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
, CLAIMS AS (
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
      LEFT JOIN TRX as trx
         ON req.TRANSMISSION_ID = trx.TRANSMISSION_ID
      LEFT JOIN RESPONSES as res
        ON req.TRANSMISSION_ID = res.TRANSMISSION_ID
        AND req.RECORD_ID = res.RECORD_ID
)

-- Rawest Form Of Claim Data
,RAW_CLAIMS AS (
    SELECT
   ----------------------------------------------------------------------------------------------------
   --[CLAIMS HEADER PAYLOAD FIELDS]
   ----------------------------------------------------------------------------------------------------
   HASH_KEY,
   TRANSMISSION_ID                                              AS CPH_TRANSMISSION_ID,
   RECORD_ID,
   INGESTED_TIMESTAMP                                           AS CPH_INGESTED_TIMESTAMP,
   DATA:routingAddress::STRING                                  AS CPH_ROUTING_ADDRESS,
   DATA:origin::STRING                                          AS CPH_ORIGIN,
   DATA:returned::STRING                                        AS CPH_RETURNED_TIMESTAMP,
   DATA:created::STRING                                         AS CPH_CREATED_TIMESTAMP,
   DATA:pcn::STRING                                             AS CPH_A4_PCN,
   DATA:ncpdp::STRING                                           AS CPH_B107_SERVICE_PROVIDER_NCPDP,
   DATA:npi::STRING                                             AS CPH_B101_SERVICE_PROVIDER_NPI,
   DATA:responseStatusCode::STRING                              AS CPH_AN_TRANSACTION_RESPONSE_STATUS,
   DATA:bin::STRING                                             AS CPH_A1_IIN,

   ----------------------------------------------------------------------------------------------------
   --[REQUEST FIELDS]
   ----------------------------------------------------------------------------------------------------

   -- NCPDP SEGMENT (TRANSACTION HEADER)
   SUBSTR(REQUEST, 0, 6) AS REQ_A1_IIN,   //HEADER [Position: 1–6   = BIN (A1, 6 chars)]
   SUBSTR(REQUEST, 7, 2) AS CPH_A2_VERSION,   //HEADER [Position: 7–8   = Version (A2, 2 chars)]
   SUBSTR(REQUEST, 9, 2) AS CPH_A3_TRANSACTION_CODE,   //HEADER [Position: 9–10  = Transaction Code (A3, 2 chars)]
   SUBSTR(REQUEST, 11, 10) AS REQ_A4_PCN,   //HEADER [Position: 11–20 = Processor Control (A4, 10 chars)]
   SUBSTR(REQUEST, 21, 1) AS CPH_A9_TRANSACTION_COUNT,   //HEADER [Position: 21    = Transaction Count (A9, 1 char)]
   SUBSTR(REQUEST, 22, 2) AS REQ_B2_SERVICE_PROVIDER_ID_QUALIFIER,   //HEADER [Position: 22–23 = Service Provider Qualifier (B2, 2 chars)]
   SUBSTR(REQUEST, 24, 15) AS REQ_B1_SERVICE_PROVIDER_ID,   //HEADER [Position: 24–38 = Service Provider ID (B1, 15 chars)]
   SUBSTR(REQUEST, 39, 8) AS REQ_D1_DATE_OF_SERVICE,   //HEADER [Position: 39–46 = Date of Service (D1, 8 chars)]
   SUBSTR(REQUEST, 47, 10) AS REQ_AK_SOFTWARE_VENDOR_ID,   //HEADER [Position: 47–56 = Vendor/Cert ID (AK, 10 chars)]

   -- NCPDP SEGMENT (INSURANCE)
   EXTRACT_NCPDP_FIELD(REQUEST, 'C2', 1) AS "REQ_C2_CARDHOLDER_ID",                                       //INSURANCE
   EXTRACT_NCPDP_FIELD(REQUEST, 'C3', 1) AS "REQ_C3_PERSON_CODE",                                         //INSURANCE
   EXTRACT_NCPDP_FIELD(REQUEST, 'C6', 1) AS "REQ_C6_PATIENT_RELATIONSHIP_CODE",                           //INSURANCE
   EXTRACT_NCPDP_FIELD(REQUEST, 'CC', 1) AS "REQ_CC_CARDHOLDER_FIRST_NAME",                               //INSURANCE
   EXTRACT_NCPDP_FIELD(REQUEST, 'CD', 1) AS "REQ_CD_CARDHOLDER_LAST_NAME",                                //INSURANCE
   EXTRACT_NCPDP_FIELD(REQUEST, '2A', 1) AS "REQ_2A_MEDIGAP_ID",                                          //INSURANCE
   EXTRACT_NCPDP_FIELD(REQUEST, 'C1', 1) AS "REQ_C1_GROUP_ID",                                            //INSURANCE
   EXTRACT_NCPDP_FIELD(REQUEST, 'C9', 1) AS "REQ_C9_ELIGIBILITY_CLARIFICATION_CODE",                      //INSURANCE
   EXTRACT_NCPDP_FIELD(REQUEST, 'N5', 1) AS "REQ_N5_MEDICAID_ID_NUMBER",                                  //INSURANCE

   -- NCPDP SEGMENT (PATIENT)
   EXTRACT_NCPDP_FIELD(REQUEST, 'CA', 1) AS "REQ_CA_PATIENT_FIRST_NAME",                                  //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'CB', 1) AS "REQ_CB_PATIENT_LAST_NAME",                                   //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'C4', 1) AS "REQ_C4_PATIENT_DATE_OF_BIRTH",                               //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'C5', 1) AS "REQ_C5_PATIENT_GENDER_CODE",                                 //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'CY', 1) AS "REQ_CY_PATIENT_ID",                                          //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'CX', 1) AS "REQ_CX_PATIENT_ID_QUALIFIER",                                //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'CM', 1) AS "REQ_CM_PATIENT_STREET_ADDRESS",                              //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'CN', 1) AS "REQ_CN_PATIENT_CITY",                                        //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'CO', 1) AS "REQ_CO_PATIENT_STATE",                                       //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'CP', 1) AS "REQ_CP_PATIENT_ZIP",                                         //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'C7', 1) AS "REQ_C7_PLACE_OF_SERVICE",                                    //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, '4X', 1) AS "REQ_4X_PATIENT_RESIDENCE",                                   //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'CQ', 1) AS "REQ_CQ_PATIENT_TELEPHONE_NUMBER",                            //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, '2C', 1) AS "REQ_2C_PREGNANCY_INDICATOR",                                 //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'CZ', 1) AS "REQ_CZ_EMPLOYER_ID",                                         //PATIENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'HN', 1) AS "REQ_HN_PATIENT_EMAIL_ADDRESS",                               //PATIENT

   --=[GROUPED SEGMENTS]=--

   -- NCPDP SEGMENT (CLAIM)
   EXTRACT_NCPDP_FIELD(REQUEST, '28', 1) AS "REQ_28_UNIT_OF_MEASURE",                                     //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'C8', 1) AS "REQ_C8_OTHER_COVERAGE_CODE",                                 //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'D2', 1) AS "REQ_D2_RX_NUMBER",                  //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'D3', 1) AS "REQ_D3_FILL_NUMBER",                                         //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'D5', 1) AS "REQ_D5_DAYS_SUPPLY",                                         //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'D6', 1) AS "REQ_D6_COMPOUND_CODE",                                       //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'DF', 1) AS "REQ_DF_NUMBER_OF_REFILLS_AUTHORIZED",                        //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'DI', 1) AS "REQ_DI_LEVEL_OF_SERVICE",                                    //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'DT', 1) AS "REQ_DT_SPECIAL_PACKAGING_INDICATOR",                         //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'DJ', 1) AS "REQ_DJ_PRESCRIPTION_ORIGIN_CODE",                            //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'DE', 1) AS "REQ_DE_DATE_PRESCRIPTION_WRITTEN",                           //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'EA', 1) AS "REQ_EA_ORIGINALLY_PRESCRIBED_PRODUCT_CODE",                  //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'EJ', 1) AS "REQ_EJ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER",          //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'EN', 1) AS "REQ_EN_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER",            //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'EP', 1) AS "REQ_EP_ASSOCIATED_PRESCRIPTION_DATE",                        //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'EM', 1) AS "REQ_EM_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER",             //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'EU', 1) AS "REQ_EU_PRIOR_AUTHORIZATION_TYPE_CODE",                       //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'D7', 1) AS "REQ_D7_PRODUCT_ID",                                          //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'E1', 1) AS "REQ_E1_PRODUCT_ID_QUALIFIER",                                //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'D8', 1) AS "REQ_D8_DAW_PRODUCT_SELECTION_CODE",                          //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'DK', 1) AS "REQ_DK_SUBMISSION_CLARIFICATION_CODE",                       //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'E7', 1) AS "REQ_E7_QUANTITY_DISPENSED",                                  //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'EK', 1) AS "REQ_EK_SCHEDULED_PRESCRIPTION_ID_NUMBER",                    //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'K5', 1) AS "REQ_K5_TRANSACTION_REFERENCE_NUMBER",                        //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'HD', 1) AS "REQ_HD_DISPENSING_STATUS",                                   //CLAIM
   EXTRACT_NCPDP_FIELD(REQUEST, 'U7', 1) AS "REQ_U7_PHARMACY_SERVICE_TYPE",                               //CLAIM
   CASE WHEN REQ_E1_PRODUCT_ID_QUALIFIER = '03' THEN REQ_D7_PRODUCT_ID END AS REQ_D703_NDC, //CLAIM

   -- NCPDP SEGMENT (PRICING)
   EXTRACT_NCPDP_FIELD(REQUEST, 'DQ', 1) AS "REQ_DQ_USUAL_AND_CUSTOMARY",                 //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'DX', 1) AS "REQ_DX_PATIENT_PAY_AMOUNT_REPORTED",         //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'D9', 1) AS "REQ_D9_INGREDIENT_COST_SUBMITTED",           //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'DN', 1) AS "REQ_DN_BASIS_OF_COST_DETERMINATION",                          //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'DC', 1) AS "REQ_DC_DISPENSING_FEE_SUBMITTED",            //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'E3', 1) AS "REQ_E3_INCENTIVE_AMOUNT_SUBMITTED",          //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'BE', 1) AS "REQ_BE_PROFESSIONAL_SERVICE_FEE_SUBMITTED",  //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'H8', 1) AS "REQ_H8_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER",             //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'H9', 1) AS "REQ_H9_OTHER_AMOUNT_CLAIMED_SUBMITTED",       //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'HA', 1) AS "REQ_HA_REGULATORY_FEE_AMOUNT_SUBMITTED",      //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'GE', 1) AS "REQ_GE_PERCENTAGE_TAX_AMOUNT_SUBMITTED",      //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'DU', 1) AS "REQ_DU_GROSS_AMOUNT_DUE",                     //PRICING
   EXTRACT_NCPDP_FIELD(REQUEST, 'JE', 1) AS "REQ_JE_PERCENTAGE_TAX_BASIS_SUBMITTED",       //PRICING

   -- NCPDP SEGMENT (FACILITY)
   EXTRACT_NCPDP_FIELD(REQUEST, '8C', 1) AS "REQ_8C_FACILITY_ID",                                         //FACILITY
   EXTRACT_NCPDP_FIELD(REQUEST, '6D', 1) AS "REQ_6D_PHARMACY_ZIP",                                        //FACILITY

   -- NCPDP SEGMENT (PRESCRIBER)
   EXTRACT_NCPDP_FIELD(REQUEST, 'EZ', 1) AS "REQ_EZ_PRESCRIBER_ID_QUALIFIER",                             //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, 'DR', 1) AS "REQ_DR_PRESCRIBER_LAST_NAME",                                //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, '2J', 1) AS "REQ_2J_PRESCRIBER_FIRST_NAME",                               //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, '2K', 1) AS "REQ_2K_PRESCRIBER_STREET_ADDRESS",                           //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, '2M', 1) AS "REQ_2M_PRESCRIBER_CITY",                                     //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, '2N', 1) AS "REQ_2N_PRESCRIBER_STATE",                                    //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, '2P', 1) AS "REQ_2P_PRESCRIBER_ZIP",                                      //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, 'PM', 1) AS "REQ_PM_PRESCRIBER_TELEPHONE_NUMBER",                         //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, 'DL', 1) AS "REQ_DL_PRIMARY_CARE_PROVIDER_ID",                            //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, '2E', 1) AS "REQ_2E_PRIMARY_CARE_PROVIDER_ID_QUALIFIER",                  //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, 'DB', 1) AS "REQ_DB_PRESCRIBER_ID",                                       //PRESCRIBER
   EXTRACT_NCPDP_FIELD(REQUEST, '4E', 1) AS "REQ_4E_PRIMARY_CARE_PROVIDER_LAST_NAME",                     //PRESCRIBER
   CASE WHEN REQ_EZ_PRESCRIBER_ID_QUALIFIER = '01' THEN REQ_DB_PRESCRIBER_ID END AS REQ_DB01_PRESCRIBER_NPI,    //PRESCRIBER

   -- NCPDP SEGMENT (COORDINATION)
   EXTRACT_NCPDP_FIELD(REQUEST, '5E', 1) AS "REQ_5E_OTHER_PAYER_REJECT_COUNT",                            //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD_JOINED(REQUEST, '6E') AS "REQ_6E_OTHER_PAYER_REJECT_CODE",              //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD(REQUEST, 'DV', 1) AS "REQ_DV_OTHER_PAYER_AMOUNT_PAID",             //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD(REQUEST, 'NP', 1) AS "REQ_NP_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_QUALIFIER", //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD(REQUEST, 'NR', 1) AS "REQ_NR_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_COUNT",     //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD_JOINED(REQUEST, 'NQ') AS "REQ_NQ_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT", //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD(REQUEST, '6C', 1) AS "REQ_6C_OTHER_PAYER_ID_QUALIFIER",                            //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD(REQUEST, 'HC', 1) AS "REQ_HC_OTHER_PAYER_AMOUNT_PAID_QUALIFIER",                   //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD(REQUEST, '4C', 1) AS "REQ_4C_COORDINATION_OF_BENEFITS_COUNT",                      //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD(REQUEST, 'NT', 1) AS "REQ_NT_OTHER_PAYER_ID_COUNT",                                //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD(REQUEST, '5C', 1) AS "REQ_5C_OTHER_PAYER_COVERAGE_TYPE",                           //COORDINATION OF BENEFITS
   EXTRACT_NCPDP_FIELD_JOINED(REQUEST, '7C') AS "REQ_7C_OTHER_PAYER_ID",                       //COORDINATION OF BENEFITS

   -- NCPDP SEGMENT (WORKERS COMPENSATION)
   EXTRACT_NCPDP_FIELD(REQUEST, 'TZ', 1) AS "REQ_TZ_GENERIC_EQUIVALENT_PRODUCT_ID_QUALIFIER",             //WORKERS COMPENSATION
   EXTRACT_NCPDP_FIELD(REQUEST, 'UA', 1) AS "REQ_UA_GENERIC_EQUIVALENT_PRODUCT_ID",                       //WORKERS COMPENSATION
   EXTRACT_NCPDP_FIELD(REQUEST, 'CF', 1) AS "REQ_CF_EMPLOYER_NAME",                                       //WORKERS COMPENSATION
   EXTRACT_NCPDP_FIELD(REQUEST, 'CG', 1) AS "REQ_CG_EMPLOYER_STREET_ADDRESS",                             //WORKERS COMPENSATION
   EXTRACT_NCPDP_FIELD(REQUEST, 'CH', 1) AS "REQ_CH_EMPLOYER_CITY",                                       //WORKERS COMPENSATION
   EXTRACT_NCPDP_FIELD(REQUEST, 'CI', 1) AS "REQ_CI_EMPLOYER_STATE",                                      //WORKERS COMPENSATION
   EXTRACT_NCPDP_FIELD(REQUEST, 'CJ', 1) AS "REQ_CJ_EMPLOYER_ZIP",                                        //WORKERS COMPENSATION
   EXTRACT_NCPDP_FIELD(REQUEST, 'CK', 1) AS "REQ_CK_EMPLOYER_TELEPHONE_NUMBER",                           //WORKERS COMPENSATION
   EXTRACT_NCPDP_FIELD(REQUEST, 'DZ', 1) AS "REQ_DZ_WORKERS_COMP_CLAIM_ID",                               //WORKERS COMPENSATION
   EXTRACT_NCPDP_FIELD(REQUEST, 'CR', 1) AS "REQ_CR_CARRIER_ID",                                          //WORKERS COMPENSATION
   EXTRACT_NCPDP_FIELD(REQUEST, 'DY', 1) AS "REQ_DY_DATE_OF_INJURY",                                      //WORKERS COMPENSATION

   -- NCPDP SEGMENT (DUR/PPS)
   EXTRACT_NCPDP_FIELD(REQUEST, 'E4', 1) AS "REQ_E4_REASON_FOR_SERVICE_CODE",                             //DUR/PPS SEGMENT
   EXTRACT_NCPDP_FIELD(REQUEST, 'E5', 1) AS "REQ_E5_PROFESSIONAL_SERVICE_CODE",                           //DUR/PPS SEGMENT

   -- NCPDP SEGMENT (COMPOUND)
   EXTRACT_NCPDP_FIELD(REQUEST, 'EC', 1) AS "REQ_EC_COMPOUND_INGREDIENT_COMPONENT_COUNT",                  //COMPOUND
   EXTRACT_NCPDP_FIELD(REQUEST, 'ED', 1) AS "REQ_ED_COMPOUND_INGREDIENT_QUANTITY",                         //COMPOUND
   EXTRACT_NCPDP_FIELD(REQUEST, 'EE', 1) AS "REQ_EE_COMPOUND_INGREDIENT_DRUG_COST",        //COMPOUND
   EXTRACT_NCPDP_FIELD(REQUEST, 'RE', 1) AS "REQ_RE_COMPOUND_PRODUCT_ID_QUALIFIER",                        //COMPOUND
   EXTRACT_NCPDP_FIELD_JOINED(REQUEST, 'TE') AS "REQ_TE_COMPOUND_PRODUCT_ID",                   //COMPOUND

   -- NCPDP SEGMENT (CLINICAL)
   EXTRACT_NCPDP_FIELD_JOINED(REQUEST, 'DO') AS "REQ_DO_DIAGNOSIS_CODE",                       //CLINICAL
   EXTRACT_NCPDP_FIELD(REQUEST, 'WE', 1) AS "REQ_WE_DIAGNOSIS_CODE_QUALIFIER",                            //CLINICAL
   EXTRACT_NCPDP_FIELD(REQUEST, 'VE', 1) AS "REQ_VE_DIAGNOSIS_CODE_COUNT",                                //CLINICAL

   -- NCPDP SEGMENT (FACILITY)
   EXTRACT_NCPDP_FIELD(REQUEST, '5J', 1) AS "REQ_5J_PHARMACY_CITY",                                       //FACILITY
   EXTRACT_NCPDP_FIELD(REQUEST, '3Q', 1) AS "REQ_3Q_PHARMACY_NAME",                                       //FACILITY
   EXTRACT_NCPDP_FIELD(REQUEST, '3U', 1) AS "REQ_3U_PHARMACY_STREET_ADDRESS",                             //FACILITY
   EXTRACT_NCPDP_FIELD(REQUEST, '3V', 1) AS "REQ_3V_PHARMACY_STATE",                                      //FACILITY

   -- NCPDP SEGMENT (NARRATIVE)
   EXTRACT_NCPDP_FIELD(REQUEST, 'BM', 1) AS "REQ_BM_NARRATIVE_MESSAGE",                                   //NARRATIVE

   ----------------------------------------------------------------------------------------------------
   --[RESPONSE FIELDS]
   ----------------------------------------------------------------------------------------------------

   -- NCPDP SEGMENT (RESPONSE MESSAGE)
   EXTRACT_NCPDP_FIELD(RESPONSE, 'F4', 1) AS "RES_F4_MESSAGE",                                             //RESPONSE MESSAGE

   -- NCPDP SEGMENT (RESPONSE INSURANCE)
   EXTRACT_NCPDP_FIELD(RESPONSE, 'C1', 1) AS "RES_C1_GROUP_ID",                                            //RESPONSE INSURANCE
   EXTRACT_NCPDP_FIELD(RESPONSE, '2F', 1) AS "RES_2F_NETWORK_REIMBURSEMENT_ID",                            //RESPONSE INSURANCE
   EXTRACT_NCPDP_FIELD(RESPONSE, 'J8', 1) AS "RES_J8_PAYER_ID",                                            //RESPONSE INSURANCE
   EXTRACT_NCPDP_FIELD(RESPONSE, 'J7', 1) AS "RES_J7_PAYER_ID_QUALIFIER",                                  //RESPONSE INSURANCE
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FO', 1) AS "RES_FO_PLAN_ID",                                             //RESPONSE INSURANCE

   -- NCPDP SEGMENT (RESPONSE STATUS)
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FA', 1) AS "RES_FA_REJECT_COUNT",                                           //RESPONSE STATUS
   EXTRACT_NCPDP_FIELD(RESPONSE, 'F3', 1) AS "RES_F3_AUTHORIZATION_NUMBER",                                   //RESPONSE STATUS
   EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'UH', ',') AS "RES_UH_ADDITIONAL_MESSAGE_INFORMATION_QUALIFIER",   //RESPONSE STATUS
   EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'UG', ',') AS "RES_UG_ADDITIONAL_MESSAGE_INFORMATION_CONTINUITY",  //RESPONSE STATUS
   EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, '6F', ',') AS "RES_6F_APPROVED_MESSAGE_CODE",                      //RESPONSE STATUS
   EXTRACT_NCPDP_FIELD(RESPONSE, 'UF', 1) AS "RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT",                   //RESPONSE STATUS
   EXTRACT_NCPDP_FIELD_JOINED(RESPONSE, 'FB') AS "RES_FB_REJECT_CODE",                             //RESPONSE STATUS
   EXTRACT_NCPDP_FIELD(RESPONSE, 'AN', 1) AS "RES_AN_TRANSACTION_RESPONSE_STATUS",                            //RESPONSE STATUS
   STRTOK_TO_ARRAY(EXTRACT_NCPDP_FIELD_JOINED_BY(RESPONSE, 'FQ', '~'), '~') RES_FQ_ADDITIONAL_MESSAGE_INFORMATION,



   -- NCPDP SEGMENT (RESPONSE PRICING)
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FH', 1) AS "RES_FH_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE",               //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'AV', 1) AS "RES_AV_PERCENTAGE_TAX_EXEMPT_INDICATOR",                                     //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'F5', 1) AS "RES_F5_PATIENT_PAY_AMOUNT",                                  //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'F6', 1) AS "RES_F6_INGREDIENT_COST_PAID",                                //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'F7', 1) AS "RES_F7_DISPENSING_FEE_PAID",                                 //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FL', 1) AS "RES_FL_INCENTIVE_AMOUNT_PAID",                               //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'J1', 1) AS "RES_J1_PROFESSIONAL_SERVICE_FEE_PAID",                       //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'J5', 1) AS "RES_J5_OTHER_PAYER_AMOUNT_RECOGNIZED",                       //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'AW', 1) AS "RES_AW_REGULATORY_FEE_AMOUNT_PAID",                          //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'AX', 1) AS "RES_AX_PERCENTAGE_TAX_AMOUNT_PAID",                          //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'F9', 1) AS "RES_F9_TOTAL_AMOUNT_PAID",                                   //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FC', 1) AS "RES_FC_ACCUMULATED_DEDUCTIBLE_AMOUNT",                       //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FD', 1) AS "RES_FD_REMAINING_DEDUCTIBLE_AMOUNT",                         //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FE', 1) AS "RES_FE_REMAINING_BENEFIT_AMOUNT",                            //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FI', 1) AS "RES_FI_AMOUNT_OF_COPAY",                                     //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FK', 1) AS "RES_FK_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM",           //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FM', 1) AS "RES_FM_BASIS_OF_REIMBURSEMENT_DETERMINATION",                                //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'J3', 1) AS "RES_J3_OTHER_AMOUNT_PAID_QUALIFIER",                                         //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'FJ', 1) AS "RES_FJ_AMOUNT_ATTRIBUTED_TO_PRODUCT_SELECTION",              //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD_JOINED(RESPONSE, 'J4') AS "RES_J4_OTHER_AMOUNT_PAID",             //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'UM', 1) AS "RES_UM_AMOUNT_ATTRIBUTED_TO_NON_PREFERRED_SELECTION",        //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'UK', 1) AS "RES_UK_AMOUNT_ATTRIBUTED_TO_BRAND_DRUG",                     //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'UJ', 1) AS "RES_UJ_AMOUNT_ATTRIBUTED_TO_PROVIDER_NETWORK_SELECTION",     //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'UC', 1) AS "RES_UC_SPENDING_ACCOUNT_AMOUNT_REMAINING",                   //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'U9', 1) AS "RES_U9_DISPENSING_FEE_REIMBURSABLE_AMOUNT",                  //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'U8', 1) AS "RES_U8_INGREDIENT_COST_REIMBURSABLE_AMOUNT",                 //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'J2', 1) AS "RES_J2_OTHER_AMOUNT_PAID_COUNT",                        //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'NZ', 1) AS "RES_NZ_AMOUNT_ATTRIBUTED_TO_PROCESSOR_FEE",                  //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'EQ', 1) AS "RES_EQ_PATIENT_PERCENTAGE_TAX_AMOUNT",                       //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'AZ', 1) AS "RES_AZ_PERCENTAGE_TAX_BASIS_PAID",                           //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, '4V', 1) AS "RES_4V_BASIS_OF_CALCULATION_COINSURANCE",                                    //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, '4U', 1) AS "RES_4U_AMOUNT_OF_COINSURANCE",                               //RESPONSE PRICING
   EXTRACT_NCPDP_FIELD(RESPONSE, 'AY', 1) AS "RES_AY_PERCENTAGE_TAX_RATE_PAID",                            //RESPONSE PRICING

   -- NCPDP SEGMENT (RESPONSE PRIOR AUTHORIZATION SEGMENT)
   EXTRACT_NCPDP_FIELD(RESPONSE, 'PY', 1) AS "RES_PY_PRIOR_AUTHORIZATION_ID_ASSIGNED"                     //RESPONSE PRIOR AUTHORIZATION SEGMENT

   FROM CLAIMS
)

-- Formated View Of Raw Claim
,CLAIMS_VIEW AS (
    SELECT
       ----------------------------------------------------------------------------------------------------
       --[CLAIMS HEADER PAYLOAD FIELDS]
       ----------------------------------------------------------------------------------------------------
       HASH_KEY,
       CPH_TRANSMISSION_ID,
       RECORD_ID,
       CPH_INGESTED_TIMESTAMP,
       CPH_ROUTING_ADDRESS,
       CPH_ORIGIN,
       CPH_RETURNED_TIMESTAMP,
       CPH_CREATED_TIMESTAMP,
       CPH_A4_PCN,
       CPH_B107_SERVICE_PROVIDER_NCPDP,
       CPH_B101_SERVICE_PROVIDER_NPI,
       CPH_AN_TRANSACTION_RESPONSE_STATUS,
       CPH_A1_IIN,

       ----------------------------------------------------------------------------------------------------
       --[REQUEST FIELDS]
       ----------------------------------------------------------------------------------------------------

       -- NCPDP SEGMENT (TRANSACTION HEADER)
       REQ_A1_IIN,   //HEADER [Position: 1–6   = BIN (A1, 6 chars)]
       CPH_A2_VERSION,   //HEADER [Position: 7–8   = Version (A2, 2 chars)]
       CPH_A3_TRANSACTION_CODE,   //HEADER [Position: 9–10  = Transaction Code (A3, 2 chars)]
       REQ_A4_PCN,   //HEADER [Position: 11–20 = Processor Control (A4, 10 chars)]
       CPH_A9_TRANSACTION_COUNT,   //HEADER [Position: 21    = Transaction Count (A9, 1 char)]
       REQ_B2_SERVICE_PROVIDER_ID_QUALIFIER,   //HEADER [Position: 22–23 = Service Provider Qualifier (B2, 2 chars)]
       REQ_B1_SERVICE_PROVIDER_ID,   //HEADER [Position: 24–38 = Service Provider ID (B1, 15 chars)]
       REQ_D1_DATE_OF_SERVICE,   //HEADER [Position: 39–46 = Date of Service (D1, 8 chars)]
       REQ_AK_SOFTWARE_VENDOR_ID,   //HEADER [Position: 47–56 = Vendor/Cert ID (AK, 10 chars)]

       -- NCPDP SEGMENT (INSURANCE)
       REQ_C2_CARDHOLDER_ID,                                       //INSURANCE
       REQ_C3_PERSON_CODE,                                         //INSURANCE
       REQ_C6_PATIENT_RELATIONSHIP_CODE,                           //INSURANCE
       REQ_CC_CARDHOLDER_FIRST_NAME,                               //INSURANCE
       REQ_CD_CARDHOLDER_LAST_NAME,                                //INSURANCE
       REQ_2A_MEDIGAP_ID,                                          //INSURANCE
       REQ_C1_GROUP_ID,                                            //INSURANCE
       REQ_C9_ELIGIBILITY_CLARIFICATION_CODE,                      //INSURANCE
       REQ_N5_MEDICAID_ID_NUMBER,                                  //INSURANCE

       -- NCPDP SEGMENT (PATIENT)
       REQ_CA_PATIENT_FIRST_NAME,                                  //PATIENT
       REQ_CB_PATIENT_LAST_NAME,                                   //PATIENT
       REQ_C4_PATIENT_DATE_OF_BIRTH,                               //PATIENT
       REQ_C5_PATIENT_GENDER_CODE,                                 //PATIENT
       REQ_CY_PATIENT_ID,                                          //PATIENT
       REQ_CX_PATIENT_ID_QUALIFIER,                                //PATIENT
       REQ_CM_PATIENT_STREET_ADDRESS,                              //PATIENT
       REQ_CN_PATIENT_CITY,                                        //PATIENT
       REQ_CO_PATIENT_STATE,                                       //PATIENT
       REQ_CP_PATIENT_ZIP,                                         //PATIENT
       REQ_C7_PLACE_OF_SERVICE,                                    //PATIENT
       REQ_4X_PATIENT_RESIDENCE,                                   //PATIENT
       REQ_CQ_PATIENT_TELEPHONE_NUMBER,                            //PATIENT
       REQ_2C_PREGNANCY_INDICATOR,                                 //PATIENT
       REQ_CZ_EMPLOYER_ID,                                         //PATIENT
       REQ_HN_PATIENT_EMAIL_ADDRESS,                               //PATIENT

       --=[GROUPED SEGMENTS]=--

       -- NCPDP SEGMENT (CLAIM)
       REQ_28_UNIT_OF_MEASURE,                                                                      //CLAIM
       REQ_C8_OTHER_COVERAGE_CODE,                                                                  //CLAIM
       SUBSTR(LTRIM(REQ_D2_RX_NUMBER, '0'),0,12) AS REQ_D2_RX_NUMBER,                               //CLAIM
       REQ_D3_FILL_NUMBER,                                                                          //CLAIM
       TRY_TO_NUMBER(REQ_D5_DAYS_SUPPLY) AS REQ_D5_DAYS_SUPPLY,                                      //CLAIM
       REQ_D6_COMPOUND_CODE,                                                                        //CLAIM
       TRY_TO_NUMBER(REQ_DF_NUMBER_OF_REFILLS_AUTHORIZED) AS REQ_DF_NUMBER_OF_REFILLS_AUTHORIZED,    //CLAIM
       REQ_DI_LEVEL_OF_SERVICE,                                                                     //CLAIM
       REQ_DT_SPECIAL_PACKAGING_INDICATOR,                                                          //CLAIM
       REQ_DJ_PRESCRIPTION_ORIGIN_CODE,                                                             //CLAIM
       REQ_DE_DATE_PRESCRIPTION_WRITTEN,                                                            //CLAIM
       REQ_EA_ORIGINALLY_PRESCRIBED_PRODUCT_CODE,                                                   //CLAIM
       REQ_EJ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER,                                           //CLAIM
       REQ_EN_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER,                                             //CLAIM
       REQ_EP_ASSOCIATED_PRESCRIPTION_DATE,                                                         //CLAIM
       REQ_EM_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER,                                              //CLAIM
       REQ_EU_PRIOR_AUTHORIZATION_TYPE_CODE,                                                        //CLAIM
       REQ_D7_PRODUCT_ID,                                                                           //CLAIM
       REQ_E1_PRODUCT_ID_QUALIFIER,                                                                 //CLAIM
       REQ_D8_DAW_PRODUCT_SELECTION_CODE,                                                           //CLAIM
       REQ_DK_SUBMISSION_CLARIFICATION_CODE,                                                        //CLAIM
       TRY_TO_NUMBER(REQ_E7_QUANTITY_DISPENSED) / 1000 AS REQ_E7_QUANTITY_DISPENSED,                //CLAIM
       REQ_EK_SCHEDULED_PRESCRIPTION_ID_NUMBER,                                                     //CLAIM
       REQ_K5_TRANSACTION_REFERENCE_NUMBER,                                                         //CLAIM
       REQ_HD_DISPENSING_STATUS,                                                                    //CLAIM
       REQ_U7_PHARMACY_SERVICE_TYPE,                                                                //CLAIM
       CASE WHEN REQ_E1_PRODUCT_ID_QUALIFIER = '03' THEN REQ_D7_PRODUCT_ID END AS REQ_D703_NDC,     //CLAIM

       -- NCPDP SEGMENT (PRICING)
       PARSE_NCPDP_CURRENCY(REQ_DQ_USUAL_AND_CUSTOMARY) AS REQ_DQ_USUAL_AND_CUSTOMARY,                 //PRICING
       PARSE_NCPDP_CURRENCY(REQ_DX_PATIENT_PAY_AMOUNT_REPORTED) AS REQ_DX_PATIENT_PAY_AMOUNT_REPORTED,         //PRICING
       PARSE_NCPDP_CURRENCY(REQ_D9_INGREDIENT_COST_SUBMITTED) AS REQ_D9_INGREDIENT_COST_SUBMITTED,           //PRICING
       REQ_DN_BASIS_OF_COST_DETERMINATION,                          //PRICING
       PARSE_NCPDP_CURRENCY(REQ_DC_DISPENSING_FEE_SUBMITTED) AS REQ_DC_DISPENSING_FEE_SUBMITTED,            //PRICING
       PARSE_NCPDP_CURRENCY(REQ_E3_INCENTIVE_AMOUNT_SUBMITTED) AS REQ_E3_INCENTIVE_AMOUNT_SUBMITTED,          //PRICING
       PARSE_NCPDP_CURRENCY(REQ_BE_PROFESSIONAL_SERVICE_FEE_SUBMITTED) AS REQ_BE_PROFESSIONAL_SERVICE_FEE_SUBMITTED,  //PRICING
       REQ_H8_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER,             //PRICING
       PARSE_NCPDP_CURRENCY(REQ_H9_OTHER_AMOUNT_CLAIMED_SUBMITTED) AS REQ_H9_OTHER_AMOUNT_CLAIMED_SUBMITTED,       //PRICING
       PARSE_NCPDP_CURRENCY(REQ_HA_REGULATORY_FEE_AMOUNT_SUBMITTED) AS REQ_HA_REGULATORY_FEE_AMOUNT_SUBMITTED,      //PRICING
       PARSE_NCPDP_CURRENCY(REQ_GE_PERCENTAGE_TAX_AMOUNT_SUBMITTED) AS REQ_GE_PERCENTAGE_TAX_AMOUNT_SUBMITTED,      //PRICING
       PARSE_NCPDP_CURRENCY(REQ_DU_GROSS_AMOUNT_DUE) AS REQ_DU_GROSS_AMOUNT_DUE,                     //PRICING
       PARSE_NCPDP_CURRENCY(REQ_JE_PERCENTAGE_TAX_BASIS_SUBMITTED) AS REQ_JE_PERCENTAGE_TAX_BASIS_SUBMITTED,       //PRICING

       -- NCPDP SEGMENT (FACILITY)
       REQ_8C_FACILITY_ID,                                         //FACILITY
       REQ_6D_PHARMACY_ZIP,                                        //FACILITY

       -- NCPDP SEGMENT (PRESCRIBER)
       REQ_EZ_PRESCRIBER_ID_QUALIFIER,                             //PRESCRIBER
       REQ_DR_PRESCRIBER_LAST_NAME,                                //PRESCRIBER
       REQ_2J_PRESCRIBER_FIRST_NAME,                               //PRESCRIBER
       REQ_2K_PRESCRIBER_STREET_ADDRESS,                           //PRESCRIBER
       REQ_2M_PRESCRIBER_CITY,                                     //PRESCRIBER
       REQ_2N_PRESCRIBER_STATE,                                    //PRESCRIBER
       REQ_2P_PRESCRIBER_ZIP,                                      //PRESCRIBER
       REQ_PM_PRESCRIBER_TELEPHONE_NUMBER,                         //PRESCRIBER
       REQ_DL_PRIMARY_CARE_PROVIDER_ID,                            //PRESCRIBER
       REQ_2E_PRIMARY_CARE_PROVIDER_ID_QUALIFIER,                  //PRESCRIBER
       REQ_DB_PRESCRIBER_ID,                                       //PRESCRIBER
       REQ_4E_PRIMARY_CARE_PROVIDER_LAST_NAME,                     //PRESCRIBER
       CASE WHEN REQ_EZ_PRESCRIBER_ID_QUALIFIER = '01' THEN REQ_DB_PRESCRIBER_ID END AS REQ_DB01_PRESCRIBER_NPI,    //PRESCRIBER

       -- NCPDP SEGMENT (COORDINATION)
       REQ_5E_OTHER_PAYER_REJECT_COUNT,                            //COORDINATION OF BENEFITS
       STRTOK_TO_ARRAY(REQ_6E_OTHER_PAYER_REJECT_CODE) AS REQ_6E_OTHER_PAYER_REJECT_CODE,              //COORDINATION OF BENEFITS
       PARSE_NCPDP_CURRENCY(REQ_DV_OTHER_PAYER_AMOUNT_PAID) AS REQ_DV_OTHER_PAYER_AMOUNT_PAID,             //COORDINATION OF BENEFITS
       REQ_NP_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_QUALIFIER, //COORDINATION OF BENEFITS
       REQ_NR_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT_COUNT,     //COORDINATION OF BENEFITS
       TRANSFORM(STRTOK_TO_ARRAY(REQ_NQ_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT), x -> PARSE_NCPDP_CURRENCY(x)) AS REQ_NQ_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT, //COORDINATION OF BENEFITS
       REQ_6C_OTHER_PAYER_ID_QUALIFIER,                            //COORDINATION OF BENEFITS
       REQ_HC_OTHER_PAYER_AMOUNT_PAID_QUALIFIER,                   //COORDINATION OF BENEFITS
       REQ_4C_COORDINATION_OF_BENEFITS_COUNT,                      //COORDINATION OF BENEFITS
       REQ_NT_OTHER_PAYER_ID_COUNT,                                //COORDINATION OF BENEFITS
       REQ_5C_OTHER_PAYER_COVERAGE_TYPE,                           //COORDINATION OF BENEFITS
       STRTOK_TO_ARRAY(REQ_7C_OTHER_PAYER_ID) AS REQ_7C_OTHER_PAYER_ID,                       //COORDINATION OF BENEFITS

       -- NCPDP SEGMENT (WORKERS COMPENSATION)
       REQ_TZ_GENERIC_EQUIVALENT_PRODUCT_ID_QUALIFIER,             //WORKERS COMPENSATION
       REQ_UA_GENERIC_EQUIVALENT_PRODUCT_ID,                       //WORKERS COMPENSATION
       REQ_CF_EMPLOYER_NAME,                                       //WORKERS COMPENSATION
       REQ_CG_EMPLOYER_STREET_ADDRESS,                             //WORKERS COMPENSATION
       REQ_CH_EMPLOYER_CITY,                                       //WORKERS COMPENSATION
       REQ_CI_EMPLOYER_STATE,                                      //WORKERS COMPENSATION
       REQ_CJ_EMPLOYER_ZIP,                                        //WORKERS COMPENSATION
       REQ_CK_EMPLOYER_TELEPHONE_NUMBER,                           //WORKERS COMPENSATION
       REQ_DZ_WORKERS_COMP_CLAIM_ID,                               //WORKERS COMPENSATION
       REQ_CR_CARRIER_ID,                                          //WORKERS COMPENSATION
       REQ_DY_DATE_OF_INJURY,                                      //WORKERS COMPENSATION

       -- NCPDP SEGMENT (DUR/PPS)
       REQ_E4_REASON_FOR_SERVICE_CODE,                             //DUR/PPS SEGMENT
       REQ_E5_PROFESSIONAL_SERVICE_CODE,                           //DUR/PPS SEGMENT

       -- NCPDP SEGMENT (COMPOUND)
       REQ_EC_COMPOUND_INGREDIENT_COMPONENT_COUNT,                  //COMPOUND
       REQ_ED_COMPOUND_INGREDIENT_QUANTITY,                         //COMPOUND
       PARSE_NCPDP_CURRENCY(REQ_EE_COMPOUND_INGREDIENT_DRUG_COST) AS REQ_EE_COMPOUND_INGREDIENT_DRUG_COST,        //COMPOUND
       REQ_RE_COMPOUND_PRODUCT_ID_QUALIFIER,                        //COMPOUND
       STRTOK_TO_ARRAY(REQ_TE_COMPOUND_PRODUCT_ID) AS REQ_TE_COMPOUND_PRODUCT_ID,                   //COMPOUND

       -- NCPDP SEGMENT (CLINICAL)
       STRTOK_TO_ARRAY(REQ_DO_DIAGNOSIS_CODE) AS REQ_DO_DIAGNOSIS_CODE,                       //CLINICAL
       REQ_WE_DIAGNOSIS_CODE_QUALIFIER,                            //CLINICAL
       REQ_VE_DIAGNOSIS_CODE_COUNT,                                //CLINICAL

       -- NCPDP SEGMENT (FACILITY)
       REQ_5J_PHARMACY_CITY,                                       //FACILITY
       REQ_3Q_PHARMACY_NAME,                                       //FACILITY
       REQ_3U_PHARMACY_STREET_ADDRESS,                             //FACILITY
       REQ_3V_PHARMACY_STATE,                                      //FACILITY

       -- NCPDP SEGMENT (NARRATIVE)
       REQ_BM_NARRATIVE_MESSAGE,                                   //NARRATIVE

       ----------------------------------------------------------------------------------------------------
       --[RESPONSE FIELDS]
       ----------------------------------------------------------------------------------------------------


       -- NCPDP SEGMENT (RESPONSE MESSAGE)
       RES_F4_MESSAGE,                                             //RESPONSE MESSAGE

       -- NCPDP SEGMENT (RESPONSE INSURANCE)
       RES_C1_GROUP_ID,                                            //RESPONSE INSURANCE
       RES_2F_NETWORK_REIMBURSEMENT_ID,                            //RESPONSE INSURANCE
       RES_J8_PAYER_ID,                                            //RESPONSE INSURANCE
       RES_J7_PAYER_ID_QUALIFIER,                                  //RESPONSE INSURANCE
       RES_FO_PLAN_ID,                                             //RESPONSE INSURANCE

       -- NCPDP SEGMENT (RESPONSE STATUS)
       RES_FA_REJECT_COUNT,                                           //RESPONSE STATUS
       RES_F3_AUTHORIZATION_NUMBER,                                   //RESPONSE STATUS
       RES_UH_ADDITIONAL_MESSAGE_INFORMATION_QUALIFIER,   //RESPONSE STATUS
       RES_UG_ADDITIONAL_MESSAGE_INFORMATION_CONTINUITY,  //RESPONSE STATUS
       RES_6F_APPROVED_MESSAGE_CODE,                      //RESPONSE STATUS
       RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT,                   //RESPONSE STATUS
       STRTOK_TO_ARRAY(RES_FB_REJECT_CODE) AS RES_FB_REJECT_CODE,                             //RESPONSE STATUS
       RES_AN_TRANSACTION_RESPONSE_STATUS,                            //RESPONSE STATUS
       RES_FQ_ADDITIONAL_MESSAGE_INFORMATION,

       -- NCPDP SEGMENT (RESPONSE PRICING)
       PARSE_NCPDP_CURRENCY(RES_FH_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE) AS RES_FH_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE,               //RESPONSE PRICING
       RES_AV_PERCENTAGE_TAX_EXEMPT_INDICATOR,                                     //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_F5_PATIENT_PAY_AMOUNT) AS RES_F5_PATIENT_PAY_AMOUNT,                                  //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_F6_INGREDIENT_COST_PAID) AS RES_F6_INGREDIENT_COST_PAID,                                //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_F7_DISPENSING_FEE_PAID) AS RES_F7_DISPENSING_FEE_PAID,                                 //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_FL_INCENTIVE_AMOUNT_PAID) AS RES_FL_INCENTIVE_AMOUNT_PAID,                               //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_J1_PROFESSIONAL_SERVICE_FEE_PAID) AS RES_J1_PROFESSIONAL_SERVICE_FEE_PAID,                       //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_J5_OTHER_PAYER_AMOUNT_RECOGNIZED) AS RES_J5_OTHER_PAYER_AMOUNT_RECOGNIZED,                       //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_AW_REGULATORY_FEE_AMOUNT_PAID) AS RES_AW_REGULATORY_FEE_AMOUNT_PAID,                          //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_AX_PERCENTAGE_TAX_AMOUNT_PAID) AS RES_AX_PERCENTAGE_TAX_AMOUNT_PAID,                          //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_F9_TOTAL_AMOUNT_PAID) AS RES_F9_TOTAL_AMOUNT_PAID,                                   //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_FC_ACCUMULATED_DEDUCTIBLE_AMOUNT) AS RES_FC_ACCUMULATED_DEDUCTIBLE_AMOUNT,                       //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_FD_REMAINING_DEDUCTIBLE_AMOUNT) AS RES_FD_REMAINING_DEDUCTIBLE_AMOUNT,                         //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_FE_REMAINING_BENEFIT_AMOUNT) AS RES_FE_REMAINING_BENEFIT_AMOUNT,                            //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_FI_AMOUNT_OF_COPAY) AS RES_FI_AMOUNT_OF_COPAY,                                     //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_FK_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM) AS RES_FK_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM,           //RESPONSE PRICING
       RES_FM_BASIS_OF_REIMBURSEMENT_DETERMINATION,                                //RESPONSE PRICING
       RES_J3_OTHER_AMOUNT_PAID_QUALIFIER,                                         //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_FJ_AMOUNT_ATTRIBUTED_TO_PRODUCT_SELECTION) AS RES_FJ_AMOUNT_ATTRIBUTED_TO_PRODUCT_SELECTION,              //RESPONSE PRICING
       TRANSFORM(STRTOK_TO_ARRAY(RES_J4_OTHER_AMOUNT_PAID), x -> PARSE_NCPDP_CURRENCY(x)) AS RES_J4_OTHER_AMOUNT_PAID,             //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_UM_AMOUNT_ATTRIBUTED_TO_NON_PREFERRED_SELECTION) AS RES_UM_AMOUNT_ATTRIBUTED_TO_NON_PREFERRED_SELECTION,        //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_UK_AMOUNT_ATTRIBUTED_TO_BRAND_DRUG) AS RES_UK_AMOUNT_ATTRIBUTED_TO_BRAND_DRUG,                     //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_UJ_AMOUNT_ATTRIBUTED_TO_PROVIDER_NETWORK_SELECTION) AS RES_UJ_AMOUNT_ATTRIBUTED_TO_PROVIDER_NETWORK_SELECTION,     //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_UC_SPENDING_ACCOUNT_AMOUNT_REMAINING) AS RES_UC_SPENDING_ACCOUNT_AMOUNT_REMAINING,                   //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_U9_DISPENSING_FEE_REIMBURSABLE_AMOUNT) AS RES_U9_DISPENSING_FEE_REIMBURSABLE_AMOUNT,                  //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_U8_INGREDIENT_COST_REIMBURSABLE_AMOUNT) AS RES_U8_INGREDIENT_COST_REIMBURSABLE_AMOUNT,                 //RESPONSE PRICING
       RES_J2_OTHER_AMOUNT_PAID_COUNT,                        //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_NZ_AMOUNT_ATTRIBUTED_TO_PROCESSOR_FEE) AS RES_NZ_AMOUNT_ATTRIBUTED_TO_PROCESSOR_FEE,                  //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_EQ_PATIENT_PERCENTAGE_TAX_AMOUNT) AS RES_EQ_PATIENT_PERCENTAGE_TAX_AMOUNT,                       //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_AZ_PERCENTAGE_TAX_BASIS_PAID) AS RES_AZ_PERCENTAGE_TAX_BASIS_PAID,                           //RESPONSE PRICING
       RES_4V_BASIS_OF_CALCULATION_COINSURANCE,                                    //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_4U_AMOUNT_OF_COINSURANCE) AS RES_4U_AMOUNT_OF_COINSURANCE,                               //RESPONSE PRICING
       PARSE_NCPDP_CURRENCY(RES_AY_PERCENTAGE_TAX_RATE_PAID) AS RES_AY_PERCENTAGE_TAX_RATE_PAID,                            //RESPONSE PRICING

        -- NCPDP SEGMENT (RESPONSE PRIOR AUTHORIZATION SEGMENT)
       RES_PY_PRIOR_AUTHORIZATION_ID_ASSIGNED                     //RESPONSE PRIOR AUTHORIZATION SEGMENT
    FROM RAW_CLAIMS
)

SELECT
    c.DATA
--     ,c.RESPONSE
    ,r.RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT
    ,r.RES_FQ_ADDITIONAL_MESSAGE_INFORMATION
--    	,REQ_7C_OTHER_PAYER_ID
-- 	,REQ_NQ_OTHER_PAYER_PATIENT_RESPONSIBILITY_AMOUNT
-- 	,REQ_DO_DIAGNOSIS_CODE
-- 	,REQ_6E_OTHER_PAYER_REJECT_CODE
-- 	,REQ_TE_COMPOUND_PRODUCT_ID
-- 	,RES_J4_OTHER_AMOUNT_PAID
-- 	,RES_FB_REJECT_CODE

-- FROM CLAIMS_VIEW;
FROM RAW_CLAIMS r
JOIN CLAIMS c
    on r.HASH_KEY = c.HASH_KEY
WHERE RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT IS NOT NULL
ORDER BY TRY_TO_NUMBER(RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT) DESC
;