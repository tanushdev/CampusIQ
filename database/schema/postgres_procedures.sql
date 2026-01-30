-- ============================================================================
-- CAMPUSIQ - STORED PROCEDURES (POSTGRESQL COMPATIBLE)
-- ============================================================================

-- ============================================================================
-- 1. FUNCTIONS & PROCEDURES FOR SCHEDULE MANAGEMENT
-- ============================================================================

-- Check Room Availability Function
CREATE OR REPLACE FUNCTION is_room_available(
    p_college_id    UUID,
    p_room_code     VARCHAR,
    p_day_of_week   INTEGER,
    p_start_time    VARCHAR,
    p_end_time      VARCHAR,
    p_exclude_id    UUID DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_count
    FROM schedules
    WHERE college_id = p_college_id
      AND room_code = p_room_code
      AND day_of_week = p_day_of_week
      AND is_deleted = FALSE
      AND is_break = FALSE
      AND (p_exclude_id IS NULL OR schedule_id != p_exclude_id)
      AND (
          (start_time <= p_start_time AND end_time > p_start_time) OR
          (start_time < p_end_time AND end_time >= p_end_time) OR
          (start_time >= p_start_time AND end_time <= p_end_time)
      );
    
    RETURN v_count = 0;
END;
$$ LANGUAGE plpgsql;

-- Check Faculty Availability Function
CREATE OR REPLACE FUNCTION is_faculty_available(
    p_college_id    UUID,
    p_instructor    VARCHAR,
    p_day_of_week   INTEGER,
    p_start_time    VARCHAR,
    p_end_time      VARCHAR,
    p_exclude_id    UUID DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_count INTEGER;
BEGIN
    IF p_instructor IS NULL OR TRIM(p_instructor) = '' THEN
        RETURN TRUE;
    END IF;
    
    SELECT COUNT(*)
    INTO v_count
    FROM schedules
    WHERE college_id = p_college_id
      AND UPPER(instructor_name) = UPPER(TRIM(p_instructor))
      AND day_of_week = p_day_of_week
      AND is_deleted = FALSE
      AND is_break = FALSE
      AND (p_exclude_id IS NULL OR schedule_id != p_exclude_id)
      AND (
          (start_time <= p_start_time AND end_time > p_start_time) OR
          (start_time < p_end_time AND end_time >= p_end_time) OR
          (start_time >= p_start_time AND end_time <= p_end_time)
      );
    
    RETURN v_count = 0;
END;
$$ LANGUAGE plpgsql;

-- Create Schedule Procedure
CREATE OR REPLACE PROCEDURE create_schedule(
    p_college_id    UUID,
    p_class_code    VARCHAR,
    p_subject_name  VARCHAR,
    p_instructor    VARCHAR,
    p_room_code     VARCHAR,
    p_day_of_week   INTEGER,
    p_start_time    VARCHAR,
    p_end_time      VARCHAR,
    p_academic_year VARCHAR,
    p_created_by    UUID
) AS $$
DECLARE
    v_schedule_id UUID;
BEGIN
    -- Validation Logic can be added here raising exceptions
    
    INSERT INTO schedules (
        schedule_id, college_id, class_code, subject_name, instructor_name,
        room_code, day_of_week, start_time, end_time, academic_year,
        created_by, created_at, updated_at
    ) VALUES (
        uuid_generate_v4(), p_college_id, p_class_code, p_subject_name, p_instructor,
        p_room_code, p_day_of_week, p_start_time, p_end_time, p_academic_year,
        p_created_by, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2. FUNCTIONS FOR AUDIT LOGGING
-- ============================================================================

CREATE OR REPLACE FUNCTION log_audit_action(
    p_college_id        UUID,
    p_user_id           UUID,
    p_user_email        VARCHAR,
    p_user_role         VARCHAR,
    p_action_type       VARCHAR,
    p_entity_type       VARCHAR,
    p_entity_id         UUID,
    p_entity_name       VARCHAR,
    p_change_summary    VARCHAR,
    p_severity          VARCHAR DEFAULT 'INFO'
) RETURNS VOID AS $$
BEGIN
    INSERT INTO audit_logs (
        log_id, college_id, user_id, user_email, user_role,
        action_type, entity_type, entity_id, entity_name,
        change_summary, severity, created_at
    ) VALUES (
        uuid_generate_v4(), p_college_id, p_user_id, p_user_email, p_user_role,
        p_action_type, p_entity_type, p_entity_id, p_entity_name,
        p_change_summary, p_severity, CURRENT_TIMESTAMP
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 3. FUNCTIONS FOR COLLEGE MANAGEMENT
-- ============================================================================

-- Get College by Domain
CREATE OR REPLACE FUNCTION get_college_by_domain(p_email_domain VARCHAR) 
RETURNS TABLE (
    college_id UUID, 
    college_name VARCHAR, 
    college_code VARCHAR, 
    college_logo_url VARCHAR, 
    status VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.college_id, c.college_name, c.college_code, 
           c.college_logo_url, c.status
    FROM colleges c
    JOIN public.email_domain_mapping edm ON c.college_id = edm.college_id
    WHERE edm.domain = LOWER(p_email_domain)
      AND edm.is_active = TRUE
      AND c.is_deleted = FALSE;
END;
$$ LANGUAGE plpgsql;
