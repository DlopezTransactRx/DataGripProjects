-- Clinical+ Counts (Postgres)
SELECT 'Campaign' AS object_name, COUNT(*) AS row_count FROM campaign
UNION ALL
SELECT 'Campaign_Alert_History' AS object_name, COUNT(*) AS row_count FROM Campaign_Alert_History
UNION ALL
SELECT 'Campaign_Criteria' AS object_name, COUNT(*) AS row_count FROM Campaign_Criteria
UNION ALL
SELECT 'Campaign_Criteria_Type' AS object_name, COUNT(*) AS row_count FROM Campaign_Criteria_Type
UNION ALL
SELECT 'Campaign_Notification_Text' AS object_name, COUNT(*) AS row_count FROM Campaign_Notification_Text
UNION ALL
SELECT 'Campaign_Notification_Version' AS object_name, COUNT(*) AS row_count FROM Campaign_Notification_Version
UNION ALL
SELECT 'Campaign_Patient' AS object_name, COUNT(*) AS row_count FROM Campaign_Patient
UNION ALL
SELECT 'Campaign_Patient_Notification' AS object_name, COUNT(*) AS row_count FROM Campaign_Patient_Notification
UNION ALL
SELECT 'Campaign_Pharmacy_Notification' AS object_name, COUNT(*) AS row_count FROM Campaign_Pharmacy_Notification
UNION ALL
SELECT 'Campaign_Status' AS object_name, COUNT(*) AS row_count FROM Campaign_Status
UNION ALL
SELECT 'Campaign_Type' AS object_name, COUNT(*) AS row_count FROM Campaign_Type
UNION ALL
SELECT 'Campaign_Workflow' AS object_name, COUNT(*) AS row_count FROM Campaign_Workflow
UNION ALL
SELECT 'Image' AS object_name, COUNT(*) AS row_count FROM Image
UNION ALL
SELECT 'Label_Type' AS object_name, COUNT(*) AS row_count FROM Label_Type
UNION ALL
SELECT 'Language_Type' AS object_name, COUNT(*) AS row_count FROM Language_Type
UNION ALL
SELECT 'Location' AS object_name, COUNT(*) AS row_count FROM Location
UNION ALL
SELECT 'Location_Filter_Type' AS object_name, COUNT(*) AS row_count FROM Location_Filter_Type
UNION ALL
SELECT 'Location_Opt_In_Campaign' AS object_name, COUNT(*) AS row_count FROM Location_Opt_In_Campaign
UNION ALL
SELECT 'Location_Opt_Out_Campaign' AS object_name, COUNT(*) AS row_count FROM Location_Opt_Out_Campaign
UNION ALL
SELECT 'Notification_Response' AS object_name, COUNT(*) AS row_count FROM Notification_Response
UNION ALL
SELECT 'Notification_Type' AS object_name, COUNT(*) AS row_count FROM Notification_Type
UNION ALL
SELECT 'Opt_Status' AS object_name, COUNT(*) AS row_count FROM Opt_Status
UNION ALL
SELECT 'Patient' AS object_name, COUNT(*) AS row_count FROM Patient
UNION ALL
SELECT 'Patient_Opt_Out_Campaign' AS object_name, COUNT(*) AS row_count FROM Patient_Opt_Out_Campaign
UNION ALL
SELECT 'Patient_Rx' AS object_name, COUNT(*) AS row_count FROM Patient_Rx
UNION ALL
SELECT 'Patient_Rx_Opt_Out_Campaign' AS object_name, COUNT(*) AS row_count FROM Patient_Rx_Opt_Out_Campaign
UNION ALL
SELECT 'Patient_Rx_Payment_Info' AS object_name, COUNT(*) AS row_count FROM Patient_Rx_Payment_Info
UNION ALL
SELECT 'Patient_Rx_Prescriber_Info' AS object_name, COUNT(*) AS row_count FROM Patient_Rx_Prescriber_Info
UNION ALL
SELECT 'Rx_Voucher' AS object_name, COUNT(*) AS row_count FROM Rx_Voucher
UNION ALL
SELECT 'Successful_Alert_Type' AS object_name, COUNT(*) AS row_count FROM Successful_Alert_Type
UNION ALL
SELECT 'Table_Log' AS object_name, COUNT(*) AS row_count FROM Table_Log
UNION ALL
SELECT 'Third_Party_Type' AS object_name, COUNT(*) AS row_count FROM Third_Party_Type
UNION ALL
SELECT 'Vendor_API_Setting' AS object_name, COUNT(*) AS row_count FROM Vendor_API_Setting
UNION ALL
SELECT 'Vendor_Patient' AS object_name, COUNT(*) AS row_count FROM Vendor_Patient
UNION ALL
SELECT 'Vendor_Type' AS object_name, COUNT(*) AS row_count FROM Vendor_Type
UNION ALL
SELECT 'Voucher_Status' AS object_name, COUNT(*) AS row_count FROM Voucher_Status
UNION ALL
SELECT 'Workflow_Type' AS object_name, COUNT(*) AS row_count FROM Workflow_Type

ORDER BY object_name ASC;


-- Campaign_Alert_History 371681
-- Patient 27308970
-- Patient_Rx 261789755
-- Patient_Rx_Payment_Info 108550238
-- Patient_Rx_Prescriber_Info 121515100