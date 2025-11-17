// =================================================
// Create Test Schema
// =================================================
USE ROLE SYSADMIN;
USE DATABASE CPE_DEV;
CREATE SCHEMA IF NOT EXISTS TEST;
USE SCHEMA TEST;


// =================================================
// Create A Stream in Test
// =================================================
USE DATABASE CPE_DEV;
USE SCHEMA TEST;
USE ROLE SYSADMIN;

//================================================================
// Create Test Table Log
//================================================================
create or replace TABLE CPE_DEV.TEST.CACHE_LOG (
	TABLE_NAME VARCHAR(255) NOT NULL,
	OPERATION_TIME TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP()
);

// =================================================
// Create Test Table
// =================================================
CREATE OR REPLACE TABLE CPE_DEV.TEST.TEST1 (
    first_name STRING,
    last_name STRING
);
INSERT INTO CPE_DEV.TEST.TEST1 (first_name, last_name) VALUES ('D', 'LO');
SELECT * FROM CPE_DEV.TEST.TEST1;

-- Has Data
SELECT SYSTEM$STREAM_HAS_DATA('CPE_DEV.TEST."STREAM_V2_CPE_DEV.TEST.TEST1"');




// =================================================
// Raw SQL For Register Function.
// =================================================
-- Create Stream
CREATE OR REPLACE STREAM CPE_DEV.TEST."STREAM_V2_CPE_DEV.TEST.TEST1" ON TABLE CPE_DEV.TEST.TEST1;

-- Create Task
CREATE OR ALTER TASK CPE_DEV.TEST."STREAM_TASK_V2_CPE_DEV.TEST.TEST1"
    TARGET_COMPLETION_INTERVAL='1 MINUTES'
    WHEN SYSTEM$STREAM_HAS_DATA('CPE_DEV.TEST."STREAM_V2_CPE_DEV.TEST.TEST1"')
AS
    EXECUTE IMMEDIATE
        $$
        BEGIN
            CREATE OR REPLACE TEMPORARY TABLE CPE_DEV.TEST.DRAIN AS
            SELECT * FROM CPE_DEV.TEST."STREAM_V2_CPE_DEV.TEST.TEST1";
        END;
        $$
;

-- Insert Record Into Cache
MERGE INTO CPE_DEV.TEST.CACHE_LOG AS target
USING (
    SELECT 'CPE_DEV.TEST.TEST1' as TABLE_NAME
) AS source
    ON target.TABLE_NAME = source.TABLE_NAME
    WHEN MATCHED THEN UPDATE SET
        target.TABLE_NAME = source.TABLE_NAME,
        target.operation_time = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN
        INSERT (TABLE_NAME, operation_time)
        VALUES (source.TABLE_NAME, CURRENT_TIMESTAMP());


-- Start Trigger Task
ALTER TASK CPE_DEV.TEST."STREAM_TASK_V2_CPE_DEV.TEST.TEST1" RESUME;



// =================================================
// Raw SQL For UnRegister Function.
// =================================================

-- Start Trigger Task
ALTER TASK CPE_DEV.TEST."STREAM_TASK_V2_CPE_DEV.TEST.TEST1" SUSPEND;

-- Create Stream
DROP STREAM IF EXISTS CPE_DEV.TEST."STREAM_V2_CPE_DEV.TEST.TEST1";

-- Drop Task
DROP TASK IF EXISTS CPE_DEV.TEST."STREAM_TASK_V2_CPE_DEV.TEST.TEST1";

-- Drop Entry From Cache
DELETE FROM CPE_DEV.TEST.CACHE_LOG WHERE TABLE_NAME = 'CPE_DEV.TEST.TEST1';



// =================================================
// Show Cache Table
// =================================================
SELECT * FROM CPE_DEV.TEST.CACHE_LOG;