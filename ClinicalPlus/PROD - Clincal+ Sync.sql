SELECT * FROM db_exported_control;

SELECT 'patient' as table_name, count(*) as record_count FROM patient
UNION ALL
SELECT 'patient_rx' as table_name, count(*) as record_count FROM patient_rx
UNION ALL
SELECT 'campaign_alert_history' as table_name, count(*) as record_count FROM campaign_alert_history
;

SELECT * FROM campaign_alert_history limit 10;

SELECT * FROM campaign;

SELECT * FROM patient LIMIT 10;