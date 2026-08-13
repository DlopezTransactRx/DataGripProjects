------------------------------------------------------------
--!!! IMPORTANT: Make sure the following are set correctly!!!
------------------------------------------------------------
-- Set Database
USE DATABASE CPE_DEV;

-- Set Your Cut-Off Date and Event Type
SET cutOffTime = CURRENT_TIMESTAMP();
SET eventType = '<SET-EVENT-TYPE-HERE>';

------------------------------------------------------------
-- METRICS
------------------------------------------------------------
-- Count of Events by Event Type and Cut Off Time
SELECT CURRENT_DATABASE() as DATABASE, $eventType as EVENT_TYPE, COUNT(*) FROM STAGING.STAGE_EVENTS WHERE data:eventType::VARCHAR IN ($eventType) AND INGESTED_TIMESTAMP <  $cutOffTime;

--  Sample of Events by Event Type and Cut Off Time
SELECT * FROM STAGING.STAGE_EVENTS WHERE data:eventType::VARCHAR IN ($eventType) AND INGESTED_TIMESTAMP <  $cutOffTime LIMIT 10;

------------------------------------------------------------
-- BACKUP
------------------------------------------------------------
CREATE TABLE SANDBOX.DLOPEZ.BACKUP_STAGE_EVENTS AS
    SELECT * FROM STAGING.STAGE_EVENTS WHERE data:eventType::VARCHAR IN ($eventType) AND INGESTED_TIMESTAMP <  $cutOffTime;

-- COUNT
SELECT COUNT(*) FROM SANDBOX.DLOPEZ.BACKUP_STAGE_EVENTS;

------------------------------------------------------------
-- !!! DELETE: Delete Events by Event Type and Cut Off Time
------------------------------------------------------------
--DELETE FROM STAGING.STAGE_EVENTS WHERE data:eventType::VARCHAR IN ($eventType) AND INGESTED_TIMESTAMP <  $cutOffTime;