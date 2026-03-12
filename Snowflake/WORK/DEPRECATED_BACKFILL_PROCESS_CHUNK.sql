USE DATABASE CPE_DEV;
USE SCHEMA DATA;


--======================================================================================================================================================
--======================================================================================================================================================
-- LOG TABLE (To Help Debugging)
--======================================================================================================================================================
--======================================================================================================================================================
CREATE OR REPLACE TABLE BACKFILL_RUN_LOG (
  ts            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  step          STRING,
  detail        STRING
);

INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('DEBUG', 'This is a test');

CREATE OR REPLACE TABLE BACKFILL_FAKE_CLAIMS_LOG (
     ingestion_ts  TIMESTAMP_NTZ,
     data       VARIANT
);

    DESCRIBE TABLE BACKFILL_FAKE_CLAIMS_LOG;
    SELECT * FROM  BACKFILL_FAKE_CLAIMS_LOG;



--======================================================================================================================================================
--======================================================================================================================================================
-- CONTROL TABLE
--======================================================================================================================================================
--======================================================================================================================================================
CREATE OR REPLACE TABLE BACKFILL_CONTROL (
  batch_date      DATE PRIMARY KEY,
  state           STRING,              -- READY / RUNNING / DONE / ERROR
  last_seq_id     NUMBER DEFAULT 0,    -- optional bookmark (can be useful for visibility)
  stage_table     STRING,
  created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  updated_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  error_message   STRING
);

    DESCRIBE TABLE BACKFILL_CONTROL;





--======================================================================================================================================================
--======================================================================================================================================================
-- STORED PROCEDURE
--======================================================================================================================================================
--======================================================================================================================================================
CREATE OR REPLACE PROCEDURE EXECUTE_CLAIMSLOG_BACKFILL(
    P_BATCH_DATE   DATE,
    P_CHUNK_SIZE   NUMBER,
    P_WORKER_ID    STRING
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  v_batch_date     DATE;
  v_stage_table    STRING;
  v_rows_claimed   NUMBER;

BEGIN

   -- LOG
   INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('START', 'Starting backfill procedure');


  ---------------------------------------------------------------------------
  -- 0) Pick batch date
  ---------------------------------------------------------------------------
  IF (P_BATCH_DATE IS NOT NULL) THEN
    v_batch_date := P_BATCH_DATE;
  ELSE
    SELECT batch_date
      INTO v_batch_date
    FROM BACKFILL_CONTROL
    WHERE state = 'READY'
    ORDER BY batch_date
    LIMIT 1;

    IF (v_batch_date IS NULL) THEN
      RETURN 'No READY batches found.';
    END IF;
  END IF;

  -- LOG
  INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('v_batch_data', :v_batch_date);

  v_stage_table := 'BACKFILLSTAGE_' || TO_VARCHAR(v_batch_date, 'YYYYMMDD');

   -- LOG
   INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('v_stage_table', :v_stage_table);

  ---------------------------------------------------------------------------
  -- 1) Ensure control row exists + set RUNNING
  ---------------------------------------------------------------------------
  -- LOG
  INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('Claim Batch Records', 'Claiming Batch Records');

  MERGE INTO BACKFILL_CONTROL c
  USING (SELECT :v_batch_date AS batch_date) s
  ON c.batch_date = s.batch_date
  WHEN NOT MATCHED THEN
    INSERT (batch_date, state, stage_table)
    VALUES (s.batch_date, 'READY', :v_stage_table);

  UPDATE BACKFILL_CONTROL
     SET state = 'RUNNING',
         stage_table = :v_stage_table,
         updated_at = CURRENT_TIMESTAMP(),
         error_message = NULL
   WHERE batch_date = :v_batch_date;

  ---------------------------------------------------------------------------
  -- 2) Create stage table if needed (per-day)
  ---------------------------------------------------------------------------
  -- LOG
  INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('Create Stage Table', 'Creating stage table: ' || :v_stage_table);
  EXECUTE IMMEDIATE '
    CREATE TRANSIENT TABLE IF NOT EXISTS ' || v_stage_table || ' (
      seq_id        NUMBER AUTOINCREMENT,
      ingestion_ts  TIMESTAMP_NTZ,
      data       VARIANT,
      status        STRING DEFAULT ''NEW'',
      claimed_at    TIMESTAMP_NTZ,
      completed_at  TIMESTAMP_NTZ,
      worker_id     STRING,
      error_message STRING
    )
  ';


  ---------------------------------------------------------------------------
  -- 3) Load the day into stage IF it's empty (or if you want idempotency checks)
  --    Replace TRANSMISSION + ingestion filter with your real source/table/column.
  ---------------------------------------------------------------------------
  -- LOG
  INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('LOADING STAGE', 'Starting Load: ' || :v_stage_table);
  EXECUTE IMMEDIATE '
    INSERT INTO ' || v_stage_table || ' (ingestion_ts, data)
    SELECT INGESTED_TIMESTAMP, DATA
    FROM STAGING.STAGE_CPE_TRANSMISSIONS
    WHERE CAST(INGESTED_TIMESTAMP AS DATE) = ''' || TO_VARCHAR(v_batch_date) || '''
     AND NOT EXISTS (SELECT 1 FROM ' || v_stage_table || ')
  ';

   -- LOG
   INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('DONE LOADING STAGE', 'Stage Loaded: ' || :v_stage_table);


  ---------------------------------------------------------------------------
  -- 4) Main Process
  ---------------------------------------------------------------------------

    -- LOG
    INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('Claiming Chunk', 'Claiming Chunk of size ' || TO_VARCHAR(:P_CHUNK_SIZE));

    EXECUTE IMMEDIATE '
      UPDATE ' || v_stage_table || ' s
         SET status = ''IN_PROCESS'',
             claimed_at = CURRENT_TIMESTAMP(),
             worker_id = ''' || P_WORKER_ID || '''
       WHERE s.seq_id IN (
           SELECT seq_id
           FROM ' || v_stage_table || '
           WHERE status = ''NEW''
           ORDER BY seq_id
           LIMIT ' || P_CHUNK_SIZE || '
       )
    ';

    -- TODO: Replace this with a query to get the actual number of rows claimed.
    v_rows_claimed := SQLROWCOUNT; --NOTE: SQLROWCOUNT is a Snowflake-provided variable that gives the number of rows affected by the last DML statement.

    -- LOG
    INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('v_rows_claimed', :v_rows_claimed);

    -------------------------------------------------------------------------
    -- 4b) PROCESS STEP (placeholder)
    --     Replace with your set-based logic (INSERT/MERGE into claims_log).
    -------------------------------------------------------------------------

    IF (v_rows_claimed = 0) THEN
        -- No More Rows To Process. Close Out Batch.

        -- LOG
        INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('Break Condition', 'No more rows to process');

        -------------------------------------------------------------------------
        -- 4d) Optional: update visibility bookmark in control (max completed seq)
        -------------------------------------------------------------------------
        -- LOG
        INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('Update Back Fill Control', 'Update Back Fill Control - COMPLETE for batch date ' || TO_VARCHAR(:v_batch_date));

        EXECUTE IMMEDIATE '
          UPDATE BACKFILL_CONTROL
             SET last_seq_id = COALESCE((
                 SELECT MAX(seq_id) FROM ' || v_stage_table || ' WHERE status = ''COMPLETE''
             ), 0),
                 updated_at = CURRENT_TIMESTAMP()
           WHERE batch_date = ''' || TO_VARCHAR(v_batch_date) || '''
        ';

        ---------------------------------------------------------------------------
        -- 5) Done: mark control DONE and drop stage table
        ---------------------------------------------------------------------------
        UPDATE BACKFILL_CONTROL
           SET state = 'DONE',
               updated_at = CURRENT_TIMESTAMP()
         WHERE batch_date = :v_batch_date;

        EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS ' || :v_stage_table;

        RETURN 'DONE: ' || TO_VARCHAR(:v_batch_date);

    ELSE

        //PROCESS THE CHUNKED OF ROWS
        -- LOG
        INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('Process Claims', 'Process Claims Log for Worker ');
        EXECUTE IMMEDIATE '
          INSERT INTO BACKFILL_FAKE_CLAIMS_LOG (ingestion_ts, data)
          SELECT ingestion_ts, data
          FROM ' || v_stage_table || '
          WHERE status = ''IN_PROCESS''
            AND worker_id = ''' || P_WORKER_ID || '''
        ';

        //MARK THE CHUNK AS COMPLETE
        -- LOG
        INSERT INTO BACKFILL_RUN_LOG( step, detail) VALUES ('Mark Chunk Complete', 'Mark Chunk Complete');
        EXECUTE IMMEDIATE '
          UPDATE ' || v_stage_table || '
             SET status = ''COMPLETE'',
                 completed_at = CURRENT_TIMESTAMP()
           WHERE status = ''IN_PROCESS''
             AND worker_id = ''' || P_WORKER_ID || '''
        ';

        // Mark Batch Control - Ready For More
         EXECUTE IMMEDIATE '
          UPDATE BACKFILL_CONTROL
             SET last_seq_id = COALESCE((
                 SELECT MAX(seq_id) FROM ' || v_stage_table || ' WHERE status = ''READY''
             ), 0),
                 updated_at = CURRENT_TIMESTAMP()
           WHERE batch_date = ''' || TO_VARCHAR(v_batch_date) || '''
        ';

    END IF;





EXCEPTION
  WHEN OTHER THEN

    UPDATE BACKFILL_CONTROL
       SET state = 'ERROR',
           updated_at = CURRENT_TIMESTAMP(),
           error_message = 'SP_BACKFILL_RUN failed'
     WHERE batch_date = :v_batch_date;

    RETURN 'ERROR running batch ' || TO_VARCHAR(:v_batch_date);
END;
$$;



------------------------------------------------------------------------------------------------------------------------------------------------------
-- Control Table Seed
------------------------------------------------------------------------------------------------------------------------------------------------------

-- Reset
TRUNCATE TABLE IF EXISTS BACKFILL_RUN_LOG;
TRUNCATE TABLE IF EXISTS BACKFILL_CONTROL;
TRUNCATE TABLE IF EXISTS BACKFILLSTAGE_20260101;
TRUNCATE TABLE IF EXISTS BACKFILLSTAGE_20251201;
TRUNCATE TABLE IF EXISTS BACKFILL_FAKE_CLAIMS_LOG;
INSERT INTO BACKFILL_CONTROL (batch_date, state) VALUES
--     ('2025-12-01', 'READY'),
    ('2026-01-01', 'READY');
;
CALL EXECUTE_CLAIMSLOG_BACKFILL(NULL, 100, 'TestBackFilRun');
SELECT * FROM  BACKFILL_RUN_LOG;

-- Check Execution Log
SELECT * FROM  BACKFILL_CONTROL;
    SELECT * FROM BACKFILLSTAGE_20260101;

    -- Check Fake Claims Log
    SELECT * FROM BACKFILL_FAKE_CLAIMS_LOG;


UPDATE BACKFILLSTAGE_20260101 s
   SET status = 'IN_PROCESS',
       claimed_at = CURRENT_TIMESTAMP(),
       worker_id = 'TestBackFilRun'
 WHERE s.seq_id IN (
     SELECT seq_id
     FROM BACKFILLSTAGE_20260101
     WHERE status = 'NEW'
     ORDER BY seq_id
     LIMIT 100
 );



--======================================================================================================================================================
--======================================================================================================================================================
-- TASK
--======================================================================================================================================================
--======================================================================================================================================================
CREATE OR REPLACE TASK TASK_BACKFILL_RUN
  WAREHOUSE = ETL_WH
  SCHEDULE = '5 MINUTE'
AS
    CALL EXECUTE_CLAIMSLOG_BACKFILL(NULL, 100, 'TestBackFilRun');