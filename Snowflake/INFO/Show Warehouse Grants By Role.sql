SHOW ROLES;

SHOW GRANTS TO ROLE DATA_COLLECTIONS_DEV;
SELECT * FROM TABLE (result_scan(last_query_id())) as rs
where rs."granted_on" = 'WAREHOUSE';

SHOW GRANTS TO ROLE DATA_COLLECTIONS_PROD;
SELECT * FROM TABLE (result_scan(last_query_id())) as rs
where rs."granted_on" = 'WAREHOUSE';

SHOW GRANTS TO ROLE DATA_SCIENCE_DEV;
SELECT * FROM TABLE (result_scan(last_query_id())) as rs
where rs."granted_on" = 'WAREHOUSE';

SHOW GRANTS TO ROLE DATA_SCIENCE_PROD;
SELECT * FROM TABLE (result_scan(last_query_id())) as rs
where rs."granted_on" = 'WAREHOUSE';