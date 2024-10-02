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
    registration_changed_to BOOLEAN NOT NULL,  -- TRUE if registered, FALSE if unregistered
    CONSTRAINT check_no_duplicate_registration_state CHECK (  -- Constraint to prevent duplicate registration states
        registration_changed_to != (
            SELECT registration_changed_to  -- Selects the last registration status
            FROM domain_registration_changes drc
            WHERE drc.domain_id = domain_id
            ORDER BY drc.change_time DESC
            LIMIT 1
        )
    )
);

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

-- Creating a view to show active domain flags
CREATE VIEW active_domain_flags AS
SELECT domain_id, flag, valid_from
FROM domain_flag
WHERE valid_to IS NULL OR valid_to > NOW();  -- Only include flags that are still valid
