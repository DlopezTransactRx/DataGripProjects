select * from jwt_accounts
--     WHERE client_id ILIKE ANY (
--         ARRAY[
--             '%clinical-plus%',
--             '%ras%',
--             '%baz%' ]
--         )
;

select * from jwt_credentials
--     WHERE client_id ILIKE ANY (
--         ARRAY[
--             '%clinical-plus%',
--             '%ras%',
--             '%baz%' ]
--         )
;