----------------------------------------------------------------------------------------------------
-- [Bulk Extract - Pre AI Import Process]
----------------------------------------------------------------------------------------------------
WITH target_tables AS (

  SELECT
      -- Target Postgres Database
      '<DATABASE>' as database_name,

      -- Target Postgres Schema
      '<SCHEMA>' as schema_name,

      -- All Target Tables in Schema to Export.
      unnest(ARRAY[
    '<TABLENAME_1>',
    -- ...
    '<TABLENAME_N>'
  ]) AS table_name
),

-- Enhance Target Tables By Including Their PKId
 targetTablesWithPK AS (
  SELECT
      tt.database_name,
      tt.schema_name,
      tt.table_name,
      string_agg(quote_ident(kcu.column_name), ', ' ORDER BY kcu.ordinal_position) AS primary_keys
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema   = kcu.table_schema           -- important
  RIGHT JOIN target_tables tt
        ON kcu.table_catalog = tt.database_name
        AND kcu.table_schema   = tt.schema_name           -- important
        AND kcu.table_name    = tt.table_name
  WHERE tc.constraint_type = 'PRIMARY KEY'
  GROUP BY tt.database_name, tt.schema_name, tt.table_name
 )

-- Indicate The Snowflake Export Values.
SELECT
    -- Table Name For Snowflake
    c.table_name AS raw_table_name,

    -- Code Name Space in Terraform
    '<SNOWFLAKE_NAMESPACE>'  AS namespace,

    -- Database Name In Snowflake
    '<SNOWFLAKE_DATABASE>'       AS database,

    -- Schema Name In Snowflake
    '<SNOWFLAKE_SCHEMA>' AS schema,

    COALESCE(tt.primary_keys, '') AS primary_keys,
    'SELECT ' ||
      string_agg(quote_ident(c.column_name), ', ' ORDER BY c.ordinal_position) ||
      ' FROM ' || quote_ident(c.table_schema) || '.' || quote_ident(c.table_name) || ';' AS sql_select
FROM information_schema.columns c
RIGHT JOIN targetTablesWithPK tt
  ON tt.database_name = c.table_catalog
 AND tt.schema_name  = c.table_schema
 AND tt.table_name    = c.table_name
GROUP BY c.table_schema, c.table_name, tt.primary_keys;
;