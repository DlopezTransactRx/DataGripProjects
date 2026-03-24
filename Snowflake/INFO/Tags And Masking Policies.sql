USE ROLE ACCOUNTADMIN;
USE DATABASE ACCOUNT_OPERATIONS;
USE SCHEMA GOVERNANCE;

//====================================================================================================
// TAGS
//====================================================================================================

-- Show All Tags
SHOW TAGS;

-- Identify All Tagged Objects
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
  ORDER BY tag_name, domain, object_id;

-- Function - Identify All Columns with Tags
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
            'CPE_DEV.DATA_SCIENCE_SHARE.TEST_DATA_MASKING', -- Table Name
            'TABLE' -- Domain (TABLE, COLUMN, SCHEMA, DATABASE)
    )
);

-- Get Tag Value for Column (DB.SCHEMA.TABLE.COLUMN)
SELECT SYSTEM$GET_TAG(
       'PHI',
       'ACCOUNT_OPERATIONS.GOVERNANCE.TEST.FIRST',
       'COLUMN' -- Domain (TABLE, COLUMN, SCHEMA, DATABASE)
);

/**
 This can only called within the context of a policy. It is essentially the POLICIES equivalent to called SYSTEM$GET_TAG for a column.
  You could use it for the logic within a policy.  You could check if the value is 'X' then switch return value.

  SYSTEM$GET_TAG_ON_CURRENT_COLUMN('ACCOUNT_OPERATIONS.PHI');
 */


//====================================================================================================
// POLICIES
//====================================================================================================
-- Show All Masking Policies
SHOW MASKING POLICIES;

-- Describe a Masking Policy
DESCRIBE MASKING POLICY MASK_STRING;

-- Identify All Tagged Objects
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES; --You would need to filter this for MASKING policies and then look for the object of interest in the REFERENCED_OBJECTS column which is a VARIANT array of objects with database, schema, name, and type.

-- Identify All Columns/Tags associated with a particular Masking Policy.
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.POLICY_REFERENCES(
        POLICY_NAME => 'MASK_STRING'
    )
);

/**
  [NOTE] Here is an example how to UNSET a masking policy from a column.
    ALTER TABLE SANDBOX.DLOPEZ.TEST MODIFY COLUMN NAME UNSET MASKING POLICY;
 */

