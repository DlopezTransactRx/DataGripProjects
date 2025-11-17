-- ====================================================================================================
-- [POSTGRES] Source Table Counts
-- ====================================================================================================

--Db Export Control Entries
SELECT * FROM db_exported_control
WHERE event_type IN (
    'campaign-criteria'
);

-- Sample Data
SELECT * FROM campaign_criteria;

-- Describe Tables
SELECT column_name, data_type, is_nullable, column_default, table_name
FROM information_schema.columns
WHERE table_name in
(
    'campaign_criteria'
)
ORDER BY table_name, column_name
;

--====================================================================================================
-- [POSTGRES] Modify Export Index
-- ====================================================================================================

-- Source Record Counts
SELECT 'campaign_criteria' as tableName, COUNT(*) as cnt FROM campaign_criteria;

SELECT
campaign_criteria_id::varchar,
campaign_id::varchar,
campaign_criteria_type_id::varchar,
ndc::varchar,
refill_due_days_min::varchar,
refill_due_days_max::varchar,
days_supply_max::varchar,
label_type_id::varchar,
gpi::varchar,
db_export_record_version::varchar
FROM campaign_criteria