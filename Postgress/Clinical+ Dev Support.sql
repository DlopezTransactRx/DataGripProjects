-- DEV
SELECT * FROM vendor_api_setting;

-- DB EXPORT CONTROL
SELECT * FROM db_exported_control;


-- Postgres (DEV) --
SELECT 'voucher_status' AS table_name, COUNT(*) AS row_count FROM voucher_status
UNION ALL
SELECT 'vendor_api_settings' AS table_name, COUNT(*) AS row_count FROM vendor_api_setting
UNION ALL
SELECT 'campaign', COUNT(*) FROM campaign
UNION ALL
SELECT 'campaign_criteria', COUNT(*) FROM campaign_criteria
UNION ALL
SELECT 'campaign_criteria_type', COUNT(*) FROM campaign_criteria_type
UNION ALL
SELECT 'campaign_notification_text', COUNT(*) FROM campaign_notification_text
UNION ALL
SELECT 'campaign_notification_version', COUNT(*) FROM campaign_notification_version
UNION ALL
SELECT 'campaign_patient_notification', COUNT(*) FROM campaign_patient_notification
UNION ALL
SELECT 'campaign_patient', COUNT(*) FROM campaign_patient
UNION ALL
SELECT 'campaign_pharmacy_notification', COUNT(*) FROM campaign_pharmacy_notification

ORDER BY table_name desc
;
