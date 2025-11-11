--====================================================================================================
-- [POSTGRES] Source Table Counts
-- ====================================================================================================

--Db Export Control Entries
SELECT * FROM db_exported_control
WHERE event_type IN (
    'PharmacySwitchServiceTableRecord',
    'SwitchServiceTableRecord'
);

--====================================================================================================
-- [POSTGRES] Modify Export Index
-- ====================================================================================================

-- Source Record Counts
SELECT 'pharmacy_switch_service_cnt' as tableName, COUNT(*) as cnt FROM pharmacy_switch_service
UNION ALL
SELECT 'switch_service' as tableName, COUNT(*) as cnt FROM switch_service;