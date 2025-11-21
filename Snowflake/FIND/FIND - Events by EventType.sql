USE DATABASE CPE_DEV;
USE SCHEMA STAGING;

SELECT COUNT(*)
FROM
    CPE_PROD.STAGING.STAGE_EVENTS
WHERE
    data:eventType in
    (
        // Replace with actual event IDs
        'rule-data-pharmacy-data-collection-options-2'
        )
  AND INGESTED_TIMESTAMP > '2025-09-19 00:00:00.000'
;
