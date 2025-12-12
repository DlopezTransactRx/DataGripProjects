-- NOTE: This is how you generate a JWT token for users.


----------------------------------------------------------------------------------------------------
-- View Full JWT Account with Credentials
----------------------------------------------------------------------------------------------------
SELECT *
FROM jwt_accounts as a
         JOIN jwt_credentials as c
              ON a.client_id = c.client_id
WHERE a.client_id ILIKE 'ras-testing-dev';

----------------------------------------------------------------------------------------------------
-- JWT Account
----------------------------------------------------------------------------------------------------
select * from jwt_accounts
--     where client_id ILIKE '%daniel%'
;

insert into jwt_accounts (client_id, roles_csv, audiences_csv, claims_kv_csv, token_expiration_hours, token_type, date_added, date_updated, active, portal_account_id) values (
    'ras-testing-dev',
    'ras-testing',
    'ras-testing',
    'clientId:ras-testing,test=helloWorld',
    10,
    'Bearer',
    now(),
    now(),
    true,
    null
);


----------------------------------------------------------------------------------------------------
-- JWT Credentials
----------------------------------------------------------------------------------------------------
select * from jwt_credentials
--     where client_id ILIKE 'daniel-dev-test'
;

insert into jwt_credentials (jwt_credentials_id, client_id, client_secret, expiration, date_added, date_updated) values (
    '123942696997720251126', -- Generate Some Random Big Int.
    'ras-testing-dev',
    '127yzecd-9x8z-6884-5b3x-997Agf287y83', -- Generate Som Client Secret.
    null,
    now(),
    now()
);
