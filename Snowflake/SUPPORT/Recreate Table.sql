//====================================================================================================
// Purpose: Recreate Table and Stream X
// This is a template script to recreate a table and its associated stream.
// Adjust the object names as needed by replacing 'X' with the actual table/stream name.
//====================================================================================================
USE DATABASE CPE_DEV;

//TODO - Consider using snowflake scripting to loop over a list of tables/streams to recreate multiple at once.

--Counts (Table and Stream)
SELECT 'Table(X)' as objNm, COUNT(*) as cnt FROM DATA.X
UNION ALL
SELECT 'Stream (X)' as objNm, COUNT(*) as cnt FROM DATA.STREAM_X;

-- Recreate Table and Stream X
ALTER TASK DATA.STREAM_TASK_X SUSPEND;
DROP STREAM DATA.STREAM_X;
CREATE OR REPLACE STREAM DATA.STREAM_X COPY GRANTS ON TABLE STAGING.STAGE_EVENTS APPEND_ONLY = TRUE SHOW_INITIAL_ROWS = TRUE;
EXECUTE TASK DATA.STREAM_TASK_X;

