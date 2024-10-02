-- Creating table to store basic domain information
CREATE TABLE domains (
    domain_id SERIAL PRIMARY KEY,  -- Unique identifier for each domain
    domain_name VARCHAR(255) NOT NULL,  -- Name of the domain (e.g., example)
    tld VARCHAR(10) NOT NULL,  -- Top-level domain (e.g., .com, .org)
    is_registered BOOLEAN DEFAULT FALSE,  -- Indicates if the domain is registered
    clear_status BOOLEAN DEFAULT TRUE,  -- Indicates if the domain is in a clear state (no issues)
    UNIQUE(domain_name, tld)  -- Ensures that each combination of domain name and TLD is unique
);

-- Creating table to store different flags that can be assigned to domains
CREATE TABLE flags (
    flag_id SERIAL PRIMARY KEY,  -- Unique identifier for each flag
    flag_name VARCHAR(50) UNIQUE NOT NULL  -- Name of the flag (e.g., "EXPIRED", "OUTZONE"), must be unique
);

-- Creating table to store changes related to domain registrations
CREATE TABLE domain_registration_changes (
    change_id SERIAL PRIMARY KEY,  -- Unique identifier for each change
    domain_id INT REFERENCES domains(domain_id),  -- Reference to the domain that is being changed
    change_time TIMESTAMP DEFAULT NOW() NOT NULL,  -- Timestamp of the change, defaults to the current time
    registration_changed_to BOOLEAN NOT NULL  -- TRUE if registered, FALSE if unregistered
);

-- Prevent inserting the same registration state for the given domain
CREATE OR REPLACE FUNCTION prevent_duplicate_registration_state()
RETURNS TRIGGER AS $$
DECLARE
    last_registration_state BOOLEAN;  -- Variable to store the last registration state
BEGIN
    -- Retrieve the most recent registration state for the same domain_id
    SELECT registration_changed_to
    INTO last_registration_state
    FROM domain_registration_changes
    WHERE domain_id = NEW.domain_id
    ORDER BY change_time DESC
    LIMIT 1;

    -- If the most recent change has the same registration state as the new one, raise an exception
    IF FOUND AND last_registration_state = NEW.registration_changed_to THEN
        RAISE EXCEPTION 'Duplicate registration state not allowed for domain_id %', NEW.domain_id;
    END IF;

    -- If no such record exists or the registration state is different, proceed with the insertion
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create a trigger to invoke the function before inserting a new record into the domain_registration_changes table
CREATE TRIGGER check_duplicate_registration_state
BEFORE INSERT ON domain_registration_changes  -- Trigger is fired before an insert operation
FOR EACH ROW  -- This trigger will run for each row that is about to be inserted
EXECUTE FUNCTION prevent_duplicate_registration_state();  -- Execute the function defined above


-- Creating table to store changes to domain flags
CREATE TABLE domain_flag_changes (
    change_id SERIAL PRIMARY KEY,  -- Unique identifier for each flag change
    domain_id INT REFERENCES domains(domain_id),  -- Reference to the domain that the flag is applied to
    flag_id INT REFERENCES flags(flag_id),  -- Reference to the flag that is being changed
    change_time TIMESTAMP DEFAULT NOW() NOT NULL,  -- Timestamp of the flag change, defaults to the current time
    flag_set_to BOOLEAN NOT NULL,  -- TRUE if the flag is set, FALSE if the flag is removed
    valid_until TIMESTAMP DEFAULT 'infinity',  -- Defines how long the flag is valid, default is indefinitely
    CONSTRAINT valid_until_after_change CHECK (valid_until > change_time OR valid_until = 'infinity')  -- Ensures valid_until is after change_time or is infinity
);

-- ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- Query to get all fully qualified domains that are registered and have a clear status
SELECT d.domain_name || '.' || d.tld AS fully_qualified_domain
FROM domains d
WHERE d.is_registered = TRUE
  AND d.clear_status = TRUE;

-- Query to get all fully qualified domains that are registered and do not have an active "EXPIRED" flag
SELECT d.domain_name || '.' || d.tld AS fully_qualified_domain
FROM domains d
WHERE d.is_registered = TRUE
  AND NOT EXISTS (
      SELECT 1
      FROM domain_flag_changes df
      WHERE df.domain_id = d.domain_id
        AND df.flag_id = (SELECT flag_id FROM flags WHERE flag_name = 'EXPIRED')  -- Checks if the domain has an "EXPIRED" flag
        AND df.flag_set_to = TRUE  -- Checks if the flag is currently set
        AND (df.valid_until IS NULL OR df.valid_until > NOW())  -- Ensures the flag is still valid
  );

-- Query to get all fully qualified domains that have both the "EXPIRED" and "OUTZONE" flags set
SELECT DISTINCT d.domain_name || '.' || d.tld AS fully_qualified_domain
FROM domains d
WHERE EXISTS (
    SELECT 1
    FROM domain_flag_changes df_exp
    WHERE d.domain_id = df_exp.domain_id
      AND df_exp.flag_id = (SELECT flag_id FROM flags WHERE flag_name = 'EXPIRED')  -- Checks for "EXPIRED" flag
      AND df_exp.flag_set_to = TRUE
) 
AND EXISTS (
    SELECT 1
    FROM domain_flag_changes df_out
    WHERE d.domain_id = df_out.domain_id
      AND df_out.flag_id = (SELECT flag_id FROM flags WHERE flag_name = 'OUTZONE')  -- Checks for "OUTZONE" flag
      AND df_out.flag_set_to = TRUE
);

-- Creating a view to show active domain flags (only the most recent valid state)
CREATE VIEW active_domain_flags AS
WITH ranked_flags AS (
    SELECT
        domain_id,
        flag_id,
        change_time AS valid_from,
        valid_until,
        flag_set_to,
        ROW_NUMBER() OVER (PARTITION BY domain_id, flag_id ORDER BY change_time DESC) AS rn
    FROM domain_flag_changes
    WHERE flag_set_to = TRUE  -- Only consider flags that are set to TRUE
)
SELECT domain_id, flag_id, valid_from, valid_until
FROM ranked_flags
WHERE rn = 1 AND (valid_until IS NULL OR valid_until > NOW());  -- Get the most recent valid flag

-- ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
-- Insert some testing data

INSERT INTO domains (domain_name, tld, is_registered, clear_status) VALUES
    ('example', 'com', TRUE, TRUE),
    ('example', 'net', FALSE, TRUE),
    ('testdomain', 'org', TRUE, FALSE),
    ('sampledomain', 'com', FALSE, TRUE),
    ('mywebsite', 'net', TRUE, TRUE),
    ('overlapdomain', 'com', TRUE, TRUE),
    ('uniquedomain', 'io', FALSE, TRUE),
    ('activeexpired', 'net', TRUE, TRUE);

INSERT INTO flags (flag_name) VALUES
    ('EXPIRED'),
    ('OUTZONE'),
    ('DELETE_CANDIDATE');

INSERT INTO domain_registration_changes (domain_id, change_time, registration_changed_to) VALUES
    (1, '2024-01-01 10:00:00', TRUE),
    (1, '2024-06-01 15:00:00', FALSE),
    (2, '2023-03-15 08:00:00', TRUE),
    (3, '2024-02-20 12:00:00', TRUE),
    (4, '2023-11-11 09:00:00', FALSE),
    (5, '2024-05-10 11:00:00', TRUE),
    (6, '2024-07-21 13:00:00', TRUE);

-- Insert test data into 'domain_flag_changes' table
INSERT INTO domain_flag_changes (domain_id, flag_id, change_time, flag_set_to, valid_until) VALUES
    -- example.com domain gets the EXPIRED flag set, which is then removed
    (1, 1, '2024-01-01 10:00:00', TRUE, '2024-06-01 15:00:00'),  -- EXPIRED flag set on 2024-01-01
    (1, 1, '2024-06-01 15:00:01', FALSE, 'infinity'),  -- EXPIRED flag removed right after
    -- testdomain.org gets an OUTZONE flag set indefinitely
    (3, 2, '2024-03-01 00:00:00', TRUE, 'infinity'),  -- OUTZONE flag set indefinitely
    -- mywebsite.net gets DELETE_CANDIDATE flag set and removed after a period
    (5, 3, '2024-05-10 11:00:00', TRUE, '2024-06-10 11:00:00'),  -- DELETE_CANDIDATE flag set on 2024-05-10
    (5, 3, '2024-06-10 11:00:01', FALSE, 'infinity'),  -- DELETE_CANDIDATE flag removed on 2024-06-10
    -- overlapdomain.com with multiple changes of the EXPIRED flag
    (6, 1, '2024-07-21 13:00:00', TRUE, 'infinity'),  -- EXPIRED flag set indefinitely
    (6, 1, '2024-09-01 09:00:00', FALSE, 'infinity');  -- EXPIRED flag removed later
