----------------------------------------------------------------------------------------------------
-- Discrepent Email - Research
----------------------------------------------------------------------------------------------------
DECLARE
  sql_text STRING;
BEGIN
  WITH target_objects (db, sch, obj_type, name) AS (
    SELECT * FROM VALUES

      --------------------------------------------------------
      --NOTE: Substitute this with those tables in the email.
      --------------------------------------------------------

      ('CPE_PROD','DATA','TABLE','MPI_CLAIM_DEDUP_20260813'),
      ('CPE_PROD','DATA','TABLE','MPI_DEDUP_CANDIDATES_WEEKLY'),
      ('CPE_PROD','DATA','TABLE','MPI_BLEED_RATE_DAILY'),
      ('CPE_PROD','DATA','TABLE','MPI_LINK_EVENT_TS_20260813'),
      ('CPE_PROD','DATA','TABLE','TEMP_BESTRX_CRM'),
      ('CPE_PROD','DATA','TABLE','MPI_NEAR_MISS_DAILY'),
      ('CPE_PROD','DATA','TABLE','MPI_ID_TO_CLAIM_RECORD_ID_BAK_20260813'),
      ('CPE_DEV', 'DATA','TABLE','MPI_ID_TO_CLAIM_RECORD_ID_BAK_20260812'),
      ('CPE_PROD','DATA','VIEW','MPI_NEAR_MISS_DAILY'),
      ('CPE_PROD','DATA','VIEW','MPI_BLEED_RATE_DAILY'),
      ('CPE_PROD','DATA_COLLECTIONS','TABLE','DC_NUVEM_TEST_WORK'),
      ('CPE_PROD','DATA_COLLECTIONS','TABLE','DC_RESOLVERX_WORK'),
      ('CPE_PROD','DATA_COLLECTIONS','TABLE','DC_RECRX_WORK'),
      ('CPE_PROD','DATA_COLLECTIONS','TABLE','DC_INNOVATIX_WORK'),
      ('CPE_DEV', 'DATA_COLLECTIONS','TABLE','DC_DELIVERY_QUEUE'),
      ('CPE_PROD','DATA_COLLECTIONS','TABLE','DC_CARDINAL_ANALYSIS'),
      ('CPE_PROD','DATA_COLLECTIONS','TABLE','DC_RECONRX_CASH_WORK'),
      ('CPE_PROD','DATA_COLLECTIONS','TABLE','DC_CARDINAL_CAH_WORK'),
      ('CPE_PROD','DATA_COLLECTIONS','TABLE','DC_CIRRUS_WORK'),
      ('CPE_PROD','DATA_COLLECTIONS','TABLE','DC_CLEARMETRX_WORK'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_MAX_ALERT_PERIOD_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_GROUP_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_PATIENT_INELIGIBLE_QUEUE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_ALERT_DATASET_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_SETTING_LOCATION_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_ALERT_RULE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_THIRDPARTY_EXECUTION_CONDITIONS_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_GROUP_CAMPAIGN_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_OPP_QUEUE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_GENERAL_QUEUE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_ALERT_PARAM_PRESET_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_CRITERIA_TYPE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_ALERT_RULE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','TP_FDB_ITEM'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_SETTING_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_RX_VOUCHER_UNMATCHED_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_QUEUE_TYPE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_CAMPAIGN_SETTING_DEFAULT_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','TABLE','CLINICALPLUS_REFILL_REMINDER_QUEUE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_CRITERIA_TYPE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_MAX_ALERT_PERIOD_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_THIRDPARTY_EXECUTION_CONDITIONS_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_QUEUE_TYPE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_SETTING_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_GENERAL_QUEUE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_GROUP_CAMPAIGN_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_SETTING_LOCATION_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_SETTING_DEFAULT_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_REFILL_REMINDER_QUEUE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_ALERT_RULE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_RX_VOUCHER_UNMATCHED_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_OPP_QUEUE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_PATIENT_INELIGIBLE_QUEUE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_GROUP_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_CAMPAIGN_ALERT_RULE_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_ALERT_DATASET_VIEW'),
      ('CPE_DEV','DATA_SCIENCE_SHARE','VIEW','CLINICALPLUS_ALERT_PARAM_PRESET_VIEW'),
      ('CPE_PROD','PRIMERX_SALESFORCE','TABLE','TEMP_TASKCSV'),
      ('CPE_PROD','STAGING','TABLE','EVENTS_TABLE'),
      ('CPE_PROD','STAGING','TABLE','COPAY_CLAIMS'),
      ('CPE_PROD','STAGING','VIEW','COPAY_CLAIMS')
  ),
  per_db AS (
    SELECT db,
           LISTAGG('(''' || sch || ''',''' || name || ''',''' ||
                   IFF(obj_type = 'VIEW', 'VIEW', 'BASE TABLE') || ''')', ',')
             AS tuple_list
    FROM target_objects
    GROUP BY db
  )
  SELECT 'CREATE OR REPLACE TEMPORARY TABLE OBJECT_METADATA_RAW AS '
         || LISTAGG(
              'SELECT table_catalog, table_schema, table_name, table_type, '
              || 'table_owner, created, last_altered '
              || 'FROM ' || db || '.INFORMATION_SCHEMA.TABLES '
              || 'WHERE (table_schema, table_name, table_type) IN (' || tuple_list || ')',
              ' UNION ALL '
            )
    INTO :sql_text
  FROM per_db;

  EXECUTE IMMEDIATE :sql_text;
  RETURN 'OBJECT_METADATA_RAW loaded';
END;



----------------------------------------------------------------------------------------------------

WITH object_metadata AS (
  SELECT * FROM OBJECT_METADATA_RAW
),
create_candidates AS (
  SELECT m.table_catalog,
         m.table_schema,
         m.table_name,
         m.table_type,
         m.table_owner,
         m.created,
         q.query_id,
         q.user_name,
         q.role_name,
         q.warehouse_name,
         q.query_type,
         q.start_time      AS statement_start,
         q.end_time        AS statement_end,
         q.query_text,
         ABS(TIMESTAMPDIFF(second, q.end_time, m.created)) AS seconds_off
  FROM   object_metadata m
  JOIN   SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY q
    ON   q.database_name = m.table_catalog
   AND   q.schema_name   = m.table_schema
   AND   q.execution_status = 'SUCCESS'
   AND   q.query_type IN ('CREATE_TABLE','CREATE_TABLE_AS_SELECT',
                          'CREATE_VIEW','CREATE','RENAME_TABLE')
   AND   q.query_text ILIKE '%' || m.table_name || '%'
   AND   q.end_time BETWEEN DATEADD(minute, -5, m.created)
                        AND DATEADD(minute,  5, m.created)
)
SELECT *
FROM   create_candidates
QUALIFY ROW_NUMBER() OVER (
          PARTITION BY table_catalog, table_schema, table_name, table_type
          ORDER BY seconds_off
        ) = 1
ORDER BY table_catalog, table_schema, table_name;