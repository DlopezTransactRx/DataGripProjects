USE DATABASE CPE_DEV;

SELECT SYSTEM$CLUSTERING_INFORMATION('STAGING.STAGE_EVENTS');

//=====================================================================
// Get the existing Clustering_Key Configured For a table.
//=====================================================================
SELECT CLUSTERING_KEY
FROM CPE_PROD.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'STAGING'
    AND TABLE_NAME = 'STAGE_EVENTS';

//=====================================================
// [DEV] Cluster Information (2005-09-17)
//=====================================================

//-=[Cluster Key Used]----------------------------------
-- LINEAR(
--     COALESCE(
--       DATE_TRUNC('hour', TRY_TO_TIMESTAMP(DATA:eventTime::string)),
--       TO_TIMESTAMP_NTZ('1970-01-01 00:00:00') -- Partition For Bad Dates.
--     ),
--     DATA:eventType::string
-- )

//-=[Cluster Info]-------------------------------------
-- {
--   "cluster_by_keys" : "LINEAR(\n    COALESCE(\n      DATE_TRUNC('hour', TRY_TO_TIMESTAMP(DATA:eventTime::string)),\n      TO_TIMESTAMP_NTZ('1970-01-01 00:00:00') -- Partition For Bad Dates.\n    ),\n    DATA:eventType::string\n)",
--   "total_partition_count" : 3813,
--   "total_constant_partition_count" : 3362,
--   "average_overlaps" : 3.219,
--   "average_depth" : 3.593,
--   "partition_depth_histogram" : {
--     "00000" : 0,
--     "00001" : 3180,
--     "00002" : 32,
--     "00003" : 44,
--     "00004" : 60,
--     "00005" : 40,
--     "00006" : 66,
--     "00007" : 49,
--     "00008" : 27,
--     "00009" : 30,
--     "00010" : 19,
--     "00011" : 0,
--     "00012" : 12,
--     "00013" : 0,
--     "00014" : 20,
--     "00015" : 0,
--     "00016" : 13,
--     "00032" : 148,
--     "00064" : 73
--   },
--   "clustering_errors" : [ ]
-- }

//====================================================================================================
//====================================================================================================
//====================================================================================================


//=====================================================
// [DEV] Change Cluster (2025-09-17)
//=====================================================
ALTER TABLE CPE_DEV.STAGING.STAGE_EVENTS
 CLUSTER BY (
   TRY_TO_DATE(DATA:eventTime::varchar),
   DATA:eventType::VARCHAR
);


// NEED TO CAPTURE THE CLUSTER KEYS