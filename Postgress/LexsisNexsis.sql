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
-- Counts
----------------------------------------------------------------------------------------------------
SELECT COUNT(*) FROM hms_address;
    SELECT * FROM hms_address LIMIT 100;

SELECT COUNT(*) FROM hms_dea;
    SELECT * FROM hms_dea LIMIT 100;

SELECT COUNT(*) FROM hms_practitioner_profile;
    SELECT * FROM hms_practitioner_profile LIMIT 100;


----------------------------------------------------------------------------------------------------
-- Scratch
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

DROP TABLE ftp_stage_testjob;

-- HMS_PIID|FIRST|MIDDLE|LAST|SUFFIX|CRED|PRACTITIONER_TYPE|UPIN|NPI|CHNG_FLAG