USE DATABASE CPE_DEV;
USE SCHEMA STAGING;

SELECT *
FROM STAGING.STAGE_EVENTS
WHERE INGESTED_TIMESTAMP > '2024-09-17 00:00:00.000'
AND data:eventId in (
    // Replace with actual event IDs
    'eventid-1-placeholder',
    'eventid-2-placeholder'
);