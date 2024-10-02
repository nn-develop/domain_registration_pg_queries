CREATE TABLE domains (
    domain_id SERIAL PRIMARY KEY,
    domain_name VARCHAR(255) NOT NULL,
    tld VARCHAR(10) NOT NULL,
    is_registered BOOLEAN DEFAULT FALSE,
    clear_status BOOLEAN DEFAULT TRUE,
    UNIQUE(domain_name, tld)
);

CREATE TABLE flags (
    flag_id SERIAL PRIMARY KEY,
    flag_name VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE domain_registration_changes (
    change_id SERIAL PRIMARY KEY,
    domain_id INT REFERENCES domains(domain_id),
    change_time TIMESTAMP DEFAULT NOW() NOT NULL,
    registration_changed_to BOOLEAN NOT NULL,  -- TRUE = register, FALSE = unregister
    CONSTRAINT check_no_duplicate_registration_state CHECK (
        registration_changed_to != (
            SELECT registration_changed_to
            FROM domain_registration_changes drc
            WHERE drc.domain_id = domain_id
            ORDER BY drc.change_time DESC
            LIMIT 1
        )
    )
);

CREATE TABLE domain_flag_changes (
    change_id SERIAL PRIMARY KEY,
    domain_id INT REFERENCES domains(domain_id),
    flag_id INT REFERENCES flags(flag_id),
    change_time TIMESTAMP DEFAULT NOW() NOT NULL,
    flag_set_to BOOLEAN NOT NULL,  -- TRUE = flag set, FALSE = flag removed
    valid_until TIMESTAMP DEFAULT 'infinity',
    CONSTRAINT valid_until_after_change CHECK (valid_until > change_time OR valid_until = 'infinity')
);

SELECT d.domain_name || '.' || d.tld AS fully_qualified_domain
FROM domains d
WHERE d.is_registered = TRUE
  AND d.clear_status = TRUE;

SELECT d.domain_name || '.' || d.tld AS fully_qualified_domain
FROM domains d
WHERE d.is_registered = TRUE
  AND NOT EXISTS (
      SELECT 1
      FROM domain_flag_changes df
      WHERE df.domain_id = d.domain_id
        AND df.flag_id = (SELECT flag_id FROM flags WHERE flag_name = 'EXPIRED')
        AND df.flag_set_to = TRUE
        AND (df.valid_until IS NULL OR df.valid_until > NOW())
  );

SELECT DISTINCT d.domain_name || '.' || d.tld AS fully_qualified_domain
FROM domains d
WHERE EXISTS (
    SELECT 1
    FROM domain_flag_changes df_exp
    WHERE d.domain_id = df_exp.domain_id
      AND df_exp.flag_id = (SELECT flag_id FROM flags WHERE flag_name = 'EXPIRED')
      AND df_exp.flag_set_to = TRUE
) 
AND EXISTS (
    SELECT 1
    FROM domain_flag_changes df_out
    WHERE d.domain_id = df_out.domain_id
      AND df_out.flag_id = (SELECT flag_id FROM flags WHERE flag_name = 'OUTZONE')
      AND df_out.flag_set_to = TRUE
);

CREATE VIEW active_domain_flags AS
SELECT domain_id, flag, valid_from
FROM domain_flag
WHERE valid_to IS NULL OR valid_to > NOW();


