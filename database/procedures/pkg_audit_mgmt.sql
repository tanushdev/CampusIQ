-- ============================================================================
-- CAMPUSIQ - AUDIT MANAGEMENT PL/SQL PACKAGE
-- Comprehensive audit logging and security trail
-- ============================================================================

CREATE OR REPLACE PACKAGE pkg_audit_mgmt AS
    
    -- Action type constants
    c_action_login          CONSTANT VARCHAR2(20) := 'LOGIN';
    c_action_logout         CONSTANT VARCHAR2(20) := 'LOGOUT';
    c_action_create         CONSTANT VARCHAR2(20) := 'CREATE';
    c_action_read           CONSTANT VARCHAR2(20) := 'READ';
    c_action_update         CONSTANT VARCHAR2(20) := 'UPDATE';
    c_action_delete         CONSTANT VARCHAR2(20) := 'DELETE';
    c_action_approve        CONSTANT VARCHAR2(20) := 'APPROVE';
    c_action_suspend        CONSTANT VARCHAR2(20) := 'SUSPEND';
    c_action_security       CONSTANT VARCHAR2(20) := 'SECURITY_VIOLATION';
    
    -- Severity level constants
    c_severity_debug        CONSTANT VARCHAR2(10) := 'DEBUG';
    c_severity_info         CONSTANT VARCHAR2(10) := 'INFO';
    c_severity_warning      CONSTANT VARCHAR2(10) := 'WARNING';
    c_severity_error        CONSTANT VARCHAR2(10) := 'ERROR';
    c_severity_critical     CONSTANT VARCHAR2(10) := 'CRITICAL';
    
    -- =========================================================================
    -- LOGGING PROCEDURES
    -- =========================================================================
    
    -- Main audit logging procedure
    PROCEDURE log_action(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_email        IN VARCHAR2,
        p_user_role         IN VARCHAR2,
        p_action_type       IN VARCHAR2,
        p_entity_type       IN VARCHAR2,
        p_entity_id         IN RAW,
        p_entity_name       IN VARCHAR2 DEFAULT NULL,
        p_old_value         IN CLOB DEFAULT NULL,
        p_new_value         IN CLOB DEFAULT NULL,
        p_change_summary    IN VARCHAR2 DEFAULT NULL,
        p_ip_address        IN VARCHAR2 DEFAULT NULL,
        p_user_agent        IN VARCHAR2 DEFAULT NULL,
        p_request_path      IN VARCHAR2 DEFAULT NULL,
        p_request_method    IN VARCHAR2 DEFAULT NULL,
        p_response_status   IN NUMBER DEFAULT NULL,
        p_severity          IN VARCHAR2 DEFAULT 'INFO'
    );
    
    -- Simplified logging for common operations
    PROCEDURE log_login(
        p_user_id           IN RAW,
        p_user_email        IN VARCHAR2,
        p_college_id        IN RAW,
        p_ip_address        IN VARCHAR2,
        p_user_agent        IN VARCHAR2,
        p_success           IN BOOLEAN DEFAULT TRUE
    );
    
    PROCEDURE log_security_event(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_event_type        IN VARCHAR2,
        p_details           IN VARCHAR2,
        p_ip_address        IN VARCHAR2,
        p_severity          IN VARCHAR2 DEFAULT 'WARNING'
    );
    
    -- =========================================================================
    -- QUERY FUNCTIONS
    -- =========================================================================
    
    -- Get audit logs with role-based filtering
    -- Super Admin: Can view ALL logs
    -- College Admin: Can view ONLY their college's logs
    -- Others: No access
    FUNCTION get_audit_logs(
        p_user_role         IN VARCHAR2,
        p_user_college      IN RAW,
        p_action_filter     IN VARCHAR2 DEFAULT NULL,
        p_entity_filter     IN VARCHAR2 DEFAULT NULL,
        p_severity_filter   IN VARCHAR2 DEFAULT NULL,
        p_from_date         IN TIMESTAMP DEFAULT NULL,
        p_to_date           IN TIMESTAMP DEFAULT NULL,
        p_limit             IN NUMBER DEFAULT 100,
        p_offset            IN NUMBER DEFAULT 0
    ) RETURN SYS_REFCURSOR;
    
    -- Get security events (Super Admin only)
    FUNCTION get_security_events(
        p_user_role         IN VARCHAR2,
        p_from_date         IN TIMESTAMP DEFAULT NULL,
        p_to_date           IN TIMESTAMP DEFAULT NULL,
        p_limit             IN NUMBER DEFAULT 50
    ) RETURN SYS_REFCURSOR;
    
    -- Get login history for a user
    FUNCTION get_login_history(
        p_user_id           IN RAW,
        p_requesting_role   IN VARCHAR2,
        p_requesting_user   IN RAW,
        p_limit             IN NUMBER DEFAULT 20
    ) RETURN SYS_REFCURSOR;
    
    -- =========================================================================
    -- MAINTENANCE PROCEDURES
    -- =========================================================================
    
    -- Archive old audit logs (Super Admin only, run periodically)
    PROCEDURE archive_old_logs(
        p_days_to_keep      IN NUMBER DEFAULT 90,
        p_user_role         IN VARCHAR2,
        p_archived_count    OUT NUMBER,
        p_error_msg         OUT VARCHAR2
    );
    
END pkg_audit_mgmt;
/

-- ============================================================================
-- PACKAGE BODY
-- ============================================================================

CREATE OR REPLACE PACKAGE BODY pkg_audit_mgmt AS

    -- =========================================================================
    -- MAIN AUDIT LOGGING PROCEDURE
    -- =========================================================================
    PROCEDURE log_action(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_email        IN VARCHAR2,
        p_user_role         IN VARCHAR2,
        p_action_type       IN VARCHAR2,
        p_entity_type       IN VARCHAR2,
        p_entity_id         IN RAW,
        p_entity_name       IN VARCHAR2 DEFAULT NULL,
        p_old_value         IN CLOB DEFAULT NULL,
        p_new_value         IN CLOB DEFAULT NULL,
        p_change_summary    IN VARCHAR2 DEFAULT NULL,
        p_ip_address        IN VARCHAR2 DEFAULT NULL,
        p_user_agent        IN VARCHAR2 DEFAULT NULL,
        p_request_path      IN VARCHAR2 DEFAULT NULL,
        p_request_method    IN VARCHAR2 DEFAULT NULL,
        p_response_status   IN NUMBER DEFAULT NULL,
        p_severity          IN VARCHAR2 DEFAULT 'INFO'
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_logs (
            log_id,
            college_id,
            user_id,
            user_email,
            user_role,
            action_type,
            entity_type,
            entity_id,
            entity_name,
            old_value,
            new_value,
            change_summary,
            ip_address,
            user_agent,
            request_path,
            request_method,
            response_status,
            severity,
            created_at
        ) VALUES (
            SYS_GUID(),
            p_college_id,
            p_user_id,
            p_user_email,
            p_user_role,
            p_action_type,
            p_entity_type,
            p_entity_id,
            p_entity_name,
            p_old_value,
            p_new_value,
            p_change_summary,
            p_ip_address,
            SUBSTR(p_user_agent, 1, 500), -- Truncate long user agents
            p_request_path,
            p_request_method,
            p_response_status,
            COALESCE(p_severity, 'INFO'),
            CURRENT_TIMESTAMP
        );
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            -- Never fail on audit logging - silently ignore errors
            ROLLBACK;
    END log_action;

    -- =========================================================================
    -- LOGIN LOGGING
    -- =========================================================================
    PROCEDURE log_login(
        p_user_id           IN RAW,
        p_user_email        IN VARCHAR2,
        p_college_id        IN RAW,
        p_ip_address        IN VARCHAR2,
        p_user_agent        IN VARCHAR2,
        p_success           IN BOOLEAN DEFAULT TRUE
    ) IS
        v_action_type VARCHAR2(20);
        v_severity VARCHAR2(10);
        v_summary VARCHAR2(200);
    BEGIN
        IF p_success THEN
            v_action_type := 'LOGIN';
            v_severity := 'INFO';
            v_summary := 'User logged in successfully';
        ELSE
            v_action_type := 'LOGIN_FAILED';
            v_severity := 'WARNING';
            v_summary := 'Login attempt failed';
        END IF;
        
        log_action(
            p_college_id        => p_college_id,
            p_user_id           => p_user_id,
            p_user_email        => p_user_email,
            p_user_role         => NULL,
            p_action_type       => v_action_type,
            p_entity_type       => 'session',
            p_entity_id         => p_user_id,
            p_entity_name       => p_user_email,
            p_old_value         => NULL,
            p_new_value         => NULL,
            p_change_summary    => v_summary,
            p_ip_address        => p_ip_address,
            p_user_agent        => p_user_agent,
            p_severity          => v_severity
        );
    END log_login;

    -- =========================================================================
    -- SECURITY EVENT LOGGING
    -- =========================================================================
    PROCEDURE log_security_event(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_event_type        IN VARCHAR2,
        p_details           IN VARCHAR2,
        p_ip_address        IN VARCHAR2,
        p_severity          IN VARCHAR2 DEFAULT 'WARNING'
    ) IS
    BEGIN
        log_action(
            p_college_id        => p_college_id,
            p_user_id           => p_user_id,
            p_user_email        => NULL,
            p_user_role         => p_user_role,
            p_action_type       => 'SECURITY_EVENT',
            p_entity_type       => 'security',
            p_entity_id         => NULL,
            p_entity_name       => p_event_type,
            p_old_value         => NULL,
            p_new_value         => p_details,
            p_change_summary    => p_event_type || ': ' || SUBSTR(p_details, 1, 100),
            p_ip_address        => p_ip_address,
            p_user_agent        => NULL,
            p_severity          => p_severity
        );
    END log_security_event;

    -- =========================================================================
    -- GET AUDIT LOGS (Role-filtered)
    -- =========================================================================
    FUNCTION get_audit_logs(
        p_user_role         IN VARCHAR2,
        p_user_college      IN RAW,
        p_action_filter     IN VARCHAR2 DEFAULT NULL,
        p_entity_filter     IN VARCHAR2 DEFAULT NULL,
        p_severity_filter   IN VARCHAR2 DEFAULT NULL,
        p_from_date         IN TIMESTAMP DEFAULT NULL,
        p_to_date           IN TIMESTAMP DEFAULT NULL,
        p_limit             IN NUMBER DEFAULT 100,
        p_offset            IN NUMBER DEFAULT 0
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
        v_from_date TIMESTAMP := COALESCE(p_from_date, CURRENT_TIMESTAMP - INTERVAL '30' DAY);
        v_to_date TIMESTAMP := COALESCE(p_to_date, CURRENT_TIMESTAMP);
    BEGIN
        -- Faculty/Staff have no access to audit logs
        IF p_user_role IN ('FACULTY', 'STAFF', 'STUDENT') THEN
            OPEN v_cursor FOR
                SELECT * FROM audit_logs WHERE 1 = 0;
            RETURN v_cursor;
        END IF;
        
        -- Super Admin can see all logs
        IF p_user_role = 'SUPER_ADMIN' THEN
            OPEN v_cursor FOR
                SELECT log_id, college_id, user_id, user_email, user_role,
                       action_type, entity_type, entity_id, entity_name,
                       change_summary, ip_address, severity, created_at
                FROM audit_logs
                WHERE created_at BETWEEN v_from_date AND v_to_date
                  AND (p_action_filter IS NULL OR action_type = p_action_filter)
                  AND (p_entity_filter IS NULL OR entity_type = p_entity_filter)
                  AND (p_severity_filter IS NULL OR severity = p_severity_filter)
                ORDER BY created_at DESC
                OFFSET p_offset ROWS
                FETCH NEXT p_limit ROWS ONLY;
        
        -- College Admin can only see their college's logs
        ELSIF p_user_role = 'COLLEGE_ADMIN' THEN
            OPEN v_cursor FOR
                SELECT log_id, college_id, user_id, user_email, user_role,
                       action_type, entity_type, entity_id, entity_name,
                       change_summary, ip_address, severity, created_at
                FROM audit_logs
                WHERE college_id = p_user_college
                  AND created_at BETWEEN v_from_date AND v_to_date
                  AND (p_action_filter IS NULL OR action_type = p_action_filter)
                  AND (p_entity_filter IS NULL OR entity_type = p_entity_filter)
                  AND (p_severity_filter IS NULL OR severity = p_severity_filter)
                ORDER BY created_at DESC
                OFFSET p_offset ROWS
                FETCH NEXT p_limit ROWS ONLY;
        ELSE
            -- Empty result for unknown roles
            OPEN v_cursor FOR
                SELECT * FROM audit_logs WHERE 1 = 0;
        END IF;
        
        RETURN v_cursor;
    END get_audit_logs;

    -- =========================================================================
    -- GET SECURITY EVENTS (Super Admin only)
    -- =========================================================================
    FUNCTION get_security_events(
        p_user_role         IN VARCHAR2,
        p_from_date         IN TIMESTAMP DEFAULT NULL,
        p_to_date           IN TIMESTAMP DEFAULT NULL,
        p_limit             IN NUMBER DEFAULT 50
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
        v_from_date TIMESTAMP := COALESCE(p_from_date, CURRENT_TIMESTAMP - INTERVAL '7' DAY);
        v_to_date TIMESTAMP := COALESCE(p_to_date, CURRENT_TIMESTAMP);
    BEGIN
        IF p_user_role != 'SUPER_ADMIN' THEN
            OPEN v_cursor FOR
                SELECT * FROM audit_logs WHERE 1 = 0;
            RETURN v_cursor;
        END IF;
        
        OPEN v_cursor FOR
            SELECT log_id, college_id, user_id, user_email, user_role,
                   action_type, entity_type, entity_name, change_summary,
                   ip_address, user_agent, severity, created_at
            FROM audit_logs
            WHERE (action_type LIKE '%SECURITY%' 
                   OR action_type LIKE '%VIOLATION%'
                   OR action_type = 'LOGIN_FAILED'
                   OR severity IN ('WARNING', 'ERROR', 'CRITICAL'))
              AND created_at BETWEEN v_from_date AND v_to_date
            ORDER BY created_at DESC
            FETCH NEXT p_limit ROWS ONLY;
        
        RETURN v_cursor;
    END get_security_events;

    -- =========================================================================
    -- GET LOGIN HISTORY
    -- =========================================================================
    FUNCTION get_login_history(
        p_user_id           IN RAW,
        p_requesting_role   IN VARCHAR2,
        p_requesting_user   IN RAW,
        p_limit             IN NUMBER DEFAULT 20
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        -- Users can only see their own login history
        -- Admins can see any user in their scope
        IF p_requesting_role IN ('FACULTY', 'STAFF', 'STUDENT') THEN
            IF p_user_id != p_requesting_user THEN
                OPEN v_cursor FOR
                    SELECT * FROM audit_logs WHERE 1 = 0;
                RETURN v_cursor;
            END IF;
        END IF;
        
        OPEN v_cursor FOR
            SELECT log_id, user_id, ip_address, user_agent, 
                   action_type, created_at
            FROM audit_logs
            WHERE user_id = p_user_id
              AND action_type IN ('LOGIN', 'LOGIN_FAILED', 'LOGOUT')
            ORDER BY created_at DESC
            FETCH NEXT p_limit ROWS ONLY;
        
        RETURN v_cursor;
    END get_login_history;

    -- =========================================================================
    -- ARCHIVE OLD LOGS
    -- =========================================================================
    PROCEDURE archive_old_logs(
        p_days_to_keep      IN NUMBER DEFAULT 90,
        p_user_role         IN VARCHAR2,
        p_archived_count    OUT NUMBER,
        p_error_msg         OUT VARCHAR2
    ) IS
        v_cutoff_date TIMESTAMP;
    BEGIN
        p_error_msg := NULL;
        p_archived_count := 0;
        
        IF p_user_role != 'SUPER_ADMIN' THEN
            p_error_msg := 'ACCESS_DENIED: Only Super Admin can archive logs';
            RETURN;
        END IF;
        
        v_cutoff_date := CURRENT_TIMESTAMP - NUMTODSINTERVAL(p_days_to_keep, 'DAY');
        
        -- For production, you would move to archive table first
        -- Here we just delete old non-critical logs
        DELETE FROM audit_logs
        WHERE created_at < v_cutoff_date
          AND severity NOT IN ('ERROR', 'CRITICAL');
        
        p_archived_count := SQL%ROWCOUNT;
        
        log_action(
            p_college_id        => NULL,
            p_user_id           => NULL,
            p_user_email        => NULL,
            p_user_role         => p_user_role,
            p_action_type       => 'ARCHIVE_LOGS',
            p_entity_type       => 'audit_logs',
            p_entity_id         => NULL,
            p_entity_name       => NULL,
            p_change_summary    => 'Archived ' || p_archived_count || ' logs older than ' || p_days_to_keep || ' days',
            p_severity          => 'INFO'
        );
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            p_error_msg := 'ERROR: ' || SQLERRM;
            ROLLBACK;
    END archive_old_logs;

END pkg_audit_mgmt;
/

COMMIT;
