// =================================================
// Create Procedure to Register Cache Table
// =================================================
CREATE OR REPLACE PROCEDURE CPE_DEV.TEST.registerCacheTable( db_name STRING, schema_name STRING, table_name STRING )
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
    DECLARE
        cachSchmPrefix STRING := CURRENT_DATABASE() || '.' || CURRENT_SCHEMA() || '.';
        cacheTbl STRING := cachSchmPrefix || 'CACHE_LOG';
        tbl STRING := db_name || '.' || schema_name || '.' || table_name;
        strm STRING := :cachSchmPrefix || '"STREAM_' || :tbl || '"';

        createStreamStmt STRING := 'CREATE OR REPLACE STREAM ' || :strm || ' ON TABLE ' || :tbl || ';';

        createTaskStmt STRING :=
            'CREATE OR ALTER TASK ' || cachSchmPrefix || '"STREAM_TASK_' || tbl || '"' ||
            CHR(10) || '    TARGET_COMPLETION_INTERVAL = ''1 MINUTES''' ||
            CHR(10) || '    WHEN SYSTEM$STREAM_HAS_DATA(''' || :strm  || ''')' ||
            CHR(10) || 'AS' ||
            CHR(10) || '    EXECUTE IMMEDIATE ''' ||
            CHR(10) || '    BEGIN' ||
            CHR(10) || '        CREATE OR REPLACE TEMPORARY TABLE ' || cachSchmPrefix || 'DRAIN AS' ||
            CHR(10) || '            SELECT * FROM ' || cachSchmPrefix || '"STREAM_' || tbl || '";' ||
            CHR(10) || '    END;' ||
            CHR(10) || '    '';';

        mergeStmt STRING :=
            'MERGE INTO ' || cacheTbl || ' AS target' ||
            CHR(10) || 'USING (' ||
            CHR(10) || '    SELECT ''' || tbl || ''' AS TABLE_NAME' ||
            CHR(10) || ') AS source' ||
            CHR(10) || '    ON target.TABLE_NAME = source.TABLE_NAME' ||
            CHR(10) || '    WHEN MATCHED THEN UPDATE SET' ||
            CHR(10) || '        target.TABLE_NAME = source.TABLE_NAME,' ||
            CHR(10) || '        target.OPERATION_TIME = CURRENT_TIMESTAMP()' ||
            CHR(10) || '    WHEN NOT MATCHED THEN' ||
            CHR(10) || '        INSERT (TABLE_NAME, OPERATION_TIME)' ||
            CHR(10) || '        VALUES (source.TABLE_NAME, CURRENT_TIMESTAMP());';

        alterTaskStmt STRING := 'ALTER TASK ' || cachSchmPrefix || '"STREAM_TASK_' || tbl || '" RESUME;';

    BEGIN
        -- Create Stream
        EXECUTE IMMEDIATE :createStreamStmt;
        -- Create Task
        EXECUTE IMMEDIATE :createTaskStmt;
        -- Insert Record Into Cache
        EXECUTE IMMEDIATE :mergeStmt;
       -- Start Trigger Task
        EXECUTE IMMEDIATE :alterTaskStmt;
    END;
$$;


// =================================================
// Create Procedure to Register Cache Table
// =================================================
CREATE OR REPLACE PROCEDURE CPE_DEV.TEST.registerCacheTableV3( db_name STRING, schema_name STRING, table_name STRING )
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
    DECLARE
        cachSchmPrefix STRING := CURRENT_DATABASE() || '.' || CURRENT_SCHEMA() || '.';
        cacheTbl STRING := cachSchmPrefix || 'CACHE_LOG';
        tbl STRING := db_name || '.' || schema_name || '.' || table_name;
        strm STRING := :cachSchmPrefix || '"STREAM_' || :tbl || '"';

        createStreamStmt STRING := 'CREATE OR REPLACE STREAM ' || :strm || ' ON TABLE ' || :tbl || ';';

        createTaskStmt STRING :=
            'CREATE OR ALTER TASK ' || cachSchmPrefix || '"STREAM_TASK_' || tbl || '"' ||
            CHR(10) || '    TARGET_COMPLETION_INTERVAL = ''1 MINUTES''' ||
            CHR(10) || '    WHEN SYSTEM$STREAM_HAS_DATA(''' || :strm  || ''')' ||
            CHR(10) || 'AS' ||
            CHR(10) || '    EXECUTE IMMEDIATE ''' ||
            CHR(10) || '    BEGIN' ||
            CHR(10) || '        CREATE OR REPLACE TEMPORARY TABLE ' || cachSchmPrefix || 'DRAIN AS' ||
            CHR(10) || '            SELECT * FROM ' || cachSchmPrefix || '"STREAM_' || tbl || '";' ||
            CHR(10) || '    END;' ||
            CHR(10) || '    '';';

        mergeStmt STRING :=
            'MERGE INTO ' || cacheTbl || ' AS target' ||
            CHR(10) || 'USING (' ||
            CHR(10) || '    SELECT ''' || tbl || ''' AS TABLE_NAME' ||
            CHR(10) || ') AS source' ||
            CHR(10) || '    ON target.TABLE_NAME = source.TABLE_NAME' ||
            CHR(10) || '    WHEN MATCHED THEN UPDATE SET' ||
            CHR(10) || '        target.TABLE_NAME = source.TABLE_NAME,' ||
            CHR(10) || '        target.OPERATION_TIME = CURRENT_TIMESTAMP()' ||
            CHR(10) || '    WHEN NOT MATCHED THEN' ||
            CHR(10) || '        INSERT (TABLE_NAME, OPERATION_TIME)' ||
            CHR(10) || '        VALUES (source.TABLE_NAME, CURRENT_TIMESTAMP());';

        alterTaskStmt STRING := 'ALTER TASK ' || cachSchmPrefix || '"STREAM_TASK_' || tbl || '" RESUME;';

    BEGIN
        -- Create Stream
        EXECUTE IMMEDIATE :createStreamStmt;
        -- Create Task
        EXECUTE IMMEDIATE :createTaskStmt;
        -- Insert Record Into Cache
        EXECUTE IMMEDIATE :mergeStmt;
       -- Start Trigger Task
        EXECUTE IMMEDIATE :alterTaskStmt;
    END;
$$;



// =================================================
// Create Procedure to UnRegister Cache Table
// =================================================
CREATE OR REPLACE PROCEDURE CPE_DEV.TEST.unRegisterCacheTable( db_name STRING, schema_name STRING, table_name STRING )
    RETURNS STRING
    LANGUAGE SQL
    EXECUTE AS OWNER
AS
$$
DECLARE
    cachSchmPrefix STRING := CURRENT_DATABASE() || '.' || CURRENT_SCHEMA() || '.';
    cacheTbl STRING := cachSchmPrefix || 'CACHE_LOG';
    tbl STRING := db_name || '.' || schema_name || '.' || table_name;
    strm STRING := :cachSchmPrefix || '"STREAM_' || :tbl || '"';
    task STRING := :cachSchmPrefix || '"STREAM_TASK_' || :tbl || '"';

    createSuspendTaskStmt STRING := 'ALTER TASK ' || cachSchmPrefix || '"STREAM_TASK_' || tbl || '" SUSPEND;';
    createDropStreamStmt STRING := 'DROP STREAM IF EXISTS ' || :strm || ';';
    createDropTaskStmt STRING := 'DROP TASK IF EXISTS ' || :task || ';';
    deleteCacheEntryStmt STRING :=  'DELETE FROM ' || :cacheTbl || ' WHERE TABLE_NAME = ''' || :tbl || ''';';


BEGIN
    -- Suspend Trigger Task
    EXECUTE IMMEDIATE :createSuspendTaskStmt;
    -- Drop Stream
    EXECUTE IMMEDIATE :createDropStreamStmt;
    -- Drop Task
    EXECUTE IMMEDIATE :createDropTaskStmt;
    -- Delete Cache Entry
    EXECUTE IMMEDIATE :deleteCacheEntryStmt;
END;
$$;

// =================================================
//  Testing
// =================================================
CALL CPE_DEV.TEST.registerCacheTable('CPE_DEV', 'TEST', 'TEST1');
CALL CPE_DEV.TEST.registerCacheTable('CPE_DEV', 'TEST', 'TEST2');

CALL CPE_DEV.TEST.unRegisterCacheTable('CPE_DEV', 'TEST', 'TEST1');
CALL CPE_DEV.TEST.unRegisterCacheTable('CPE_DEV', 'TEST', 'TEST2');


CALL CPE_DEV.DB_CACHE.registerCacheTableV2('CPE_DEV', 'TEST', 'TEST1');


// =================================================
//  Register - Simplified
// =================================================
CREATE OR REPLACE PROCEDURE CPE_DEV.TEST.registerCacheTableV3(
    db_name      STRING,
    schema_name  STRING,
    table_name   STRING
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    cachSchmPrefix STRING := CURRENT_DATABASE() || '.' || CURRENT_SCHEMA() || '.';
    tbl            STRING := db_name || '.' || schema_name || '.' || table_name;
    cacheTbl       STRING := cachSchmPrefix || 'CACHE_LOG';
    strm           STRING := cachSchmPrefix || '"STREAM_' || tbl || '"';
    tsk            STRING := cachSchmPrefix || '"STREAM_TASK_' || tbl || '"';
    drain          STRING := cachSchmPrefix || 'DRAIN';
    createTask     STRING;
BEGIN
    -- Create Stream
    CREATE OR REPLACE STREAM IDENTIFIER(:strm) ON TABLE IDENTIFIER(:tbl);

    -- Create Trigger Task
    createTask :=
    'create or replace task IDENTIFIER(''' || :tsk || ''')
        target_completion_interval=''1 MINUTES''
        when SYSTEM$STREAM_HAS_DATA(''' || :strm || ''')
        as
        begin
        merge into IDENTIFIER(''' || :cacheTbl || ''') as target
           using (
             select ''' || :tbl || ''' as TABLE_NAME
          ) as source
             on target.TABLE_NAME = source.TABLE_NAME
             when matched then update set
                 target.TABLE_NAME = source.TABLE_NAME,
                 target.OPERATION_TIME = CURRENT_TIMESTAMP()
             when not matched then
                 insert (TABLE_NAME, OPERATION_TIME)
                 values (source.TABLE_NAME, CURRENT_TIMESTAMP());

        create or replace temporary table IDENTIFIER(''' || :drain || ''') as
            select * from IDENTIFIER(''' || :strm || ''');
        end;';
    EXECUTE IMMEDIATE :createTask;

    -- Merge Record Into Cache
    MERGE INTO IDENTIFIER(:cacheTbl) AS target
    USING (
        SELECT :tbl AS TABLE_NAME
    ) AS source
        ON target.TABLE_NAME = source.TABLE_NAME
        WHEN MATCHED THEN UPDATE SET
            target.TABLE_NAME = source.TABLE_NAME,
            target.OPERATION_TIME = CURRENT_TIMESTAMP()
        WHEN NOT MATCHED THEN
            INSERT (TABLE_NAME, OPERATION_TIME)
            VALUES (source.TABLE_NAME, CURRENT_TIMESTAMP());

    -- Start Trigger Task
    ALTER TASK IDENTIFIER(:tsk) RESUME;

    -- Return Success Message
    RETURN 'Table Registered ' || :tbl || ' successfully.';

EXCEPTION
    WHEN OTHER THEN
        RETURN 'Table Registration Failed = ' || SQLERRM;
END;
$$;


// =================================================
// Create Procedure to UnRegister Cache Table
// =================================================
CREATE OR REPLACE PROCEDURE CPE_DEV.TEST.unRegisterCacheTableV3( db_name STRING, schema_name STRING, table_name STRING )
    RETURNS STRING
    LANGUAGE SQL
    EXECUTE AS OWNER
AS
$$
DECLARE
    cachSchmPrefix STRING := CURRENT_DATABASE() || '.' || CURRENT_SCHEMA() || '.';
    cacheTbl STRING := cachSchmPrefix || 'CACHE_LOG';
    tbl STRING := db_name || '.' || schema_name || '.' || table_name;
    strm STRING := :cachSchmPrefix || '"STREAM_' || :tbl || '"';
    tsk STRING := :cachSchmPrefix || '"STREAM_TASK_' || :tbl || '"';
BEGIN
    -- Suspend Trigger Task
    ALTER TASK IDENTIFIER(:tsk) SUSPEND;
    -- Drop Stream
    DROP STREAM IF EXISTS IDENTIFIER(:strm);
    -- Drop Task
    DROP TASK IF EXISTS IDENTIFIER(:tsk);
    -- Delete Cache Entry
    DELETE FROM IDENTIFIER(:cacheTbl) WHERE TABLE_NAME = :tbl;

    -- Return Success Message
    RETURN 'Table UnRegistered ' || :tbl || ' successfully.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Table UnRegistration Failed = ' || SQLERRM;
END;
$$;



CREATE OR REPLACE TABLE CPE_DEV.TEST.TEST2 (
    first_name STRING,
    last_name STRING
);

TRUNCATE TABLE CPE_DEV.TEST.CACHE_LOG;
SELECT * FROM CPE_DEV.TEST.CACHE_LOG;

TRUNCATE TABLE CPE_DEV.TEST.TEST2;
INSERT INTO CPE_DEV.TEST.TEST2 (first_name, last_name) VALUES ('DD', 'LO');
SELECT * FROM CPE_DEV.TEST.TEST2;

SELECT * FROM CPE_DEV.TEST."STREAM_CPE_DEV.TEST.TEST2";
DESCRIBE STREAM CPE_DEV.TEST."STREAM_CPE_DEV.TEST.TEST2";

CALL CPE_DEV.DB_CACHE.unRegisterCacheTable('CPE_DEV', 'TEST', 'TEST2');
CALL CPE_DEV.DB_CACHE.registerCacheTable('CPE_DEV', 'TEST', 'TEST2');

-- See Catch Log With Offset
SELECT * FROM  CPE_DEV.DB_CACHE.CACHE_LOG AT(OFFSET => -30*1) WHERE TABLE_NAME = 'CPE_DEV.TEST.TEST2' ;
SELECT * FROM  CPE_DEV.DB_CACHE.CACHE_LOG WHERE TABLE_NAME = 'CPE_DEV.TEST.TEST2';