USE DATABASE CPE_DEV;
USE SCHEMA STAGING;

SELECT *
FROM
    CPE_DEV.STAGING.STAGE_EVENTS
WHERE
    INGESTED_TIMESTAMP > '2025-11-24 00:00:00.000'
    AND data:eventType LIKE '%events-test3%'
--     AND data:eventId::VARCHAR LIKE '%compressed-20251124%'
--     AND data:eventPayload.Description::VARCHAR LIKE '%Hello%'
--     AND data:searchable::BOOLEAN = TRUE
--     AND data:persist::BOOLEAN = TRUE
LIMIT 100;