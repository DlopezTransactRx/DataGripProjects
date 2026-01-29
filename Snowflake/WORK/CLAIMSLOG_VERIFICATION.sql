USE DATABASE CPE_PROD;
USE SCHEMA DATA;
USE WAREHOUSE WH_RESEARCH;

CREATE TEMPORARY TABLE SAMPLE_DATA AS
-- Verification Query
WITH targets AS (
    SELECT RECORD_ID FROM CPE_CLAIMS_LOG SAMPLE (100 ROWS)
),
claim_log AS (
  SELECT l.*
  FROM CPE_PROD.DATA.CPE_CLAIMS_LOG l
  JOIN targets t ON t.RECORD_ID = l.RECORD_ID
),
claim_req AS (
  SELECT q.*
  FROM CPE_PROD.DATA.CPE_CLAIM_REQUESTS q
  JOIN targets t ON t.RECORD_ID = q.RECORD_ID
),
claim_res AS (
  SELECT s.*
  FROM CPE_PROD.DATA.CPE_CLAIM_RESPONSES s
  JOIN targets t ON t.RECORD_ID = s.RECORD_ID
),
combined AS (SELECT
     -- ========================================================================
     -- KEY IDENTIFIERS
     -- ========================================================================
     log.RECORD_ID,
     log.CPH_TRANSMISSION_ID                               AS LOG_TRANSMISSION_ID,
     req.TRANSMISSION_ID                                   AS REQ_TRANSMISSION_ID,
     res.TRANSMISSION_ID                                   AS RES_TRANSMISSION_ID,

--      -- ========================================================================
--      -- HEADER SEGMENT (REQUEST)
--      -- ========================================================================
--      log.REQ_A1_IIN                                        AS LOG_REQ_BIN,
--      req.BIN                                               AS REQ_BIN,
--
--      log.REQ_A4_PCN                                        AS LOG_REQ_PCN,
--      req.PCN                                               AS REQ_PCN,
--
--      log.REQ_B1_SERVICE_PROVIDER_ID                        AS LOG_REQ_SERVICE_PROVIDER_ID,
--      req.SERVICE_PROVIDER_ID                               AS REQ_SERVICE_PROVIDER_ID,
--
--      log.REQ_B2_SERVICE_PROVIDER_ID_QUALIFIER              AS LOG_REQ_SERVICE_PROVIDER_ID_QUALIFIER,
--      req.SERVICE_PROVIDER_ID_QUALIFIER                     AS REQ_SERVICE_PROVIDER_ID_QUALIFIER,
--
--      log.REQ_D1_DATE_OF_SERVICE                            AS LOG_REQ_DATE_OF_SERVICE,
--      req.DATE_OF_SERVICE                                   AS REQ_DATE_OF_SERVICE,
--
--      -- ========================================================================
--      -- INSURANCE SEGMENT (REQUEST)
--      -- ========================================================================
--      log.REQ_C1_GROUP_ID                                   AS LOG_REQ_GROUP_ID,
--      req.GROUP_ID                                          AS REQ_GROUP_ID,
--
--      log.REQ_C2_CARDHOLDER_ID                              AS LOG_REQ_CARDHOLDER_ID,
--      req.CARDHOLDER_ID                                     AS REQ_CARDHOLDER_ID,
--
--      log.REQ_C3_PERSON_CODE                                AS LOG_REQ_PERSON_CODE,
--      req.PERSON_CODE                                       AS REQ_PERSON_CODE,
--
--      log.REQ_C6_PATIENT_RELATIONSHIP_CODE                  AS LOG_REQ_PATIENT_RELATIONSHIP_CODE,
--      req.PATIENT_RELATIONSHIP_CODE                         AS REQ_PATIENT_RELATIONSHIP_CODE,
--
--      log.REQ_CC_CARDHOLDER_FIRST_NAME                      AS LOG_REQ_CARDHOLDER_FIRST_NAME,
--      req.CARDHOLDER_FIRST_NAME                             AS REQ_CARDHOLDER_FIRST_NAME,
--
--      log.REQ_CD_CARDHOLDER_LAST_NAME                       AS LOG_REQ_CARDHOLDER_LAST_NAME,
--      req.CARDHOLDER_LAST_NAME                              AS REQ_CARDHOLDER_LAST_NAME,
--
--      -- ========================================================================
--      -- PATIENT SEGMENT (REQUEST)
--      -- ========================================================================
--      log.REQ_C4_PATIENT_DATE_OF_BIRTH                      AS LOG_REQ_PATIENT_DOB,
--      req.PATIENT_DOB                                       AS REQ_PATIENT_DOB,
--
--      log.REQ_C5_PATIENT_GENDER_CODE                        AS LOG_REQ_PATIENT_GENDER,
--      req.PATIENT_GENDER                                    AS REQ_PATIENT_GENDER,
--
--      log.REQ_C7_PLACE_OF_SERVICE                           AS LOG_REQ_PLACE_OF_SERVICE,
--      req.PLACE_OF_SERVICE                                  AS REQ_PLACE_OF_SERVICE,
--
--      log.REQ_CA_PATIENT_FIRST_NAME                         AS LOG_REQ_PATIENT_FIRST_NAME,
--      req.PATIENT_FIRST_NAME                                AS REQ_PATIENT_FIRST_NAME,
--
--      log.REQ_CB_PATIENT_LAST_NAME                          AS LOG_REQ_PATIENT_LAST_NAME,
--      req.PATIENT_LAST_NAME                                 AS REQ_PATIENT_LAST_NAME,
--
--      log.REQ_CM_PATIENT_STREET_ADDRESS                     AS LOG_REQ_PATIENT_ADDRESS,
--      req.PATIENT_ADDRESS                                   AS REQ_PATIENT_ADDRESS,
--
--      log.REQ_CN_PATIENT_CITY                               AS LOG_REQ_PATIENT_CITY,
--      req.PATIENT_CITY                                      AS REQ_PATIENT_CITY,
--
--      log.REQ_CO_PATIENT_STATE                              AS LOG_REQ_PATIENT_STATE,
--      req.PATIENT_STATE                                     AS REQ_PATIENT_STATE,
--
--      log.REQ_CP_PATIENT_ZIP                                AS LOG_REQ_PATIENT_ZIP,
--      req.PATIENT_ZIP                                       AS REQ_PATIENT_ZIP,
--
--      log.REQ_CQ_PATIENT_TELEPHONE_NUMBER                   AS LOG_REQ_PATIENT_PHONE_NUMBER,
--      req.PATIENT_PHONE_NUMBER                              AS REQ_PATIENT_PHONE_NUMBER,
--
--      log.REQ_CX_PATIENT_ID_QUALIFIER                       AS LOG_REQ_PATIENT_ID_QUALIFIER,
--      req.PATIENT_ID_QUALIFIER                              AS REQ_PATIENT_ID_QUALIFIER,
--
--      log.REQ_CY_PATIENT_ID                                 AS LOG_REQ_PATIENT_ID,
--      req.PATIENT_ID                                        AS REQ_PATIENT_ID,
--
--      log.REQ_2C_PREGNANCY_INDICATOR                        AS LOG_REQ_PREGNANCY_INDICATOR,
--      req.PREGNANCY_INDICATOR                               AS REQ_PREGNANCY_INDICATOR,
--
--      log.REQ_4X_PATIENT_RESIDENCE                          AS LOG_REQ_PATIENT_RESIDENCE,
--      req.PATIENT_RESIDENCE                                 AS REQ_PATIENT_RESIDENCE,
--
--      -- ========================================================================
--      -- CLAIM SEGMENT (REQUEST)
--      -- ========================================================================
--      log.REQ_28_UNIT_OF_MEASURE                            AS LOG_REQ_UNIT_OF_MEASURE,
--      req.UNIT_OF_MEASURE                                   AS REQ_UNIT_OF_MEASURE,
--
--      log.REQ_C8_OTHER_COVERAGE_CODE                        AS LOG_REQ_OTHER_COVERAGE_CODE,
--      req.OTHER_COVERAGE_CODE                               AS REQ_OTHER_COVERAGE_CODE,
--
--      log.REQ_D2_RX_NUMBER                                  AS LOG_REQ_RX_NUMBER,
--      req.RX_NUMBER                                         AS REQ_RX_NUMBER,
--
     log.REQ_D3_FILL_NUMBER                                AS LOG_REQ_FILL_NUMBER,
     req.FILL_NUMBER                                       AS REQ_FILL_NUMBER,

--      log.REQ_D5_DAYS_SUPPLY                                AS LOG_REQ_DAY_SUPPLY,
--      req.DAY_SUPPLY                                        AS REQ_DAY_SUPPLY,
--
--      log.REQ_D6_COMPOUND_CODE                              AS LOG_REQ_COMPOUND_CODE,
--      req.COMPOUND_CODE                                     AS REQ_COMPOUND_CODE,
--
--      log.REQ_D7_PRODUCT_ID                                 AS LOG_REQ_PRODUCT_ID,
--      req.PRODUCT_ID                                        AS REQ_PRODUCT_ID,
--
--      log.REQ_D703_NDC                                      AS LOG_REQ_NDC,
--      req.NDC                                               AS REQ_NDC,
--
--      log.REQ_D8_DAW_PRODUCT_SELECTION_CODE                 AS LOG_REQ_DAW,
--      req.DAW                                               AS REQ_DAW,
--
--      log.REQ_DF_NUMBER_OF_REFILLS_AUTHORIZED               AS LOG_REQ_NUMBER_OF_REFILLS,
--      req.NUMBER_OF_REFILLS                                 AS REQ_NUMBER_OF_REFILLS,
--
--      log.REQ_DI_LEVEL_OF_SERVICE                           AS LOG_REQ_LEVEL_OF_SERVICE,
--      req.LEVEL_OF_SERVICE                                  AS REQ_LEVEL_OF_SERVICE,
--
--      log.REQ_DJ_PRESCRIPTION_ORIGIN_CODE                   AS LOG_REQ_PRESCRIPTION_ORIGIN_CODE,
--      req.PRESCRIPTION_ORIGIN_CODE                          AS REQ_PRESCRIPTION_ORIGIN_CODE,
--
--      log.REQ_DK_SUBMISSION_CLARIFICATION_CODE              AS LOG_REQ_SUBMISSION_CLARIFICATION_CODE,
--      req.SUBMISSION_CLARIFICATION_CODE                     AS REQ_SUBMISSION_CLARIFICATION_CODE,
--
--      log.REQ_DE_DATE_PRESCRIPTION_WRITTEN                  AS LOG_REQ_DATE_PRESCRIPTION_WRITTEN,
--      req.DATE_PRESCRIPTION_WRITTEN                         AS REQ_DATE_PRESCRIPTION_WRITTEN,
--
--      log.REQ_E1_PRODUCT_ID_QUALIFIER                       AS LOG_REQ_PRODUCT_ID_QUALIFIER,
--      req.PRODUCT_ID_QUALIFIER                              AS REQ_PRODUCT_ID_QUALIFIER,

     log.REQ_E7_QUANTITY_DISPENSED                         AS LOG_REQ_QUANTITY_DISPENSED,
     req.QUANTITY_DISPENSED                                AS REQ_QUANTITY_DISPENSED,

--      log.REQ_EA_ORIGINALLY_PRESCRIBED_PRODUCT_CODE         AS LOG_REQ_ORIGINALLY_PRESCRIBED_PRODUCT_CODE,
--      req.ORIGINALLY_PRESCRIBED_PRODUCT_CODE                AS REQ_ORIGINALLY_PRESCRIBED_PRODUCT_CODE,
--
--      log.REQ_EJ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER AS LOG_REQ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER,
--      req.ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER        AS REQ_ORIGINALLY_PRESCRIBED_PRODUCT_ID_QUALIFIER,
--
--      log.REQ_EM_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER    AS LOG_REQ_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER,
--      req.PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER           AS REQ_PRESCRIPTION_REFERENCE_NUMBER_QUALIFIER,
--
--      log.REQ_EN_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER   AS LOG_REQ_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER,
--      req.ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER          AS REQ_ASSOCIATED_PRESCRIPTION_REFERENCE_NUMBER,
--
--      log.REQ_EP_ASSOCIATED_PRESCRIPTION_DATE               AS LOG_REQ_ASSOCIATED_PRESCRIPTION_DATE,
--      req.ASSOCIATED_PRESCRIPTION_DATE                      AS REQ_ASSOCIATED_PRESCRIPTION_DATE,
--
--      log.REQ_EU_PRIOR_AUTHORIZATION_TYPE_CODE              AS LOG_REQ_PRIOR_AUTHORIZATION_CODE,
--      req.PRIOR_AUTHORIZATION_CODE                          AS REQ_PRIOR_AUTHORIZATION_CODE,
--
--      log.REQ_HD_DISPENSING_STATUS                          AS LOG_REQ_DISPENSE_STATUS,
--      req.DISPENSE_STATUS                                   AS REQ_DISPENSE_STATUS,
--
--      log.REQ_U7_PHARMACY_SERVICE_TYPE                      AS LOG_REQ_PHARMACY_SERVICE_TYPE,
--      req.PHARMACY_SERVICE_TYPE                             AS REQ_PHARMACY_SERVICE_TYPE,
--
--      -- ========================================================================
--      -- PRICING SEGMENT (REQUEST)
--      -- ========================================================================
--      log.REQ_D9_INGREDIENT_COST_SUBMITTED                  AS LOG_REQ_INGREDIENT_COST_SUBMITTED,
--      req.INGREDIENT_COST_SUBMITTED                         AS REQ_INGREDIENT_COST_SUBMITTED,
--
--      log.REQ_DC_DISPENSING_FEE_SUBMITTED                   AS LOG_REQ_DISPENSING_FEE_SUBMITTED,
--      req.DISPENSING_FEE_SUBMITTED                          AS REQ_DISPENSING_FEE_SUBMITTED,
--
--      log.REQ_DN_BASIS_OF_COST_DETERMINATION                AS LOG_REQ_BASIS_OF_COST_DETERMINATION,
--      req.BASIS_OF_COST_DETERMINATION                       AS REQ_BASIS_OF_COST_DETERMINATION,
--
--      log.REQ_DQ_USUAL_AND_CUSTOMARY                        AS LOG_REQ_USUAL_AND_CUSTOMARY,
--      req.USUAL_AND_CUSTOMARY                               AS REQ_USUAL_AND_CUSTOMARY,
--
--      log.REQ_DU_GROSS_AMOUNT_DUE                           AS LOG_REQ_GROSS_AMOUNT_DUE,
--      req.GROSS_AMOUNT_DUE                                  AS REQ_GROSS_AMOUNT_DUE,
--
--      log.REQ_DX_PATIENT_PAY_AMOUNT_REPORTED                AS LOG_REQ_PATIENT_PAY_AMOUNT_REPORTED,
--      req.PATIENT_PAY_AMOUNT_REPORTED                       AS REQ_PATIENT_PAY_AMOUNT_REPORTED,
--
--      log.REQ_E3_INCENTIVE_AMOUNT_SUBMITTED                 AS LOG_REQ_INCENTIVE_AMOUNT_SUBMITTED,
--      req.INCENTIVE_AMOUNT_SUBMITTED                        AS REQ_INCENTIVE_AMOUNT_SUBMITTED,
--
--      log.REQ_BE_PROFESSIONAL_SERVICE_FEE_SUBMITTED         AS LOG_REQ_PROFESSIONAL_SERVICE_FEE_SUBMITTED,
--      req.PROFESSIONAL_SERVICE_FEE_SUBMITTED                AS REQ_PROFESSIONAL_SERVICE_FEE_SUBMITTED,
--
--      log.REQ_GE_PERCENTAGE_TAX_AMOUNT_SUBMITTED            AS LOG_REQ_PERCENTAGE_SALES_TAX_AMOUNT_SUBMITTED,
--      req.PERCENTAGE_SALES_TAX_AMOUNT_SUBMITTED             AS REQ_PERCENTAGE_SALES_TAX_AMOUNT_SUBMITTED,
--
--      log.REQ_H8_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER   AS LOG_REQ_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER,
--      req.OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER          AS REQ_OTHER_AMOUNT_CLAIMED_SUBMITTED_QUALIFIER,
--
--      log.REQ_H9_OTHER_AMOUNT_CLAIMED_SUBMITTED             AS LOG_REQ_OTHER_AMOUNT_CLAIMED_SUBMITTED,
--      req.OTHER_AMOUNT_CLAIMED_SUBMITTED                    AS REQ_OTHER_AMOUNT_CLAIMED_SUBMITTED,
--
--      log.REQ_HA_REGULATORY_FEE_AMOUNT_SUBMITTED            AS LOG_REQ_FLAT_SALES_TAX_AMOUNT_SUBMITTED,
--      req.FLAT_SALES_TAX_AMOUNT_SUBMITTED                   AS REQ_FLAT_SALES_TAX_AMOUNT_SUBMITTED,
--
--      -- ========================================================================
--      -- FACILITY SEGMENT (REQUEST)
--      -- ========================================================================
--      log.REQ_6D_PHARMACY_ZIP                               AS LOG_REQ_PHARMACY_ZIP_CODE,
--      req.PHARMACY_ZIP_CODE                                 AS REQ_PHARMACY_ZIP_CODE,
--
--      log.REQ_8C_FACILITY_ID                                AS LOG_REQ_FACILITY_ID,
--      req.FACILITY_ID                                       AS REQ_FACILITY_ID,
--
--      -- ========================================================================
--      -- PRESCRIBER SEGMENT (REQUEST)
--      -- ========================================================================
--      log.REQ_DB_PRESCRIBER_ID                              AS LOG_REQ_PRESCRIBER_NPI,
--      req.PRESCRIBER_NPI                                    AS REQ_PRESCRIBER_NPI,
--
--      log.REQ_DB01_PRESCRIBER_NPI                           AS LOG_REQ_PRESCRIBER_NPI_QUALIFIED,
--      req.PRESCRIBER_NPI                                    AS REQ_PRESCRIBER_NPI_QUALIFIED,
--
--      log.REQ_DL_PRIMARY_CARE_PROVIDER_ID                   AS LOG_REQ_PRIMARY_CARE_PROVIDER_ID,
--      req.PRIMARY_CARE_PROVIDER_ID                          AS REQ_PRIMARY_CARE_PROVIDER_ID,
--
--      log.REQ_DR_PRESCRIBER_LAST_NAME                       AS LOG_REQ_PRESCRIBER_NAME_1,
--      req.PRESCRIBER_NAME_1                                 AS REQ_PRESCRIBER_NAME_1,
--
--      log.REQ_EZ_PRESCRIBER_ID_QUALIFIER                    AS LOG_REQ_PRESCRIBER_ID_QUALIFIER,
--      req.PRESCRIBER_ID_QUALIFIER                           AS REQ_PRESCRIBER_ID_QUALIFIER,
--
--      log.REQ_2E_PRIMARY_CARE_PROVIDER_ID_QUALIFIER         AS LOG_REQ_PRIMARY_CARE_PROVIDER_ID_QUALIFIER,
--      req.PRIMARY_CARE_PROVIDER_ID_QUALIFIER                AS REQ_PRIMARY_CARE_PROVIDER_ID_QUALIFIER,
--
--      log.REQ_2J_PRESCRIBER_FIRST_NAME                      AS LOG_REQ_PRESCRIBER_NAME_2,
--      req.PRESCRIBER_NAME_2                                 AS REQ_PRESCRIBER_NAME_2,
--
--      log.REQ_2K_PRESCRIBER_STREET_ADDRESS                  AS LOG_REQ_PRESCRIBER_ADDRESS_1,
--      req.PRESCRIBER_ADDRESS_1                              AS REQ_PRESCRIBER_ADDRESS_1,
--
--      log.REQ_2M_PRESCRIBER_CITY                            AS LOG_REQ_PRESCRIBER_CITY,
--      req.PRESCRIBER_CITY                                   AS REQ_PRESCRIBER_CITY,
--
--      log.REQ_2N_PRESCRIBER_STATE                           AS LOG_REQ_PRESCRIBER_STATE,
--      req.PRESCRIBER_STATE                                  AS REQ_PRESCRIBER_STATE,
--
--      log.REQ_2P_PRESCRIBER_ZIP                             AS LOG_REQ_PRESCRIBER_ZIP_CODE,
--      req.PRESCRIBER_ZIP_CODE                               AS REQ_PRESCRIBER_ZIP_CODE,
--
--      log.REQ_PM_PRESCRIBER_TELEPHONE_NUMBER                AS LOG_REQ_PRESCRIBER_PHONE_NUMBER,
--      req.PRESCRIBER_PHONE_NUMBER                           AS REQ_PRESCRIBER_PHONE_NUMBER,
--
--      -- ========================================================================
--      -- COORDINATION OF BENEFITS SEGMENT (REQUEST)
--      -- ========================================================================
--      log.REQ_4C_COORDINATION_OF_BENEFITS_COUNT             AS LOG_REQ_COORDINATION_OF_BENEFITS_COUNT,
--      req.COORDINATION_OF_BENEFITS_COUNT                    AS REQ_COORDINATION_OF_BENEFITS_COUNT,
--
--      log.REQ_5C_OTHER_PAYER_COVERAGE_TYPE                  AS LOG_REQ_OTHER_PAYER_COVERAGE_TYPE,
--      req.OTHER_PAYER_COVERAGE_TYPE                         AS REQ_OTHER_PAYER_COVERAGE_TYPE,

     log.REQ_7C_OTHER_PAYER_ID                             AS LOG_REQ_OTHER_PAYER_ID_ARRAY,
     req.OTHER_PAYER_ID1                                   AS REQ_OTHER_PAYER_ID1,
     req.OTHER_PAYER_ID2                                   AS REQ_OTHER_PAYER_ID2,

--      log.REQ_HC_OTHER_PAYER_AMOUNT_PAID_QUALIFIER          AS LOG_REQ_OTHER_PAYER_AMOUNT_PAID_QUALIFIER,
--      req.OTHER_PAYER_AMOUNT_PAID_QUALIFIER                 AS REQ_OTHER_PAYER_AMOUNT_PAID_QUALIFIER,

     log.REQ_NT_OTHER_PAYER_ID_COUNT                       AS LOG_REQ_OTHER_PAYER_ID_COUNT,
     req.OTHER_PAYER_ID_COUNT                              AS REQ_OTHER_PAYER_ID_COUNT,

     -- ========================================================================
     -- WORKERS COMPENSATION SEGMENT (REQUEST)
     -- ========================================================================
--      log.REQ_CR_CARRIER_ID                                 AS LOG_REQ_CARRIER_ID,
--      req.CARRIER_ID                                        AS REQ_CARRIER_ID,

--      log.REQ_DY_DATE_OF_INJURY                             AS LOG_REQ_YEAR_OF_INJURY,
--      req.YEAR_OF_INJURY                                    AS REQ_YEAR_OF_INJURY,

     -- ========================================================================
     -- COMPOUND SEGMENT (REQUEST)
     -- ========================================================================
--      log.REQ_RE_COMPOUND_PRODUCT_ID_QUALIFIER              AS LOG_REQ_COMPOUND_PRODUCT_ID_QUALIFIER,
--      req.COMPOUND_PRODUCT_ID_QUALIFIER                     AS REQ_COMPOUND_PRODUCT_ID_QUALIFIER,
--
     log.REQ_TE_COMPOUND_PRODUCT_ID                        AS LOG_REQ_COMPOUND_PRODUCT_ID,
     req.COMPOUND_PRODUCT_ID                               AS REQ_COMPOUND_PRODUCT_ID,

     -- ========================================================================
     -- CLINICAL SEGMENT (REQUEST)
     -- ========================================================================
     log.REQ_DO_DIAGNOSIS_CODE                             AS LOG_REQ_DIAGNOSIS_CODE,
     req.DIAGNOSIS_CODE                                    AS REQ_DIAGNOSIS_CODE,

--      log.REQ_WE_DIAGNOSIS_CODE_QUALIFIER                   AS LOG_REQ_DIAGNOSIS_CODE_QUALIFIER,
--      req.DIAGNOSIS_CODE_QUALIFIER                          AS REQ_DIAGNOSIS_CODE_QUALIFIER,
--
--      -- ========================================================================
--      -- RESPONSE STATUS SEGMENT
--      -- ========================================================================
--      log.RES_AN_TRANSACTION_RESPONSE_STATUS                AS LOG_RES_RESPONSE_STATUS_CODE,
--      res.RESPONSE_STATUS_CODE                              AS RES_RESPONSE_STATUS_CODE,
--
--      log.RES_F3_AUTHORIZATION_NUMBER                       AS LOG_RES_AUTHORIZATION_NUMBER,
--      res.AUTHORIZATION_NUMBER                              AS RES_AUTHORIZATION_NUMBER,
--
--      log.RES_FA_REJECT_COUNT                               AS LOG_RES_REJECT_COUNT,
--      res.REJECT_COUNT                                      AS RES_REJECT_COUNT,
--
--      log.RES_FB_REJECT_CODE                                AS LOG_RES_REJECT_CODE_ARRAY,
--      res.REJECT_CODE_1                                     AS RES_REJECT_CODE_1,
--      res.REJECT_CODE_2                                     AS RES_REJECT_CODE_2,
--      res.REJECT_CODE_3                                     AS RES_REJECT_CODE_3,
--      res.REJECT_CODE_4                                     AS RES_REJECT_CODE_4,
--      res.REJECT_CODE_5                                     AS RES_REJECT_CODE_5,
--
--      log.RES_FQ_ADDITIONAL_MESSAGE_INFORMATION             AS LOG_RES_ADDITIONAL_MESSAGE_INFORMATION,
--      res.ADDITIONAL_MESSAGE_INFORMATION                    AS RES_ADDITIONAL_MESSAGE_INFORMATION,
--
--      log.RES_6F_APPROVED_MESSAGE_CODE                      AS LOG_RES_APPROVED_MESSAGE_CODE,
--      res.APPROVED_MESSAGE_CODE                             AS RES_APPROVED_MESSAGE_CODE,
--
--      log.RES_UF_ADDITIONAL_MESSAGE_INFORMATION_COUNT       AS LOG_RES_ADD_MESSAGE_INFORMATION_COUNT,
--      res.ADD_MESSAGE_INFORMATION_COUNT                     AS RES_ADD_MESSAGE_INFORMATION_COUNT,
--
--      log.RES_UG_ADDITIONAL_MESSAGE_INFORMATION_CONTINUITY  AS LOG_RES_ADD_MESSAGE_INFORMATION_CONT,
--      res.ADD_MESSAGE_INFORMATION_CONT                      AS RES_ADD_MESSAGE_INFORMATION_CONT,
--
--      log.RES_UH_ADDITIONAL_MESSAGE_INFORMATION_QUALIFIER   AS LOG_RES_ADD_MESSAGE_INFORMATION_QUALIFIER,
--      res.ADD_MESSAGE_INFORMATION_QUALIFIER                 AS RES_ADD_MESSAGE_INFORMATION_QUALIFIER,
--
--      -- ========================================================================
--      -- RESPONSE MESSAGE SEGMENT
--      -- ========================================================================
--      log.RES_F4_MESSAGE                                    AS LOG_RES_MESSAGE,
--      res.MESSAGE                                           AS RES_MESSAGE,
--
--      -- ========================================================================
--      -- RESPONSE INSURANCE SEGMENT
--      -- ========================================================================
--      log.RES_C1_GROUP_ID                                   AS LOG_RES_GROUP_ID,
--      res.GROUP_ID                                          AS RES_GROUP_ID,

--      log.RES_FO_PLAN_ID                                    AS LOG_RES_PLAN_ID,
--      res.PLAN_ID                                           AS RES_PLAN_ID,
--
--      log.RES_J7_PAYER_ID_QUALIFIER                         AS LOG_RES_PAYER_ID_QUALIFIER,
--      res.PAYER_ID_QUALIFIER                                AS RES_PAYER_ID_QUALIFIER,
--
--      log.RES_J8_PAYER_ID                                   AS LOG_RES_PAYER_ID,
--      res.PAYER_ID                                          AS RES_PAYER_ID,
--
--      log.RES_2F_NETWORK_REIMBURSEMENT_ID                   AS LOG_RES_NETWORK_REIMBURSEMENT_ID,
--      res.NETWORK_REIMBURSEMENT_ID                          AS RES_NETWORK_REIMBURSEMENT_ID,
--
--      -- ========================================================================
--      -- RESPONSE PRICING SEGMENT
--      -- ========================================================================
--      log.RES_AV_PERCENTAGE_TAX_EXEMPT_INDICATOR            AS LOG_RES_PERCENTAGE_TAX_EXEMPT_INDICATOR,
--      res.PERCENTAGE_TAX_EXEMPT_INDICATOR                   AS RES_PERCENTAGE_TAX_EXEMPT_INDICATOR,
--
--      log.RES_AW_REGULATORY_FEE_AMOUNT_PAID                 AS LOG_RES_FLAT_SALES_TAX_AMOUNT_PAID,
--      res.FLAT_SALES_TAX_AMOUNT_PAID                        AS RES_FLAT_SALES_TAX_AMOUNT_PAID,
--
--      log.RES_AX_PERCENTAGE_TAX_AMOUNT_PAID                 AS LOG_RES_PERCENTAGE_SALES_TAX_AMOUNT_PAID,
--      res.PERCENTAGE_SALES_TAX_AMOUNT_PAID                  AS RES_PERCENTAGE_SALES_TAX_AMOUNT_PAID,
--
--      log.RES_F5_PATIENT_PAY_AMOUNT                         AS LOG_RES_PATIENT_AMOUNT_PAID,
--      res.PATIENT_AMOUNT_PAID                               AS RES_PATIENT_AMOUNT_PAID,
--
--      log.RES_F6_INGREDIENT_COST_PAID                       AS LOG_RES_INGREDIENT_COST_PAID,
--      res.INGREDIENT_COST_PAID                              AS RES_INGREDIENT_COST_PAID,
--
--      log.RES_F7_DISPENSING_FEE_PAID                        AS LOG_RES_DISPENSING_FEE_PAID,
--      res.DISPENSING_FEE_PAID                               AS RES_DISPENSING_FEE_PAID,
--
--      log.RES_F9_TOTAL_AMOUNT_PAID                          AS LOG_RES_TOTAL_AMOUNT_PAID,
--      res.TOTAL_AMOUNT_PAID                                 AS RES_TOTAL_AMOUNT_PAID,
--
--      log.RES_FC_ACCUMULATED_DEDUCTIBLE_AMOUNT              AS LOG_RES_ACCUMULATED_DEDUCTIBLE_AMOUNT,
--      res.ACCUMULATED_DEDUCTIBLE_AMOUNT                     AS RES_ACCUMULATED_DEDUCTIBLE_AMOUNT,
--
--      log.RES_FD_REMAINING_DEDUCTIBLE_AMOUNT                AS LOG_RES_REMAINING_DEDUCTIBLE_AMOUNT,
--      res.REMAINING_DEDUCTIBLE_AMOUNT                       AS RES_REMAINING_DEDUCTIBLE_AMOUNT,
--
--      log.RES_FE_REMAINING_BENEFIT_AMOUNT                   AS LOG_RES_REMAINING_BENEFIT_AMOUNT,
--      res.REMAINING_BENEFIT_AMOUNT                          AS RES_REMAINING_BENEFIT_AMOUNT,
--
--      log.RES_FH_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE      AS LOG_RES_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE,
--      res.AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE             AS RES_AMOUNT_APPLIED_TO_PERIODIC_DEDUCTIBLE,

--      log.RES_FI_AMOUNT_OF_COPAY                            AS LOG_RES_COPAY_AMOUNT,
--      res.COPAY_AMOUNT1                                     AS RES_COPAY_AMOUNT1,
--      res.COPAY_AMOUNT2                                     AS RES_COPAY_AMOUNT2,
--
--      log.RES_FJ_AMOUNT_ATTRIBUTED_TO_PRODUCT_SELECTION     AS LOG_RES_AMOUNT_ATTRIBUTED_TO_PRODUCT_SELECTION,
--      res.AMOUNT_ATTRIBUTED_TO_PRODUCT_SELECTION            AS RES_AMOUNT_ATTRIBUTED_TO_PRODUCT_SELECTION,
--
--      log.RES_FK_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM  AS LOG_RES_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM,
--      res.AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM         AS RES_AMOUNT_EXCEEDING_PERIODIC_BENEFIT_MAXIMUM,
--
--      log.RES_FL_INCENTIVE_AMOUNT_PAID                      AS LOG_RES_INCENTIVE_AMOUNT_PAID,
--      res.INCENTIVE_AMOUNT_PAID                             AS RES_INCENTIVE_AMOUNT_PAID,
--
--      log.RES_FM_BASIS_OF_REIMBURSEMENT_DETERMINATION       AS LOG_RES_BASIS_OF_REIMBURSEMENT_DETERMINATION,
--      res.BASIS_OF_REIMBURSEMENT_DETERMINATION              AS RES_BASIS_OF_REIMBURSEMENT_DETERMINATION,
--
--      log.RES_J1_PROFESSIONAL_SERVICE_FEE_PAID              AS LOG_RES_PROFESSIONAL_SERVICE_FEE_PAID,
--      res.PROFESSIONAL_SERVICE_FEE_PAID                     AS RES_PROFESSIONAL_SERVICE_FEE_PAID,
--
--      log.RES_J3_OTHER_AMOUNT_PAID_QUALIFIER                AS LOG_RES_OTHER_AMOUNT_PAID_QUALIFIER,
--      res.OTHER_AMOUNT_PAID_QUALIFIER                       AS RES_OTHER_AMOUNT_PAID_QUALIFIER,

     log.RES_J4_OTHER_AMOUNT_PAID                          AS LOG_RES_OTHER_AMOUNT_PAID,
     res.OTHER_AMOUNT_PAID                                 AS RES_OTHER_AMOUNT_PAID,

--      log.RES_J5_OTHER_PAYER_AMOUNT_RECOGNIZED              AS LOG_RES_OTHER_PAYER_AMOUNT_RECOGNIZED,
--      res.OTHER_PAYER_AMOUNT_RECOGNIZED                     AS RES_OTHER_PAYER_AMOUNT_RECOGNIZED
 FROM CPE_PROD.DATA.CPE_CLAIMS_LOG AS log
          JOIN CPE_PROD.DATA.CPE_CLAIM_REQUESTS AS req
               ON log.RECORD_ID = req.RECORD_ID
          JOIN CPE_PROD.DATA.CPE_CLAIM_RESPONSES AS res
               ON log.RECORD_ID = res.RECORD_ID
 ORDER BY log.RECORD_ID DESC
)
SELECT * FROM combined;



-- Records That Differ
USE WAREHOUSE COMPUTE_WH;
SELECT
    RECORD_ID,
    LOG_TRANSMISSION_ID,

    LOG_REQ_COMPOUND_PRODUCT_ID,
    REQ_COMPOUND_PRODUCT_ID,

    // Comes from REQ, was pulling form response.  Addressed.
--     LOG_REQ_DIAGNOSIS_CODE,
--     REQ_DIAGNOSIS_CODE,

FROM SAMPLE_DATA;
