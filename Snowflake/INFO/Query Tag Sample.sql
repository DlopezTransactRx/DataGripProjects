-- Show Pre-existing Query Tag
SHOW PARAMETERS LIKE 'QUERY_TAG';

-- Set Session
-- NOTE:  This cane be any string up to 2000 characters long. In this case we are establishing a custom JSON.
ALTER SESSION SET QUERY_TAG = '{ "app": "datagrip", "environment": "development", "user": "daniel.lopez@redsailtechnologies.com", "task": "test", "version": "" }';

-- Show Currently Query Tag Session Value.
SHOW PARAMETERS LIKE 'QUERY_TAG';

-- Query To Execute
SELECT COUNT(*) FROM CPE_DEV.DATA.TRANSACTION_LOG;

-- Example of Filtering By Custom Query Tag.
WITH json_tag as(
    SELECT
        QUERY_ID,
        USER_NAME,
        PARSE_JSON(QUERY_TAG) as tag,
        QUERY_TEXT
    FROM TABLE(CPE_DEV.INFORMATION_SCHEMA.QUERY_HISTORY())
    WHERE QUERY_TAG <> ''
)
SELECT
    tag,
    QUERY_ID,
    USER_NAME,
    QUERY_TEXT
FROM json_tag
WHERE tag:task::string = 'test'; --Filtering By Custom Tag

-- Unset Query Tag
ALTER SESSION UNSET QUERY_TAG;

-- See Tag to Verify Unset.
SHOW PARAMETERS LIKE 'QUERY_TAG';
