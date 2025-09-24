----------------------------------------------------------------------------------------------------
-- Drop TestJob Stage
----------------------------------------------------------------------------------------------------
DROP TABLE ftp_stage_testjob;

----------------------------------------------------------------------------------------------------
-- hms_practitioner_profile
----------------------------------------------------------------------------------------------------

-- Create Test Table
DROP TABLE IF EXISTS test_hms_practitioner_profile;
CREATE TABLE test_hms_practitioner_profile AS
SELECT * FROM hms_practitioner_profile;

-- Counts
SELECT COUNT(*) FROM test_hms_practitioner_profile;
SELECT * FROM test_hms_practitioner_profile;

-- Preview Query --
WITH delta AS (
    SELECT
        SPLIT_PART(data, '|', 1)  AS HMS_PIID,
        SPLIT_PART(data, '|', 2)  AS FIRST,
        SPLIT_PART(data, '|', 3)  AS MIDDLE,
        SPLIT_PART(data, '|', 4)  AS LAST,
        SPLIT_PART(data, '|', 5)  AS SUFFIX,
        SPLIT_PART(data, '|', 6)  AS CRED,
        SPLIT_PART(data, '|', 7)  AS PRACTITIONER_TYPE,
        SPLIT_PART(data, '|', 8)  AS UPIN,
        CASE
          WHEN SPLIT_PART(data, '|', 9) ~ '^[0-9]+$'
          THEN SPLIT_PART(data, '|', 9)::int
          ELSE NULL
        END AS NPI,
        SPLIT_PART(data, '|', 10) AS CHNG_FLAG
    FROM ftp_stage_testjob
)
SELECT * FROM delta
;

-- Import Query --
WITH delta AS (
    SELECT
        SPLIT_PART(data, '|', 1)  AS HMS_PIID,
        SPLIT_PART(data, '|', 2)  AS FIRST,
        SPLIT_PART(data, '|', 3)  AS MIDDLE,
        SPLIT_PART(data, '|', 4)  AS LAST,
        SPLIT_PART(data, '|', 5)  AS SUFFIX,
        SPLIT_PART(data, '|', 6)  AS CRED,
        SPLIT_PART(data, '|', 7)  AS PRACTITIONER_TYPE,
        SPLIT_PART(data, '|', 8)  AS UPIN,
        CASE
            WHEN SPLIT_PART(data, '|', 9) ~ '^[0-9]+$'
                THEN SPLIT_PART(data, '|', 9)::int
            ELSE NULL
        END AS NPI,
        SPLIT_PART(data, '|', 10) AS CHNG_FLAG
    FROM ftp_stage_testjob
)
MERGE INTO test_hms_practitioner_profile AS t
USING delta AS d
  ON t.HMS_PIID = d.HMS_PIID
WHEN MATCHED AND d.CHNG_FLAG = 'DELETED' THEN
  DELETE
WHEN MATCHED AND d.CHNG_FLAG = 'UPDATED' THEN
  UPDATE SET
    FIRST = d.FIRST,
    MIDDLE = d.MIDDLE,
    LAST = d.LAST,
    SUFFIX = d.SUFFIX,
    CRED = d.CRED,
    PRACTITIONER_TYPE = d.PRACTITIONER_TYPE,
    UPIN = d.UPIN,
    NPI = d.NPI
WHEN NOT MATCHED AND d.CHNG_FLAG IN ('NEW','UPDATED') THEN
  INSERT (HMS_PIID, FIRST, MIDDLE, LAST, SUFFIX, CRED, PRACTITIONER_TYPE, UPIN, NPI)
  VALUES (d.HMS_PIID, d.FIRST, d.MIDDLE, d.LAST, d.SUFFIX, d.CRED, d.PRACTITIONER_TYPE, d.UPIN, d.NPI)
;


----------------------------------------------------------------------------------------------------
-- hms_dea
----------------------------------------------------------------------------------------------------

-- Create Test Table
DROP TABLE IF EXISTS test_hms_dea;
CREATE TABLE test_hms_dea AS
SELECT * FROM hms_dea;

-- Counts
SELECT COUNT(*) FROM test_hms_dea;
SELECT * FROM test_hms_dea;

-- Preview Query --
SELECT
    SPLIT_PART(data, '|', 1)  AS HMS_PIID,
    SPLIT_PART(data, '|', 2)  AS DEA,
    SPLIT_PART(data, '|', 3)  AS DEA_SCHEDULE,
    SPLIT_PART(data, '|', 4)  AS DEA_EXPIRE,
    SPLIT_PART(data, '|', 5)  AS NADEAN,
    SPLIT_PART(data, '|', 6)  AS LID,
    SPLIT_PART(data, '|', 7)  AS CHNG_FLAG
FROM ftp_stage_testjob
;


----------------------------------------------------------------------------------------------------
-- hms_address
----------------------------------------------------------------------------------------------------

-- Create Test Table
DROP TABLE IF EXISTS test_hms_address;
CREATE TABLE test_hms_address AS
SELECT * FROM hms_address;

-- Counts
SELECT COUNT(*) FROM test_hms_address;
SELECT * FROM test_hms_address;

-- Preview Query --
SELECT
    SPLIT_PART(data, '|', 1)  AS HMS_PIID,
    SPLIT_PART(data, '|', 2)  AS HMS_LID,
    SPLIT_PART(data, '|', 3)  AS RANK,
    SPLIT_PART(data, '|', 4)  AS FIRM_NAME,
    SPLIT_PART(data, '|', 5)  AS ADDRESS1,
    SPLIT_PART(data, '|', 6)  AS ADDRESS2,
    SPLIT_PART(data, '|', 7)  AS CITY,
    SPLIT_PART(data, '|', 8)  AS STATE,
    SPLIT_PART(data, '|', 9)  AS ZIP,
    SPLIT_PART(data, '|', 10) AS ZIP4,
    SPLIT_PART(data, '|', 11) AS PHONE1,
    SPLIT_PART(data, '|', 12) AS PHONE2,
    SPLIT_PART(data, '|', 13) AS FAX,
    SPLIT_PART(data, '|', 14) AS CHNG_FLAG
FROM ftp_stage_testjob
;
