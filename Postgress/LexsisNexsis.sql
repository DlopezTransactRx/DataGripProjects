----------------------------------------------------------------------------------------------------
-- Drop TestJob Stage
----------------------------------------------------------------------------------------------------
TRUNCATE TABLE ftp_stage_testjob;
DROP TABLE ftp_stage_testjob;

-- Count
SELECT count(*) FROM ftp_stage_testjob;

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

-- Create Table
CREATE TABLE IF NOT EXISTS test_hms_address (
     HMS_PIID    TEXT,
     HMS_LID     TEXT,
     RANK        INTEGER,
     FIRM_NAME   TEXT,
     ADDRESS1    TEXT,
     ADDRESS2    TEXT,
     CITY        TEXT,
     STATE       TEXT,
     ZIP         TEXT,
     ZIP4        TEXT,
     PHONE1      TEXT,
     PHONE2      TEXT,
     FAX         TEXT
);

-- Import Query --
WITH delta AS (
 SELECT
  SPLIT_PART(data, '|', 1)  AS HMS_PIID,
  SPLIT_PART(data, '|', 2)  AS HMS_LID,
  CASE
   WHEN SPLIT_PART(data, '|', 3) ~ '^[0-9]+$'
   THEN SPLIT_PART(data, '|', 3)::int
   ELSE NULL
  END AS RANK,
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
)
MERGE INTO test_hms_address AS t
USING delta AS d
 ON t.HMS_PIID = d.HMS_PIID AND t.HMS_LID = d.HMS_LID
WHEN MATCHED AND d.CHNG_FLAG = 'DELETED' THEN
 DELETE
WHEN MATCHED AND d.CHNG_FLAG = 'UPDATED' THEN
 UPDATE SET
  RANK = d.RANK,
  FIRM_NAME = d.FIRM_NAME,
  ADDRESS1 = d.ADDRESS1,
  ADDRESS2 = d.ADDRESS2,
  CITY = d.CITY,
  STATE = d.STATE,
  ZIP = d.ZIP,
  ZIP4 = d.ZIP4,
  PHONE1 = d.PHONE1,
  PHONE2 = d.PHONE2,
  FAX = d.FAX
WHEN NOT MATCHED AND d.CHNG_FLAG IN ('NEW','UPDATED') THEN
 INSERT (HMS_PIID, HMS_LID, RANK, FIRM_NAME, ADDRESS1, ADDRESS2, CITY, STATE, ZIP, ZIP4, PHONE1, PHONE2, FAX)
 VALUES (d.HMS_PIID, d.HMS_LID, d.RANK, d.FIRM_NAME, d.ADDRESS1, d.ADDRESS2, d.CITY, d.STATE, d.ZIP, d.ZIP4, d.PHONE1, d.PHONE2, d.FAX)



----------------------------------------------------------------------------------------------------
-- hms_practitioner_profile
----------------------------------------------------------------------------------------------------
-- Create Test Table
TRUNCATE TABLE test_hms_practitioner_profile;
DROP TABLE IF EXISTS test_hms_practitioner_profile;
CREATE TABLE test_hms_practitioner_profile AS
SELECT * FROM hms_practitioner_profile;

-- Counts
SELECT COUNT(*) FROM test_hms_practitioner_profile;
--BEFORE: 2817270
--AFTER:  2817273

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
WHERE CHNG_FLAG = 'NEW'
;


-- Raw Create Table
CREATE TABLE IF NOT EXISTS test_hms_practitioner_profile (
     hms_piid           TEXT,
     first              TEXT,
     middle             TEXT,
     last               TEXT,
     suffix             TEXT,
     cred               TEXT,
     practitioner_type  TEXT,
     upin               TEXT,
     npi                INTEGER
);

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
-- Truncate/Drop
TRUNCATE TABLE test_hms_dea;
DROP TABLE IF EXISTS test_hms_dea;

-- Create Test Table
CREATE TABLE test_hms_dea AS
SELECT * FROM hms_dea;

-- Counts
SELECT COUNT(*) FROM test_hms_dea;

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

-- Create Table
CREATE TABLE IF NOT EXISTS test_hms_dea (
                                            hms_piid           TEXT,
                                            dea                TEXT,
                                            dea_schedule       TEXT,
                                            dea_expire         TEXT,
                                            nadean             TEXT,
                                            lid                TEXT
);

-- Import
WITH delta AS (
    SELECT
        SPLIT_PART(data, '|', 1)  AS HMS_PIID,
        SPLIT_PART(data, '|', 2)  AS DEA,
        SPLIT_PART(data, '|', 3)  AS DEA_SCHEDULE,
        SPLIT_PART(data, '|', 4)  AS DEA_EXPIRE,
        SPLIT_PART(data, '|', 5)  AS NADEAN,
        SPLIT_PART(data, '|', 6)  AS LID,
        SPLIT_PART(data, '|', 7)  AS CHNG_FLAG
    FROM ftp_stage_testjob
    )
    MERGE INTO test_hms_dea AS t
USING delta AS d
ON t.HMS_PIID = d.HMS_PIID
WHEN MATCHED AND d.CHNG_FLAG = 'DELETED' THEN
    DELETE
WHEN MATCHED AND d.CHNG_FLAG = 'UPDATED' THEN
    UPDATE SET
               DEA = d.DEA,
               DEA_SCHEDULE = d.DEA_SCHEDULE,
               DEA_EXPIRE = d.DEA_EXPIRE,
               NADEAN = d.NADEAN,
               LID = d.LID
WHEN NOT MATCHED AND d.CHNG_FLAG IN ('NEW','UPDATED') THEN
    INSERT (HMS_PIID, DEA, DEA_SCHEDULE, DEA_EXPIRE, NADEAN, LID)
    VALUES (d.HMS_PIID, d.DEA, d.DEA_SCHEDULE, d.DEA_EXPIRE, d.NADEAN, d.LID)
;
