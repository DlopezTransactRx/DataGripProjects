//================================================================
// [SNOWFLAKE CLIENT VULNERABILITY INFO]
// This Snowflake function identifies all Snowflake Clients with
// known vulnerabilities.
//================================================================
SELECT
    c:clientId::VARCHAR clientId
    , 'https://www.cve.org/CVERecord?id=' || f.value:cve::VARCHAR cve
    , f.value:maxAffected::VARCHAR maxAffected
    , f.value:minAffected::VARCHAR minAffected
    , f.value:severity::VARCHAR severity
FROM
    (
        SELECT value c
        FROM TABLE(FLATTEN(PARSE_JSON(SYSTEM$CLIENT_VULNERABILITY_INFO())))
    ) c,
    lateral flatten(input => c, path => 'vulnerabilities' ) f;


//================================================================
// [SOFTWARE CLIENT VERSION INFO]
// This query is the list of supported Clients and versions.
// Also includes Recommended Version to Upgrade To.
//================================================================
SELECT
    value:clientId::VARCHAR                          AS client_id,
    value:minimumSupportedVersion::VARCHAR           AS min_supported,
    value:minimumNearingEndOfSupportVersion::VARCHAR AS nearing_eol,
    value:recommendedVersion::VARCHAR                AS recommended,
    value:deprecatedVersions                         AS deprecated_versions
FROM TABLE(FLATTEN(PARSE_JSON(SYSTEM$CLIENT_VERSION_INFO())));




//================================================================
// [Identify Users - Connecting With Vulnerabel Clients]
//================================================================
-- Optional helper: normalize versions like 3.12.4 into comparable numbers.
CREATE OR REPLACE TEMP FUNCTION version_key(v VARCHAR)
RETURNS NUMBER
LANGUAGE SQL
AS
$$
      COALESCE(TRY_TO_NUMBER(REGEXP_SUBSTR(SPLIT_PART(v, '.', 1), '\\d+')), 0) * 1000000000
    + COALESCE(TRY_TO_NUMBER(REGEXP_SUBSTR(SPLIT_PART(v, '.', 2), '\\d+')), 0) * 1000000
    + COALESCE(TRY_TO_NUMBER(REGEXP_SUBSTR(SPLIT_PART(v, '.', 3), '\\d+')), 0) * 1000
    + COALESCE(TRY_TO_NUMBER(REGEXP_SUBSTR(SPLIT_PART(v, '.', 4), '\\d+')), 0)
$$;

-- Days of Logins To review
SET DAYS = 14;

-- Query
WITH vulnerable_clients AS (
    SELECT
        c:clientId::VARCHAR AS client_id,
        'https://www.cve.org/CVERecord?id=' || f.value:cve::VARCHAR AS cve_url,
        f.value:cve::VARCHAR AS cve,
        f.value:maxAffected::VARCHAR AS max_affected,
        f.value:minAffected::VARCHAR AS min_affected,
        f.value:severity::VARCHAR AS severity,
        version_key(f.value:maxAffected::VARCHAR) AS max_affected_key,
        version_key(f.value:minAffected::VARCHAR) AS min_affected_key
    FROM (
        SELECT value c
        FROM TABLE(FLATTEN(PARSE_JSON(SYSTEM$CLIENT_VULNERABILITY_INFO())))
    ) c,
    LATERAL FLATTEN(input => c, path => 'vulnerabilities') f
)

, client_versions AS (
    SELECT
        value:clientId::VARCHAR                          AS client_id,
        value:minimumSupportedVersion::VARCHAR           AS min_supported,
        value:minimumNearingEndOfSupportVersion::VARCHAR AS nearing_eol,
        value:recommendedVersion::VARCHAR                AS recommended_version,
        value:deprecatedVersions                         AS deprecated_versions
    FROM TABLE(FLATTEN(PARSE_JSON(SYSTEM$CLIENT_VERSION_INFO())))
)

, login_history AS (
    SELECT
        event_timestamp,
        user_name,
        client_ip,
        reported_client_type,
        reported_client_version,

        CASE
            WHEN reported_client_type ILIKE '%JDBC%' THEN 'JDBC'
            WHEN reported_client_type ILIKE '%ODBC%' THEN 'ODBC'
            WHEN reported_client_type ILIKE '%PYTHON%' THEN 'PythonConnector'
            WHEN reported_client_type ILIKE '%SNOWSQL%' THEN 'SnowSQL'
            WHEN reported_client_type ILIKE '%NODE%' OR reported_client_type ILIKE '%JS%' THEN 'JSDriver'
            WHEN reported_client_type ILIKE '%DOTNET%' OR reported_client_type ILIKE '%.NET%' THEN 'DOTNETDriver'
            WHEN reported_client_type ILIKE '%GO%' THEN 'GO'
            WHEN reported_client_type ILIKE '%PHP%' THEN 'PHP_PDO'
            WHEN reported_client_type ILIKE '%SQLAPI%' THEN 'SQLAPI'
            ELSE reported_client_type
        END AS client_id,

        version_key(reported_client_version) AS reported_version_key
    FROM snowflake.account_usage.login_history
    WHERE event_timestamp >= DATEADD(day, -$DAYS, CURRENT_TIMESTAMP())
      AND is_success = 'YES'
      AND reported_client_version IS NOT NULL
)

, vulnerable_logins AS (
    SELECT
        lh.user_name,
        lh.event_timestamp,
        lh.client_ip,
        lh.reported_client_type,
        lh.reported_client_version,
        vc.client_id,
        vc.cve,
        vc.severity,
        vc.cve_url,
        vc.min_affected,
        vc.max_affected,
        cv.min_supported,
        cv.nearing_eol,
        cv.recommended_version,
        cv.deprecated_versions
    FROM login_history lh
    JOIN vulnerable_clients vc
        ON lh.client_id = vc.client_id
       AND lh.reported_version_key <= vc.max_affected_key
       AND (
            vc.min_affected IS NULL
            OR lh.reported_version_key >= vc.min_affected_key
       )
    LEFT JOIN client_versions cv
        ON vc.client_id = cv.client_id
)

-- Identify Those Distinct User/Client/Version Combos
, vulnerable_users AS (
    SELECT
        user_name,
        client_id,
        reported_client_version,
        nearing_eol,
        recommended_version,

        ARRAY_AGG(DISTINCT OBJECT_CONSTRUCT(
            'cve', cve,
            'cve_url', cve_url,
            'severity', severity,
            'min_affected', min_affected,
            'max_affected', max_affected
        )) AS cve_info

    FROM vulnerable_logins
    GROUP BY
        user_name,
        client_id,
        reported_client_version,
        min_supported,
        nearing_eol,
        recommended_version
)

SELECT *
FROM vulnerable_users
ORDER BY user_name, client_id, reported_client_version;