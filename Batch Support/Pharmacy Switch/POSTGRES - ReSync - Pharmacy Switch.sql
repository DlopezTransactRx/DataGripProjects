-- ====================================================================================================
-- [POSTGRES] NOTE: New Columns Added to Support PPE Rules Not In Snowflake.
-- ====================================================================================================
SELECT ppe_rule_base_id FROM pharmacy_switch_service where ppe_rule_base_id IS NOT NULL;
SELECT direct_override, insert_intermediary_auth_code, ppe_type, record_status FROM switch_service;


-- ====================================================================================================
-- [POSTGRES] Source Table Counts
-- ====================================================================================================

--Db Export Control Entries
SELECT * FROM db_exported_control
WHERE event_type IN (
    'PharmacySwitchServiceTableRecord',
    'SwitchServiceTableRecord'
);
-- Sample Data
SELECT * FROM pharmacy_switch_service;
SELECT * FROM switch_service;

-- Describe Tables
SELECT column_name, data_type, is_nullable, column_default, table_name
FROM information_schema.columns
WHERE table_name in
(
--     'pharmacy_switch_service'--,
    'switch_service'
)
ORDER BY table_name, column_name
;

--====================================================================================================
-- [POSTGRES] Modify Export Index
-- ====================================================================================================

-- Source Record Counts
SELECT 'pharmacy_switch_service' as tableName, COUNT(*) as cnt FROM pharmacy_switch_service
UNION ALL
SELECT 'switch_service' as tableName, COUNT(*) as cnt FROM switch_service;