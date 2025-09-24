----------------------------------------------------------------------------------------------------
-- Create Test Records
----------------------------------------------------------------------------------------------------
CREATE TABLE test_hms_practitioner_profile AS
SELECT * FROM hms_practitioner_profile;

CREATE TABLE test_hms_dea AS
SELECT * FROM hms_dea;

CREATE TABLE test_hms_address AS
SELECT * FROM hms_address;

----------------------------------------------------------------------------------------------------
-- Drop TestJob Stage
----------------------------------------------------------------------------------------------------
DROP TABLE ftp_stage_testjob;

----------------------------------------------------------------------------------------------------
-- Counts
----------------------------------------------------------------------------------------------------
SELECT COUNT(*) FROM hms_address;
    SELECT * FROM hms_address LIMIT 100;

SELECT COUNT(*) FROM hms_dea;
    SELECT * FROM hms_dea LIMIT 100;

SELECT COUNT(*) FROM hms_practitioner_profile;
    SELECT * FROM hms_practitioner_profile LIMIT 100;


----------------------------------------------------------------------------------------------------
-- hms_practitioner_profile
----------------------------------------------------------------------------------------------------
SELECT
  SPLIT_PART(data, '|', 1)  AS HMS_PIID,
  SPLIT_PART(data, '|', 2)  AS FIRST,
  SPLIT_PART(data, '|', 3)  AS MIDDLE,
  SPLIT_PART(data, '|', 4)  AS LAST,
  SPLIT_PART(data, '|', 5)  AS SUFFIX,
  SPLIT_PART(data, '|', 6)  AS CRED,
  SPLIT_PART(data, '|', 7)  AS PRACTITIONER_TYPE,
  SPLIT_PART(data, '|', 8)  AS UPIN,
  SPLIT_PART(data, '|', 9)  AS NPI,
  SPLIT_PART(data, '|', 10) AS CHNG_FLAG
FROM ftp_stage_testjob
;


----------------------------------------------------------------------------------------------------
-- hms_dea
----------------------------------------------------------------------------------------------------
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