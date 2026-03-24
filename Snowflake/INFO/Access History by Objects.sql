/**
* This query identifies the last access time for a list of specified database objects (tables, views, procedures, functions) by analyzing the Snowflake Access History.
* This is a good check before removing objects to see if they have been accessed recently or if they are potentially unused and safe to remove.  You can adjust the list of target objects and the time range of the access history as needed.
 */

--  List Objects You want to research here.
WITH target_objects AS (
    SELECT
        object_type,
        UPPER(object_name) AS object_name
    FROM VALUES
        ('TABLE',     'CPE_DEV.DATA.RULE_DATA_PHARMACY_DATA_COLLECTION_OPTIONS_BAK'),
        ('TABLE',     'CPE_DEV.DATA.CLAIMSLOG_BACKFILL_CONTROL_V2'),
        ('TABLE',     'CPE_DEV.DATA.BESTRX_CRM_SNAPSHOT_TEST'),
        ('TABLE',     'CPE_PROD.DATA.PMS_MTM_BACKUP'),
        ('VIEW',      'CPE_PROD.PUBLIC.PATIENTS_EXTRAC_VIEW'),
        ('VIEW',      'CPE_DEV.DATA.TEST_CLAIMS_LOG_VIEW'),
        ('PROCEDURE', 'CPE_DEV.PUBLIC.DEMO_PROC'),
        ('FUNCTION',  'CPE_PROD.DATA.GET_RETURN_CODE')
    AS v(object_type, object_name)
),

-- The Access History contains two VARIANT json arrays that list the objects accessed by each query: DIRECT_OBJECTS_ACCESSED and BASE_OBJECTS_ACCESSED.
-- The direct objects are the ones explicitly referenced in the query while the base objects include all objects accessed including those accessed indirectly via views, procedures, etc.
-- To be comprehensive we want to check both arrays for any access to our target objects.
-- We can use a LATERAL FLATTEN to extract the objects from the json.  These arrays and then UNION ALL the results together to get a single list of all accessed objects.
accessed_objects AS (
    SELECT
        ah.query_start_time,
        UPPER(obj.value:objectDomain::STRING) AS object_type,
        UPPER(obj.value:objectName::STRING)   AS object_name
    FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah,
         LATERAL FLATTEN(input => ah.direct_objects_accessed) obj

    UNION ALL

    SELECT
        ah.query_start_time,
        UPPER(obj.value:objectDomain::STRING) AS object_type,
        UPPER(obj.value:objectName::STRING)   AS object_name
    FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah,
         LATERAL FLATTEN(input => ah.base_objects_accessed) obj
)

-- Determine Last Access Time for Each Target Object
SELECT
    t.object_type,
    t.object_name,
    MAX(a.query_start_time) AS last_used_at,
    DATEDIFF('day', MAX(a.query_start_time), CURRENT_TIMESTAMP()) AS days_since_last_use
FROM target_objects t
LEFT JOIN accessed_objects a
    ON t.object_type = a.object_type
   AND t.object_name = a.object_name
GROUP BY t.object_type, t.object_name
ORDER BY last_used_at NULLS FIRST, t.object_type, t.object_name;