USE DATABASE CPE_DEV;
USE SCHEMA DATA;

//Query to pull sample data form an NCPDP Reequest Field.
SET ncpdpField = 'D7';


`//Request Transaction
SELECT     
    EXTRACT_NCPDP_FIELD(REQUEST, $ncpdpField, 1) AS fieldData,
FROM CPE_DEV.DATA.TRANSMISSIONS 
WHERE TRANSACTION_CODE IN ('B1', 'Q1', 'S1', 'B3') 
AND fieldData IS NOT NULL
LIMIT 1;
`

//Response Transaction
SELECT     
    EXTRACT_NCPDP_FIELD(RESPONSE, $ncpdpField, 1) AS fieldData,
FROM CPE_DEV.DATA.TRANSMISSIONS 
WHERE TRANSACTION_CODE IN ('B1', 'Q1', 'S1', 'B3') 
AND fieldData IS NOT NULL
LIMIT 1;