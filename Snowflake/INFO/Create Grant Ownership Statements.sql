USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;
USE DATABASE CPE_DEV;
-- USE DATABASE CPE_PROD;

--Run Queries First and Capture Querey Id For Each and Replace accordingly below.
-- SHOW SHARES;
-- SHOW WAREHOUSES;
SET currentOwner = 'ACCOUNTADMIN';
SET targetRole = 'SYSADMIN';


SELECT * FROM (
    --Database Objects
    SELECT 1 as groupOrder, 'GRANT OWNERSHIP ON DATABASE ' || DATABASE_NAME || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, DATABASE_OWNER as OWNER, DATABASE_NAME AS DATABASE_NAME
    FROM INFORMATION_SCHEMA.DATABASES

    UNION
    SELECT 2 as groupOrder, 'GRANT OWNERSHIP ON SCHEMA ' || SCHEMA_NAME || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, SCHEMA_OWNER as OWNER, CATALOG_NAME AS DATABASE_NAME
    FROM INFORMATION_SCHEMA.SCHEMATA

    UNION
    SELECT 3 as groupOrder, 'GRANT OWNERSHIP ON TABLE ' || TABLE_CATALOG || '.' || TABLE_SCHEMA || '.' || TABLE_NAME || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, TABLE_OWNER as OWNER, TABLE_CATALOG AS DATABASE_NAME
    FROM INFORMATION_SCHEMA.TABLES

    UNION
    SELECT 4 as groupOrder, 'GRANT OWNERSHIP ON VIEW ' || TABLE_CATALOG || '.' || TABLE_SCHEMA || '.' || TABLE_NAME || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, TABLE_OWNER as OWNER, TABLE_CATALOG AS DATABASE_NAME
    FROM INFORMATION_SCHEMA.VIEWS

    UNION
    SELECT 5 as groupOrder, 'GRANT OWNERSHIP ON FUNCTION ' || FUNCTION_CATALOG || '.' || FUNCTION_SCHEMA || '.' || FUNCTION_NAME || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, FUNCTION_OWNER as OWNER, FUNCTION_CATALOG AS DATABASE_NAME
    FROM INFORMATION_SCHEMA.FUNCTIONS

    UNION
    SELECT 6 as groupOrder, 'GRANT OWNERSHIP ON PROCEDURE ' || PROCEDURE_CATALOG || '.' || PROCEDURE_SCHEMA || '.' || PROCEDURE_NAME || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, PROCEDURE_OWNER as OWNER, PROCEDURE_CATALOG AS DATABASE_NAME
    FROM INFORMATION_SCHEMA.PROCEDURES

    UNION
    SELECT 7 as groupOrder, 'GRANT OWNERSHIP ON STAGE ' || STAGE_CATALOG || '.' || STAGE_SCHEMA || '.' || STAGE_NAME || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, STAGE_OWNER as OWNER, STAGE_CATALOG AS DATABASE_NAME
    FROM INFORMATION_SCHEMA.STAGES

    UNION
    SELECT 8 as groupOrder, 'GRANT OWNERSHIP ON FILE FORMAT ' || FILE_FORMAT_CATALOG || '.' || FILE_FORMAT_SCHEMA || '.' || FILE_FORMAT_NAME || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, FILE_FORMAT_OWNER as OWNER, FILE_FORMAT_CATALOG AS DATABASE_NAME
    FROM INFORMATION_SCHEMA.FILE_FORMATS

    //[LESSON LEARNED] - PIPES need to be paused before grants can be executed.  Then resumed.
    UNION
    SELECT 9 as groupOrder, 'GRANT OWNERSHIP ON PIPE ' || PIPE_CATALOG || '.' || PIPE_SCHEMA || '.' || PIPE_NAME || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, PIPE_OWNER as OWNER, PIPE_CATALOG AS DATABASE_NAME
    FROM INFORMATION_SCHEMA.PIPES
)
WHERE DATABASE_NAME = CURRENT_DATABASE() AND OWNER = $currentOwner
ORDER BY groupOrder ASC;


-- [STREAMS]
USE SCHEMA DATA;
    SHOW STREAMS;
    SELECT 10 as groupOrder, 'GRANT OWNERSHIP ON STREAM ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, rsSchema."owner" as OWNER, rsSchema."database_name" AS DATABASE_NAME
        FROM TABLE (RESULT_SCAN(LAST_QUERY_ID())) as rsSchema
        WHERE rsSchema."owner" = $currentOwner AND rsSchema."database_name" = CURRENT_DATABASE();

USE SCHEMA DATA_COLLECTIONS;
    SHOW STREAMS;
    SELECT 10 as groupOrder, 'GRANT OWNERSHIP ON STREAM ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, rsSchema."owner" as OWNER, rsSchema."database_name" AS DATABASE_NAME
        FROM TABLE (RESULT_SCAN(LAST_QUERY_ID())) as rsSchema
        WHERE rsSchema."owner" = $currentOwner AND rsSchema."database_name" = CURRENT_DATABASE();


USE SCHEMA STAGING;
    SHOW STREAMS;
    SELECT 10 as groupOrder, 'GRANT OWNERSHIP ON STREAM ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, rsSchema."owner" as OWNER, rsSchema."database_name" AS DATABASE_NAME
        FROM TABLE (RESULT_SCAN(LAST_QUERY_ID())) as rsSchema
        WHERE rsSchema."owner" = $currentOwner AND rsSchema."database_name" = CURRENT_DATABASE();

USE SCHEMA BILLING;
    SHOW STREAMS;
    SELECT 10 as groupOrder, 'GRANT OWNERSHIP ON STREAM ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;' AS command, rsSchema."owner" as OWNER, rsSchema."database_name" AS DATABASE_NAME
        FROM TABLE (RESULT_SCAN(LAST_QUERY_ID())) as rsSchema
        WHERE rsSchema."owner" = $currentOwner AND rsSchema."database_name" = CURRENT_DATABASE();



-- [TASKS]
USE SCHEMA DATA;
    SHOW TASKS;
    SELECT 11 as groupOrder, 'ALTER TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' SUSPEND;\nGRANT OWNERSHIP ON TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;\nALTER TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' RESUME;\n' AS command,  rsSchema."owner" as OWNER, rsSchema."database_name" AS DATABASE_NAME
        FROM TABLE (RESULT_SCAN(LAST_QUERY_ID())) as rsSchema
        WHERE rsSchema."owner" = $currentOwner AND rsSchema."database_name" = CURRENT_DATABASE();

USE SCHEMA DATA_COLLECTIONS;
    SHOW TASKS;
    SELECT 11 as groupOrder, 'ALTER TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' SUSPEND;\nGRANT OWNERSHIP ON TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;\nALTER TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' RESUME;\n' AS command,  rsSchema."owner" as OWNER, rsSchema."database_name" AS DATABASE_NAME
        FROM TABLE (RESULT_SCAN(LAST_QUERY_ID())) as rsSchema
        WHERE rsSchema."owner" = $currentOwner AND rsSchema."database_name" = CURRENT_DATABASE();


USE SCHEMA STAGING;
    SHOW TASKS;
    SELECT 11 as groupOrder, 'ALTER TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' SUSPEND;\nGRANT OWNERSHIP ON TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;\nALTER TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' RESUME;\n' AS command,  rsSchema."owner" as OWNER, rsSchema."database_name" AS DATABASE_NAME
        FROM TABLE (RESULT_SCAN(LAST_QUERY_ID())) as rsSchema
        WHERE rsSchema."owner" = $currentOwner AND rsSchema."database_name" = CURRENT_DATABASE();

USE SCHEMA BILLING;
    SHOW TASKS;
    SELECT 11 as groupOrder, 'ALTER TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' SUSPEND;\nGRANT OWNERSHIP ON TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' TO ROLE ' || $targetRole || ' COPY CURRENT GRANTS;\nALTER TASK ' || rsSchema."database_name" || '.' || rsSchema."schema_name" || '.' || rsSchema."name" || ' RESUME;\n' AS command,  rsSchema."owner" as OWNER, rsSchema."database_name" AS DATABASE_NAME
    FROM TABLE (RESULT_SCAN(LAST_QUERY_ID())) as rsSchema
        WHERE rsSchema."owner" = $currentOwner AND rsSchema."database_name" = CURRENT_DATABASE();
