//====================================================================================================
// [SNOWFLAKE] PROD - Record Counts
//====================================================================================================

// Source Record Counts
SELECT 'pharmacy_switch_service' as tableName, COUNT(*) as cnt FROM CPE_PROD.DATA.PHARMACY_SWITCH_SERVICE
UNION ALL
SELECT 'switch_service' as tableName, COUNT(*) as cnt FROM CPE_PROD.DATA.SWITCH_SERVICE;

// Describe Table
DESCRIBE TABLE CPE_PROD.DATA.PHARMACY_SWITCH_SERVICE ->> SELECT * FROM $1 ORDER BY "name";
DESCRIBE TABLE CPE_PROD.DATA.SWITCH_SERVICE ->> SELECT * FROM $1 ORDER BY "name";

// Sample Data
SELECT *  FROM CPE_PROD.DATA.PHARMACY_SWITCH_SERVICE;
SELECT *  FROM CPE_PROD.DATA.SWITCH_SERVICE;

//====================================================================================================
// [SNOWFLAKE] PROD - Raw Event Counts
//====================================================================================================

// Count Raw Events
WITH targetEvents AS (
    SELECT DATA:eventType::VARCHAR  as eventType, data, INGESTED_TIMESTAMP
    FROM CPE_PROD.STAGING.STAGE_EVENTS
    WHERE DATA:eventType::VARCHAR IN (
          'SwitchDataExport-PharmacySwitchServiceTableRecord',
          'SwitchDataExport-SwitchServiceTableRecord'
    )
    AND ingested_timestamp > '2025-11-01'
)
SELECT eventType, count(*) as cnt
FROM targetEvents
GROUP BY eventType;

//====================================================================================================
// [SNOWFLAKE] PROD - Resync Steps
//====================================================================================================

// Delete Raw Events
-- DELETE FROM CPE_PROD.STAGING.STAGE_EVENTS WHERE DATA:eventType::VARCHAR IN ( 'SwitchDataExport-PharmacySwitchServiceTableRecord', 'SwitchDataExport-SwitchServiceTableRecord' );

// Drop Previous Backup Tables
-- DROP TABLE IF EXISTS CPE_PROD.DATA.PHARMACY_SWITCH_SERVICE_BAK;
-- DROP TABLE IF EXISTS CPE_PROD.DATA.SWITCH_SERVICE_BAK;

// Clone Tables As Back
-- CREATE TABLE CPE_PROD.DATA.PHARMACY_SWITCH_SERVICE_BAK CLONE CPE_PROD.DATA.PHARMACY_SWITCH_SERVICE;
-- CREATE TABLE CPE_PROD.DATA.SWITCH_SERVICE_BAK CLONE CPE_PROD.DATA.SWITCH_SERVICE;

// Truncate Source Tables
-- TRUNCATE TABLE CPE_PROD.DATA.PHARMACY_SWITCH_SERVICE;
-- TRUNCATE TABLE CPE_PROD.DATA.SWITCH_SERVICE;

// Execute Tasks
-- EXECUTE TASK CPE_PROD.DATA.STREAM_TASK_PHARMACY_SWITCH_SERVICE;
-- EXECUTE TASK CPE_PROD.DATA.STREAM_TASK_SWITCH_SERVICE;


