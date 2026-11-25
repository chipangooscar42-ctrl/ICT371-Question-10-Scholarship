
-- ============================================================
-- ICT371 QUESTION 10: SCHOLARSHIP APPLICATION ASSESSMENT
-- ============================================================

-- SECTION 1: CLEAN UP OBJECTS FROM A PREVIOUS RUN OF QUESTION 10
-- This only removes objects belonging to Question 10.

DROP TABLE IF EXISTS decision_audit CASCADE;
DROP TABLE IF EXISTS applications CASCADE;
DROP TABLE IF EXISTS students CASCADE;

DROP VIEW IF EXISTS v_approved_applicants CASCADE;

DROP PROCEDURE IF EXISTS pr_assess_pending();
DROP PROCEDURE IF EXISTS pr_assess_application(INTEGER);

DROP FUNCTION IF EXISTS fn_scholarship_eligible(INTEGER, NUMERIC, NUMERIC);
DROP FUNCTION IF EXISTS fn_log_decision_change();


-- ============================================================
-- SECTION 2: CREATE TABLES
-- ============================================================

CREATE TABLE students (
    student_id SERIAL PRIMARY KEY,
    student_number VARCHAR(20) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL
);

CREATE TABLE applications (
    application_id SERIAL PRIMARY KEY,
    student_id INTEGER NOT NULL,
    age_at_application INTEGER NOT NULL CHECK (age_at_application > 0),
    monthly_income NUMERIC(10,2) NOT NULL CHECK (monthly_income >= 0),
    average_mark NUMERIC(5,2) NOT NULL
        CHECK (average_mark >= 0 AND average_mark <= 100),
    submitted_on DATE NOT NULL DEFAULT CURRENT_DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),

    CONSTRAINT fk_application_student
        FOREIGN KEY (student_id)
        REFERENCES students(student_id)
);

CREATE TABLE decision_audit (
    audit_id SERIAL PRIMARY KEY,
    application_id INTEGER NOT NULL,
    old_status VARCHAR(20) NOT NULL,
    new_status VARCHAR(20) NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_audit_application
        FOREIGN KEY (application_id)
        REFERENCES applications(application_id)
);


-- ============================================================
-- SECTION 3: INSERT SAMPLE STUDENTS
-- ============================================================

INSERT INTO students (student_number, full_name)
VALUES
('STU001', 'John Banda'),
('STU002', 'Mary Phiri'),
('STU003', 'Peter Zulu'),
('STU004', 'Grace Tembo'),
('STU005', 'David Chanda'),
('STU006', 'Ruth Mwila');


-- ============================================================
-- SECTION 4: INSERT SIX PENDING SCHOLARSHIP APPLICATIONS
-- Eligibility rules:
-- Age: 18 to 25 inclusive
-- Monthly household income: K3,000 or less
-- Average mark: 70 or above
-- ============================================================

INSERT INTO applications
(student_id, age_at_application, monthly_income, average_mark, submitted_on, status)
VALUES
(1, 18, 3000.00, 70.00, CURRENT_DATE - 5, 'PENDING'),
(2, 25, 2500.00, 85.00, CURRENT_DATE - 4, 'PENDING'),
(3, 17, 2000.00, 90.00, CURRENT_DATE - 3, 'PENDING'),
(4, 26, 2500.00, 80.00, CURRENT_DATE - 2, 'PENDING'),
(5, 22, 3001.00, 90.00, CURRENT_DATE - 1, 'PENDING'),
(6, 21, 2800.00, 69.00, CURRENT_DATE, 'PENDING');


-- ============================================================
-- SECTION 5: CREATE ELIGIBILITY FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION fn_scholarship_eligible(
    p_age INTEGER,
    p_income NUMERIC,
    p_mark NUMERIC
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL THEN
        RAISE EXCEPTION 'Age, income and average mark cannot be NULL';
    END IF;

    IF p_age <= 0 THEN
        RAISE EXCEPTION 'Age must be greater than zero';
    END IF;

    IF p_income < 0 THEN
        RAISE EXCEPTION 'Monthly income cannot be negative';
    END IF;

    IF p_mark < 0 OR p_mark > 100 THEN
        RAISE EXCEPTION 'Average mark must be between 0 and 100';
    END IF;

    RETURN (
        p_age BETWEEN 18 AND 25
        AND p_income <= 3000
        AND p_mark >= 70
    );
END;
$$;


-- ============================================================
-- SECTION 6: CREATE AUDIT TRIGGER FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION fn_log_decision_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO decision_audit (
        application_id,
        old_status,
        new_status,
        changed_at
    )
    VALUES (
        NEW.application_id,
        OLD.status,
        NEW.status,
        CURRENT_TIMESTAMP
    );

    RETURN NEW;
END;
$$;


-- ============================================================
-- SECTION 7: CREATE AFTER UPDATE AUDIT TRIGGER
-- Only actual status changes are recorded.
-- ============================================================

CREATE TRIGGER trg_decision_audit
AFTER UPDATE OF status ON applications
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION fn_log_decision_change();


-- ============================================================
-- SECTION 8: CREATE APPLICATION ASSESSMENT PROCEDURE
-- ============================================================

CREATE OR REPLACE PROCEDURE pr_assess_application(
    p_application_id INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_age INTEGER;
    v_income NUMERIC(10,2);
    v_mark NUMERIC(5,2);
    v_status VARCHAR(20);
    v_eligible BOOLEAN;
BEGIN
    SELECT
        age_at_application,
        monthly_income,
        average_mark,
        status
    INTO
        v_age,
        v_income,
        v_mark,
        v_status
    FROM applications
    WHERE application_id = p_application_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application ID % does not exist',
            p_application_id;
    END IF;

    IF v_status <> 'PENDING' THEN
        RAISE EXCEPTION 'Application ID % has already been assessed',
            p_application_id;
    END IF;

    v_eligible := fn_scholarship_eligible(
        v_age,
        v_income,
        v_mark
    );

    IF v_eligible THEN
        UPDATE applications
        SET status = 'APPROVED'
        WHERE application_id = p_application_id;
    ELSE
        UPDATE applications
        SET status = 'REJECTED'
        WHERE application_id = p_application_id;
    END IF;
END;
$$;


-- ============================================================
-- SECTION 9: CREATE APPROVED APPLICANTS VIEW
-- Household income is deliberately excluded.
-- ============================================================

CREATE OR REPLACE VIEW v_approved_applicants AS
SELECT
    s.student_number,
    s.full_name,
    a.average_mark,
    a.status
FROM students s
INNER JOIN applications a
    ON s.student_id = a.student_id
WHERE a.status = 'APPROVED';


-- ============================================================
-- SECTION 10: CREATE INDEX
-- Supports searches by status and submission date.
-- ============================================================

CREATE INDEX idx_applications_status_submitted
ON applications (status, submitted_on);


-- ============================================================
-- SECTION 11: SHOW QUERY AND EXPLAIN PLAN
-- ============================================================

EXPLAIN
SELECT
    application_id,
    student_id,
    submitted_on,
    status
FROM applications
WHERE status = 'PENDING'
AND submitted_on BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE;


-- ============================================================
-- SECTION 12: CREATE PROCEDURE TO ASSESS ALL PENDING APPLICATIONS
-- ============================================================

CREATE OR REPLACE PROCEDURE pr_assess_pending()
LANGUAGE plpgsql
AS $$
DECLARE
    v_application RECORD;
BEGIN
    FOR v_application IN
        SELECT application_id
        FROM applications
        WHERE status = 'PENDING'
        ORDER BY application_id
    LOOP
        CALL pr_assess_application(v_application.application_id);
    END LOOP;
END;
$$;


-- ============================================================
-- SECTION 13: RUN THE ASSESSMENT PROCEDURE
-- ============================================================

CALL pr_assess_pending();


-- ============================================================
-- SECTION 14: DISPLAY ALL ASSESSED APPLICATIONS
-- ============================================================

SELECT
    a.application_id,
    s.student_number,
    s.full_name,
    a.age_at_application,
    a.monthly_income,
    a.average_mark,
    a.status
FROM applications a
INNER JOIN students s
    ON a.student_id = s.student_id
ORDER BY a.application_id;


-- ============================================================
-- SECTION 15: DISPLAY APPROVED APPLICANTS
-- ============================================================

SELECT *
FROM v_approved_applicants
ORDER BY student_number;


-- ============================================================
-- SECTION 16: DISPLAY DECISION AUDIT RECORDS
-- ============================================================

SELECT
    audit_id,
    application_id,
    old_status,
    new_status,
    changed_at
FROM decision_audit
ORDER BY audit_id;


-- ============================================================
-- SECTION 17: DISPLAY SUMMARY COUNTS
-- ============================================================

SELECT
    COUNT(*) AS total_applications,
    COUNT(*) FILTER (WHERE status = 'APPROVED') AS approved_applications,
    COUNT(*) FILTER (WHERE status = 'REJECTED') AS rejected_applications,
    COUNT(*) FILTER (WHERE status = 'PENDING') AS pending_applications
FROM applications;


-- ============================================================
-- SECTION 18: TEST THAT RE-RUNNING DOES NOT DUPLICATE AUDIT
-- The procedure should find no PENDING applications.
-- ============================================================

CALL pr_assess_pending();

SELECT COUNT(*) AS audit_records_after_second_run
FROM decision_audit;


-- ============================================================
-- SECTION 19: SCHEDULE WEEKLY ASSESSMENT
-- Every Monday at 08:00.
-- This requires pg_cron to be available and configured.
-- ============================================================

DO $$
BEGIN
    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_cron';

    EXECUTE
        'SELECT cron.unschedule(jobid)
         FROM cron.job
         WHERE jobname = ''ict371_scholarship_assessment''';

    EXECUTE
        'SELECT cron.schedule(
            ''ict371_scholarship_assessment'',
            ''0 8 * * 1'',
            ''CALL pr_assess_pending();''
        )';

    RAISE NOTICE 'Scholarship assessment job scheduled for Mondays at 08:00';

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron scheduling was not completed: %', SQLERRM;
END;
$$;


-- ============================================================
-- END OF ICT371 QUESTION 10
-- ============================================================
