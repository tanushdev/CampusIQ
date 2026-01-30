-- ============================================================================
-- CAMPUSIQ - COLLEGE MANAGEMENT PL/SQL PACKAGE
-- Role-based access control for college and branding operations
-- ============================================================================

CREATE OR REPLACE PACKAGE pkg_college_mgmt AS
    
    -- Types
    TYPE t_college_rec IS RECORD (
        college_id      RAW(16),
        college_name    VARCHAR2(200),
        college_code    VARCHAR2(50),
        college_logo    VARCHAR2(1000),
        email_domain    VARCHAR2(100),
        status          VARCHAR2(20),
        created_at      TIMESTAMP
    );
    
    -- =========================================================================
    -- COLLEGE CRUD OPERATIONS
    -- =========================================================================
    
    -- Create new college (Super Admin only)
    PROCEDURE create_college(
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_college_name      IN VARCHAR2,
        p_college_code      IN VARCHAR2,
        p_email_domain      IN VARCHAR2,
        p_website_url       IN VARCHAR2 DEFAULT NULL,
        p_address           IN VARCHAR2 DEFAULT NULL,
        p_city              IN VARCHAR2 DEFAULT NULL,
        p_state             IN VARCHAR2 DEFAULT NULL,
        p_phone             IN VARCHAR2 DEFAULT NULL,
        p_college_id        OUT RAW,
        p_error_msg         OUT VARCHAR2
    );
    
    -- Update college details (Super Admin only)
    PROCEDURE update_college(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_college_name      IN VARCHAR2,
        p_college_code      IN VARCHAR2,
        p_website_url       IN VARCHAR2,
        p_address           IN VARCHAR2,
        p_city              IN VARCHAR2,
        p_state             IN VARCHAR2,
        p_phone             IN VARCHAR2,
        p_error_msg         OUT VARCHAR2
    );
    
    -- =========================================================================
    -- BRANDING OPERATIONS (Name + Logo)
    -- Enforced at DB level:
    --   - Super Admin: Can update ANY college
    --   - College Admin: Can ONLY update OWN college
    --   - Faculty/Staff: NO update access
    -- =========================================================================
    
    PROCEDURE update_college_branding(
        p_college_id        IN RAW,          -- Target college to update
        p_user_id           IN RAW,          -- Current user
        p_user_role         IN VARCHAR2,     -- User's role code
        p_user_college      IN RAW,          -- User's own college (NULL for super admin)
        p_college_name      IN VARCHAR2,     -- New college name
        p_logo_url          IN VARCHAR2,     -- New logo URL
        p_error_msg         OUT VARCHAR2     -- Error message if failed
    );
    
    -- =========================================================================
    -- COLLEGE STATUS OPERATIONS (Super Admin only)
    -- =========================================================================
    
    PROCEDURE approve_college(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_error_msg         OUT VARCHAR2
    );
    
    PROCEDURE suspend_college(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_reason            IN VARCHAR2,
        p_error_msg         OUT VARCHAR2
    );
    
    PROCEDURE delete_college(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_error_msg         OUT VARCHAR2
    );
    
    -- =========================================================================
    -- QUERY FUNCTIONS
    -- =========================================================================
    
    FUNCTION get_college_by_id(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_user_college      IN RAW
    ) RETURN SYS_REFCURSOR;
    
    FUNCTION get_all_colleges(
        p_user_role         IN VARCHAR2,
        p_status_filter     IN VARCHAR2 DEFAULT NULL
    ) RETURN SYS_REFCURSOR;
    
    FUNCTION get_college_by_domain(
        p_email_domain      IN VARCHAR2
    ) RETURN SYS_REFCURSOR;
    
END pkg_college_mgmt;
/

-- ============================================================================
-- PACKAGE BODY
-- ============================================================================

CREATE OR REPLACE PACKAGE BODY pkg_college_mgmt AS

    -- Helper function to check role permission level
    FUNCTION get_role_level(p_role VARCHAR2) RETURN NUMBER IS
    BEGIN
        CASE p_role
            WHEN 'SUPER_ADMIN' THEN RETURN 100;
            WHEN 'COLLEGE_ADMIN' THEN RETURN 50;
            WHEN 'FACULTY' THEN RETURN 10;
            WHEN 'STAFF' THEN RETURN 5;
            WHEN 'STUDENT' THEN RETURN 1;
            ELSE RETURN 0;
        END CASE;
    END get_role_level;
    
    -- Helper procedure to log audit
    PROCEDURE log_audit(
        p_college_id    RAW,
        p_user_id       RAW,
        p_user_role     VARCHAR2,
        p_action        VARCHAR2,
        p_entity_type   VARCHAR2,
        p_entity_id     RAW,
        p_old_value     CLOB,
        p_new_value     CLOB,
        p_summary       VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO audit_logs (
            college_id, user_id, user_role, action_type, 
            entity_type, entity_id, old_value, new_value, 
            change_summary, created_at
        ) VALUES (
            p_college_id, p_user_id, p_user_role, p_action,
            p_entity_type, p_entity_id, p_old_value, p_new_value,
            p_summary, CURRENT_TIMESTAMP
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END log_audit;

    -- =========================================================================
    -- CREATE COLLEGE (Super Admin only)
    -- =========================================================================
    PROCEDURE create_college(
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_college_name      IN VARCHAR2,
        p_college_code      IN VARCHAR2,
        p_email_domain      IN VARCHAR2,
        p_website_url       IN VARCHAR2 DEFAULT NULL,
        p_address           IN VARCHAR2 DEFAULT NULL,
        p_city              IN VARCHAR2 DEFAULT NULL,
        p_state             IN VARCHAR2 DEFAULT NULL,
        p_phone             IN VARCHAR2 DEFAULT NULL,
        p_college_id        OUT RAW,
        p_error_msg         OUT VARCHAR2
    ) IS
    BEGIN
        p_error_msg := NULL;
        
        -- Only Super Admin can create colleges
        IF p_user_role != 'SUPER_ADMIN' THEN
            p_error_msg := 'ACCESS_DENIED: Only Super Admin can create colleges';
            RETURN;
        END IF;
        
        -- Validate required fields
        IF p_college_name IS NULL OR LENGTH(TRIM(p_college_name)) < 3 THEN
            p_error_msg := 'VALIDATION: College name must be at least 3 characters';
            RETURN;
        END IF;
        
        -- Check for duplicate college code
        DECLARE
            v_count NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_count 
            FROM colleges 
            WHERE college_code = p_college_code AND is_deleted = 0;
            
            IF v_count > 0 THEN
                p_error_msg := 'DUPLICATE: College code already exists';
                RETURN;
            END IF;
        END;
        
        -- Check for duplicate email domain
        DECLARE
            v_count NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_count 
            FROM email_domain_mapping 
            WHERE domain = p_email_domain AND is_active = 1;
            
            IF v_count > 0 THEN
                p_error_msg := 'DUPLICATE: Email domain already registered';
                RETURN;
            END IF;
        END;
        
        -- Generate new college ID
        p_college_id := SYS_GUID();
        
        -- Insert college
        INSERT INTO colleges (
            college_id, college_name, college_code, email_domain,
            website_url, address, city, state, phone,
            status, created_by, created_at, updated_at
        ) VALUES (
            p_college_id, p_college_name, p_college_code, p_email_domain,
            p_website_url, p_address, p_city, p_state, p_phone,
            'PENDING', p_user_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        );
        
        -- Create email domain mapping
        INSERT INTO email_domain_mapping (
            college_id, domain, is_primary, is_active, created_at
        ) VALUES (
            p_college_id, p_email_domain, 1, 1, CURRENT_TIMESTAMP
        );
        
        -- Log audit
        log_audit(
            p_college_id, p_user_id, p_user_role, 'CREATE',
            'college', p_college_id, NULL,
            '{"name":"' || p_college_name || '","code":"' || p_college_code || '"}',
            'Created new college: ' || p_college_name
        );
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            p_error_msg := 'ERROR: ' || SQLERRM;
            ROLLBACK;
    END create_college;

    -- =========================================================================
    -- UPDATE COLLEGE BRANDING (Role-enforced)
    -- This is the CRITICAL security enforcement at DB level
    -- =========================================================================
    PROCEDURE update_college_branding(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_user_college      IN RAW,
        p_college_name      IN VARCHAR2,
        p_logo_url          IN VARCHAR2,
        p_error_msg         OUT VARCHAR2
    ) IS
        v_old_name      VARCHAR2(200);
        v_old_logo      VARCHAR2(1000);
        v_college_exists NUMBER;
    BEGIN
        p_error_msg := NULL;
        
        -- =================================================================
        -- SECURITY CHECK: Role-based access control
        -- =================================================================
        
        -- Faculty and Staff cannot update branding AT ALL
        IF p_user_role IN ('FACULTY', 'STAFF', 'STUDENT') THEN
            p_error_msg := 'ACCESS_DENIED: Faculty/Staff cannot modify college branding';
            
            -- Log security violation attempt
            log_audit(
                p_college_id, p_user_id, p_user_role, 'SECURITY_VIOLATION',
                'college_branding', p_college_id, NULL, NULL,
                'Unauthorized branding update attempt by ' || p_user_role
            );
            
            RETURN;
        END IF;
        
        -- College Admin can ONLY update their OWN college
        IF p_user_role = 'COLLEGE_ADMIN' THEN
            IF p_user_college IS NULL OR p_user_college != p_college_id THEN
                p_error_msg := 'ACCESS_DENIED: College Admin can only update their own college';
                
                -- Log cross-tenant attempt
                log_audit(
                    p_college_id, p_user_id, p_user_role, 'CROSS_TENANT_VIOLATION',
                    'college_branding', p_college_id, NULL, NULL,
                    'Cross-tenant branding update attempt'
                );
                
                RETURN;
            END IF;
        END IF;
        
        -- Super Admin can update ANY college (no additional check needed)
        
        -- =================================================================
        -- VALIDATION
        -- =================================================================
        
        -- Check college exists
        SELECT COUNT(*) INTO v_college_exists
        FROM colleges 
        WHERE college_id = p_college_id AND is_deleted = 0;
        
        IF v_college_exists = 0 THEN
            p_error_msg := 'NOT_FOUND: College does not exist';
            RETURN;
        END IF;
        
        -- Validate college name
        IF p_college_name IS NOT NULL AND LENGTH(TRIM(p_college_name)) < 3 THEN
            p_error_msg := 'VALIDATION: College name must be at least 3 characters';
            RETURN;
        END IF;
        
        -- Validate logo URL format (basic check)
        IF p_logo_url IS NOT NULL AND LENGTH(p_logo_url) > 0 THEN
            IF NOT (INSTR(LOWER(p_logo_url), 'http://') = 1 OR 
                    INSTR(LOWER(p_logo_url), 'https://') = 1) THEN
                p_error_msg := 'VALIDATION: Logo URL must start with http:// or https://';
                RETURN;
            END IF;
        END IF;
        
        -- =================================================================
        -- GET OLD VALUES FOR AUDIT
        -- =================================================================
        SELECT college_name, college_logo_url
        INTO v_old_name, v_old_logo
        FROM colleges
        WHERE college_id = p_college_id;
        
        -- =================================================================
        -- UPDATE BRANDING
        -- =================================================================
        UPDATE colleges
        SET college_name = COALESCE(p_college_name, college_name),
            college_logo_url = COALESCE(p_logo_url, college_logo_url),
            updated_by = p_user_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE college_id = p_college_id
          AND is_deleted = 0;
        
        -- Log successful update
        log_audit(
            p_college_id, p_user_id, p_user_role, 'UPDATE_BRANDING',
            'college', p_college_id,
            '{"name":"' || v_old_name || '","logo":"' || NVL(v_old_logo, '') || '"}',
            '{"name":"' || COALESCE(p_college_name, v_old_name) || '","logo":"' || NVL(p_logo_url, v_old_logo) || '"}',
            'Branding updated by ' || p_user_role
        );
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            p_error_msg := 'ERROR: ' || SQLERRM;
            ROLLBACK;
    END update_college_branding;

    -- =========================================================================
    -- UPDATE COLLEGE (Super Admin only)
    -- =========================================================================
    PROCEDURE update_college(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_college_name      IN VARCHAR2,
        p_college_code      IN VARCHAR2,
        p_website_url       IN VARCHAR2,
        p_address           IN VARCHAR2,
        p_city              IN VARCHAR2,
        p_state             IN VARCHAR2,
        p_phone             IN VARCHAR2,
        p_error_msg         OUT VARCHAR2
    ) IS
    BEGIN
        p_error_msg := NULL;
        
        -- Only Super Admin can update full college details
        IF p_user_role != 'SUPER_ADMIN' THEN
            p_error_msg := 'ACCESS_DENIED: Only Super Admin can update college details';
            RETURN;
        END IF;
        
        UPDATE colleges
        SET college_name = COALESCE(p_college_name, college_name),
            college_code = COALESCE(p_college_code, college_code),
            website_url = COALESCE(p_website_url, website_url),
            address = COALESCE(p_address, address),
            city = COALESCE(p_city, city),
            state = COALESCE(p_state, state),
            phone = COALESCE(p_phone, phone),
            updated_by = p_user_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE college_id = p_college_id
          AND is_deleted = 0;
        
        IF SQL%ROWCOUNT = 0 THEN
            p_error_msg := 'NOT_FOUND: College not found';
            RETURN;
        END IF;
        
        log_audit(
            p_college_id, p_user_id, p_user_role, 'UPDATE',
            'college', p_college_id, NULL, NULL,
            'College details updated'
        );
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            p_error_msg := 'ERROR: ' || SQLERRM;
            ROLLBACK;
    END update_college;

    -- =========================================================================
    -- APPROVE COLLEGE (Super Admin only)
    -- =========================================================================
    PROCEDURE approve_college(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_error_msg         OUT VARCHAR2
    ) IS
        v_old_status VARCHAR2(20);
    BEGIN
        p_error_msg := NULL;
        
        IF p_user_role != 'SUPER_ADMIN' THEN
            p_error_msg := 'ACCESS_DENIED: Only Super Admin can approve colleges';
            RETURN;
        END IF;
        
        SELECT status INTO v_old_status
        FROM colleges
        WHERE college_id = p_college_id AND is_deleted = 0;
        
        IF v_old_status = 'APPROVED' THEN
            p_error_msg := 'INVALID_STATE: College is already approved';
            RETURN;
        END IF;
        
        UPDATE colleges
        SET status = 'APPROVED',
            approved_by = p_user_id,
            approved_at = CURRENT_TIMESTAMP,
            updated_by = p_user_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE college_id = p_college_id;
        
        log_audit(
            p_college_id, p_user_id, p_user_role, 'APPROVE',
            'college', p_college_id,
            '{"status":"' || v_old_status || '"}',
            '{"status":"APPROVED"}',
            'College approved'
        );
        
        COMMIT;
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_error_msg := 'NOT_FOUND: College not found';
        WHEN OTHERS THEN
            p_error_msg := 'ERROR: ' || SQLERRM;
            ROLLBACK;
    END approve_college;

    -- =========================================================================
    -- SUSPEND COLLEGE (Super Admin only)
    -- =========================================================================
    PROCEDURE suspend_college(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_reason            IN VARCHAR2,
        p_error_msg         OUT VARCHAR2
    ) IS
    BEGIN
        p_error_msg := NULL;
        
        IF p_user_role != 'SUPER_ADMIN' THEN
            p_error_msg := 'ACCESS_DENIED: Only Super Admin can suspend colleges';
            RETURN;
        END IF;
        
        UPDATE colleges
        SET status = 'SUSPENDED',
            suspended_reason = p_reason,
            updated_by = p_user_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE college_id = p_college_id
          AND is_deleted = 0;
        
        IF SQL%ROWCOUNT = 0 THEN
            p_error_msg := 'NOT_FOUND: College not found';
            RETURN;
        END IF;
        
        log_audit(
            p_college_id, p_user_id, p_user_role, 'SUSPEND',
            'college', p_college_id, NULL,
            '{"status":"SUSPENDED","reason":"' || p_reason || '"}',
            'College suspended: ' || p_reason
        );
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            p_error_msg := 'ERROR: ' || SQLERRM;
            ROLLBACK;
    END suspend_college;

    -- =========================================================================
    -- DELETE COLLEGE (Soft delete, Super Admin only)
    -- =========================================================================
    PROCEDURE delete_college(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_error_msg         OUT VARCHAR2
    ) IS
    BEGIN
        p_error_msg := NULL;
        
        IF p_user_role != 'SUPER_ADMIN' THEN
            p_error_msg := 'ACCESS_DENIED: Only Super Admin can delete colleges';
            RETURN;
        END IF;
        
        UPDATE colleges
        SET is_deleted = 1,
            status = 'DELETED',
            updated_by = p_user_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE college_id = p_college_id
          AND is_deleted = 0;
        
        IF SQL%ROWCOUNT = 0 THEN
            p_error_msg := 'NOT_FOUND: College not found';
            RETURN;
        END IF;
        
        log_audit(
            p_college_id, p_user_id, p_user_role, 'DELETE',
            'college', p_college_id, NULL, NULL,
            'College deleted (soft delete)'
        );
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            p_error_msg := 'ERROR: ' || SQLERRM;
            ROLLBACK;
    END delete_college;

    -- =========================================================================
    -- GET COLLEGE BY ID
    -- =========================================================================
    FUNCTION get_college_by_id(
        p_college_id        IN RAW,
        p_user_id           IN RAW,
        p_user_role         IN VARCHAR2,
        p_user_college      IN RAW
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        -- Super Admin can view any college
        IF p_user_role = 'SUPER_ADMIN' THEN
            OPEN v_cursor FOR
                SELECT college_id, college_name, college_code, college_logo_url,
                       email_domain, website_url, address, city, state, country,
                       postal_code, phone, status, academic_year, subscription_tier,
                       max_users, approved_at, created_at, updated_at
                FROM colleges
                WHERE college_id = p_college_id AND is_deleted = 0;
        ELSE
            -- Other users can only view their own college
            OPEN v_cursor FOR
                SELECT college_id, college_name, college_code, college_logo_url,
                       email_domain, website_url, address, city, state, country,
                       postal_code, phone, status, academic_year, subscription_tier,
                       max_users, approved_at, created_at, updated_at
                FROM colleges
                WHERE college_id = p_college_id 
                  AND college_id = p_user_college
                  AND is_deleted = 0;
        END IF;
        
        RETURN v_cursor;
    END get_college_by_id;

    -- =========================================================================
    -- GET ALL COLLEGES (Super Admin only)
    -- =========================================================================
    FUNCTION get_all_colleges(
        p_user_role         IN VARCHAR2,
        p_status_filter     IN VARCHAR2 DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        IF p_user_role != 'SUPER_ADMIN' THEN
            -- Return empty cursor for non-super-admins
            OPEN v_cursor FOR
                SELECT * FROM colleges WHERE 1 = 0;
            RETURN v_cursor;
        END IF;
        
        IF p_status_filter IS NOT NULL THEN
            OPEN v_cursor FOR
                SELECT college_id, college_name, college_code, college_logo_url,
                       email_domain, status, created_at, updated_at
                FROM colleges
                WHERE status = p_status_filter AND is_deleted = 0
                ORDER BY created_at DESC;
        ELSE
            OPEN v_cursor FOR
                SELECT college_id, college_name, college_code, college_logo_url,
                       email_domain, status, created_at, updated_at
                FROM colleges
                WHERE is_deleted = 0
                ORDER BY created_at DESC;
        END IF;
        
        RETURN v_cursor;
    END get_all_colleges;

    -- =========================================================================
    -- GET COLLEGE BY EMAIL DOMAIN (For login auto-detection)
    -- =========================================================================
    FUNCTION get_college_by_domain(
        p_email_domain      IN VARCHAR2
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT c.college_id, c.college_name, c.college_code, 
                   c.college_logo_url, c.status
            FROM colleges c
            JOIN email_domain_mapping edm ON c.college_id = edm.college_id
            WHERE edm.domain = LOWER(p_email_domain)
              AND edm.is_active = 1
              AND c.is_deleted = 0;
        
        RETURN v_cursor;
    END get_college_by_domain;

END pkg_college_mgmt;
/

COMMIT;
