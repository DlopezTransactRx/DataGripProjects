-- Compare Table Version
USE DATABASE CPE_PROD;
USE SCHEMA DATA;

-- Tables To Compare
SET oldTbl = 'BESTRX_CRM_SNAPSHOT';
SET newTbl = 'BESTRX_CRM';

-- CTE Old Column Info
WITH old AS (
    SELECT column_name, data_type, ordinal_position
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE table_schema = CURRENT_SCHEMA()
      AND table_name = $oldTbl
),

 -- CTE New Column Info
 new AS (
     SELECT column_name, data_type, ordinal_position
     FROM INFORMATION_SCHEMA.COLUMNS
     WHERE table_schema = CURRENT_SCHEMA()
       AND table_name = $newTbl
 )

-- Select Only Differences
SELECT *
FROM (
      (SELECT column_name, 'ONLY_IN_OLD' AS status FROM old
       EXCEPT
       SELECT column_name, 'ONLY_IN_OLD' FROM new)

      UNION ALL

      (SELECT column_name, 'ONLY_IN_NEW' AS status FROM new
       EXCEPT
       SELECT column_name, 'ONLY_IN_NEW' FROM old)
      )
ORDER BY column_name;