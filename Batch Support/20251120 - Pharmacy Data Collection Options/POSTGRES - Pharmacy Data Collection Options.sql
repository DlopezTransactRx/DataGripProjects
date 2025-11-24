-- Db Export Control Entries
SELECT * FROM db_exported_control WHERE event_type ILIKE '%data-collection%';

-- Count Of Records in pharmacy_data_collection_options
SELECT COUNT(*) FROM pharmacy_data_collection_options;

-- Sample Data
SELECT id FROM pharmacy_data_collection_options;

-- Sample Data - Missing Records In Snowflake.
WITH idsInSnowflake AS (
    SELECT DISTINCT value::numeric AS recordId
    FROM unnest(string_to_array(
        -- List of Snowflake Ids
        '1421187327057448960'
        , ',')) AS value
)
SELECT *
FROM pharmacy_data_collection_options as o
WHERE o.id IN (SELECT recordId FROM idsInSnowflake);