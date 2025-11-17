SELECT *
FROM information_schema.columns
WHERE table_schema = 'public'
-- AND table_name   = 'programs'
AND column_name  = 'db_export_record_version';

SELECT * FROM db_exported_control;

-- RAW TABLE COUNTS
SELECT 'CAMPAIGN_ALERT_HISTORY' AS TABLE_NAME, COUNT(*) AS CNT FROM campaign_alert_history
UNION ALL
SELECT 'PATIENT' AS TABLE_NAME, COUNT(*) AS CNT FROM patient
UNION ALL
SELECT 'PATIENT_RX' AS TABLE_NAME, COUNT(*) AS CNT FROM patient_rx
;


SELECT
  campaign_alert_history_id::varchar,
  campaign_workflow_id::varchar,
  is_successful::varchar,
  alerted_on::varchar,
  patient_id_hash::varchar,
  notification_reponse_id::varchar,
  location_npi::varchar,
  campaign_id::varchar,
  responsed_on::varchar,
  patient_rx_id::varchar,
  notification_id::varchar,
  notification_type_id::varchar,
  workflow_type_id::varchar,
  db_export_record_version
FROM campaign_alert_history
ORDER BY db_export_record_version ASC;

SELECT
    patient_id_hash,
    first_name,
    last_name,
    date_of_birth,
    location_npi,
    opt_in_secure_messaging,
    opt_in_sms,
    opt_in_email,
    home_phone,
    mobile_phone,
    email,
    rxlocal_patient_id,
    notification_phone,
    updated_on,
    work_phone,
    patient_code,
    status,
    gender,
    race,
    ethnicity,
    language,
    db_export_record_version
FROM patient
ORDER BY db_export_record_version ASC
LIMIT 10;

SELECT
    patient_rx_id,
    patient_id_hash,
    rx_number,
    fill_number,
    npi,
    date_filled,
    date_written,
    product_uom,
    product_ndc,
    product_name,
    daw,
    refills_total,
    refills_remaining,
    quantity,
    quantity_dispensed,
    days_supply,
    sig,
    diagnostic_code,
    renewal_indicator,
    prescription_form,
    patient_pay,
    workflow_type_id,
    date_sold,
    start_date,
    completion_method,
    updated_on,
    db_export_record_version
FROM patient_rx
ORDER BY db_export_record_version ASC
LIMIT 10;

SELECT 'campaign_alert_history' as "TABLENAME", count(*) from campaign_alert_history --958
UNION ALL
SELECT 'patient' as "TABLENAME",count(*) from patient --542
UNION ALL
SELECT 'patient_rx' as "TABLENAME",count(*) from patient_rx; --
