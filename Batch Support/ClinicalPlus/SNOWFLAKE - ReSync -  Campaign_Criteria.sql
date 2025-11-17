//====================================================================================================
// [SNOWFLAKE] PROD - Record Counts
//====================================================================================================

// Source Record Counts
SELECT 'campaign-criteria' as tableName, COUNT(*) as cnt FROM CPE_PROD.CLINICAL_PLUS.CAMPAIGN_CRITERIA;

// Describe Table
DESCRIBE TABLE CPE_PROD.CLINICAL_PLUS.CAMPAIGN_CRITERIA ->> SELECT * FROM $1 ORDER BY "name";

// Sample Data
SELECT * FROM CPE_PROD.CLINICAL_PLUS.CAMPAIGN_CRITERIA;
SELECT COUNT(*) FROM CPE_PROD.CLINICAL_PLUS.CAMPAIGN_CRITERIA;

//====================================================================================================
// [SNOWFLAKE] PROD - Raw Event Counts
//====================================================================================================

// Count Raw Events
WITH targetEvents AS (
    SELECT DATA:eventType::VARCHAR  as eventType, data, INGESTED_TIMESTAMP
    FROM CPE_PROD.STAGING.STAGE_EVENTS
    WHERE DATA:eventType::VARCHAR IN (
--           'clinicalplus-campaign-criteria'
          'dataexport-clinicalplus-campaign-criteria'
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
-- DELETE FROM CPE_PROD.STAGING.STAGE_EVENTS WHERE DATA:eventType::VARCHAR IN ( 'clinicalplus-campaign-criteria');

// Drop Previous Backup Tables
-- DROP TABLE IF EXISTS CPE_PROD.CLINICAL_PLUS.CAMPAIGN_CRITERIA_BAK;

// Clone Tables As Back
-- CREATE TABLE CPE_PROD.CLINICAL_PLUS.CAMPAIGN_CRITERIA_BAK CLONE CPE_PROD.CLINICAL_PLUS.CAMPAIGN_CRITERIA;

// Truncate Source Tables
-- TRUNCATE TABLE CPE_PROD.CLINICAL_PLUS.CAMPAIGN_CRITERIA;

// Execute Tasks
EXECUTE TASK CPE_PROD.CLINICAL_PLUS.STREAM_TASK_CAMPAIGN_CRITERIA;