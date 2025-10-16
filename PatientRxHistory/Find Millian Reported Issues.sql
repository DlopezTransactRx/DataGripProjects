USE DATABASE CPE_PROD;
USE SCHEMA DATA;

DESCRIBE TABLE DATA.HTTPS_REQUEST_HISTORY;
DESCRIBE TABLE DATA.PATIENT_RX_HISTORY_REQUESTS;

SET START_TIME = '2025-10-15 00:00:00';

-- Find all Milliman Reported Requests
WITH PrxHistoryRequests AS (
    SELECT *
    FROM DATA.PATIENT_RX_HISTORY_REQUESTS
    WHERE EVENT_TIME > $START_TIME
      AND REQUEST_ID IN (
         '83917968-e787-4bd7-b6f2-e34aba23c9d8',
         '6e3a595a-0863-4d50-94c1-15147ee75f63',
         '12091306-7e20-4014-a74b-8db5ff48faed',
         'a7b7b038-8ac7-4e53-a84c-fa16e86ce6fe',
         'd923ddaa-425e-4ef8-a237-fb1219d3f4d3',
         '20d35cab-2a95-4264-91ea-1a32bb2eb861',
         'd0f6d96a-aaf2-48d2-8370-f43846b0b95f',
         '5921cb83-393e-499b-b236-928298e281b3'
        )
),
-- Scope Request By Date Time
HTTPRequests AS (
    SELECT *
    FROM DATA.HTTPS_REQUEST_HISTORY
    WHERE REQUEST_TIME > $START_TIME
)
SELECT http.*, prx.*
FROM PrxHistoryRequests prx
LEFT JOIN  HTTPRequests http
    ON prx.HTTP_REQUEST_ID = http.HTTP_REQUEST_ID
;