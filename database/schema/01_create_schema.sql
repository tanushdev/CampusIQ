-- ============================================================================
-- CAMPUSIQ - CORE DATABASE SCHEMA
-- Production-ready multi-tenant college management system
-- Oracle SQL / PostgreSQL compatible (with SQLite fallback)
-- ============================================================================

-- ============================================================================
-- ROLES TABLE (Predefined system roles)
-- ============================================================================
CREATE TABLE roles (
    role_id         RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    role_name       VARCHAR2(50) NOT NULL UNIQUE,
    role_code       VARCHAR2(20) NOT NULL UNIQUE,
    description     VARCHAR2(500),
    hierarchy_level NUMBER(3) NOT NULL,
    is_system_role  NUMBER(1) DEFAULT 1,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert predefined roles
INSERT INTO roles (role_name, role_code, hierarchy_level, description) VALUES
    ('Super Admin', 'SUPER_ADMIN', 100, 'Platform owner with full system access'),
    ('College Admin', 'COLLEGE_ADMIN', 50, 'Tenant-level administrator for a college'),
    ('Faculty', 'FACULTY', 10, 'Teaching staff with class/schedule access'),
    ('Staff', 'STAFF', 5, 'Non-teaching staff with limited access'),
    ('Student', 'STUDENT', 1, 'Student with read-only access');
COMMIT;

-- ============================================================================
-- COLLEGES TABLE (Core multi-tenant entity)
-- ============================================================================
CREATE TABLE colleges (
    college_id          RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_name        VARCHAR2(200) NOT NULL,
    college_code        VARCHAR2(50) UNIQUE,
    college_logo_url    VARCHAR2(1000),
    email_domain        VARCHAR2(100),
    website_url         VARCHAR2(500),
    address             VARCHAR2(500),
    city                VARCHAR2(100),
    state               VARCHAR2(100),
    country             VARCHAR2(100) DEFAULT 'India',
    postal_code         VARCHAR2(20),
    phone               VARCHAR2(50),
    status              VARCHAR2(20) DEFAULT 'PENDING' 
                        CHECK (status IN ('PENDING', 'APPROVED', 'SUSPENDED', 'DELETED')),
    timezone            VARCHAR2(50) DEFAULT 'Asia/Kolkata',
    academic_year       VARCHAR2(20),
    subscription_tier   VARCHAR2(20) DEFAULT 'BASIC'
                        CHECK (subscription_tier IN ('BASIC', 'STANDARD', 'PREMIUM', 'ENTERPRISE')),
    max_users           NUMBER(10) DEFAULT 100,
    approved_by         RAW(16),
    approved_at         TIMESTAMP,
    suspended_reason    VARCHAR2(500),
    is_deleted          NUMBER(1) DEFAULT 0,
    created_by          RAW(16),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          RAW(16),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- EMAIL DOMAIN MAPPING (For automatic college detection during login)
-- ============================================================================
CREATE TABLE email_domain_mapping (
    mapping_id      RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id      RAW(16) NOT NULL REFERENCES colleges(college_id),
    domain          VARCHAR2(100) NOT NULL,
    is_primary      NUMBER(1) DEFAULT 0,
    is_active       NUMBER(1) DEFAULT 1,
    verified_at     TIMESTAMP,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_domain UNIQUE (domain)
);

-- ============================================================================
-- USERS TABLE (Multi-tenant user accounts)
-- ============================================================================
CREATE TABLE users (
    user_id             RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    email               VARCHAR2(255) NOT NULL,
    google_id           VARCHAR2(100),
    full_name           VARCHAR2(200),
    first_name          VARCHAR2(100),
    last_name           VARCHAR2(100),
    avatar_url          VARCHAR2(1000),
    phone               VARCHAR2(50),
    role_id             RAW(16) NOT NULL REFERENCES roles(role_id),
    college_id          RAW(16) REFERENCES colleges(college_id),
    department_id       RAW(16),
    status              VARCHAR2(20) DEFAULT 'ACTIVE'
                        CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING')),
    email_verified      NUMBER(1) DEFAULT 0,
    last_login_at       TIMESTAMP,
    last_login_ip       VARCHAR2(50),
    login_count         NUMBER(10) DEFAULT 0,
    failed_login_count  NUMBER(3) DEFAULT 0,
    locked_until        TIMESTAMP,
    preferences         CLOB,
    is_deleted          NUMBER(1) DEFAULT 0,
    created_by          RAW(16),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          RAW(16),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_users_email UNIQUE (email),
    CONSTRAINT uk_users_google_id UNIQUE (google_id)
);

-- ============================================================================
-- DEPARTMENTS TABLE
-- ============================================================================
CREATE TABLE departments (
    department_id       RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) NOT NULL REFERENCES colleges(college_id),
    department_name     VARCHAR2(200) NOT NULL,
    department_code     VARCHAR2(50),
    description         VARCHAR2(500),
    head_user_id        RAW(16) REFERENCES users(user_id),
    is_active           NUMBER(1) DEFAULT 1,
    is_deleted          NUMBER(1) DEFAULT 0,
    created_by          RAW(16),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          RAW(16),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_dept_college UNIQUE (college_id, department_code)
);

-- ============================================================================
-- FACULTY TABLE (Extended faculty information)
-- ============================================================================
CREATE TABLE faculty (
    faculty_id          RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) NOT NULL REFERENCES colleges(college_id),
    user_id             RAW(16) NOT NULL REFERENCES users(user_id),
    department_id       RAW(16) REFERENCES departments(department_id),
    employee_code       VARCHAR2(50),
    designation         VARCHAR2(100),
    qualification       VARCHAR2(200),
    specialization      VARCHAR2(200),
    experience_years    NUMBER(2),
    joining_date        DATE,
    status              VARCHAR2(20) DEFAULT 'ACTIVE'
                        CHECK (status IN ('ACTIVE', 'INACTIVE', 'ON_LEAVE', 'RESIGNED')),
    is_deleted          NUMBER(1) DEFAULT 0,
    created_by          RAW(16),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          RAW(16),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_faculty_user UNIQUE (user_id)
);

-- ============================================================================
-- CLASSES TABLE
-- ============================================================================
CREATE TABLE classes (
    class_id            RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) NOT NULL REFERENCES colleges(college_id),
    department_id       RAW(16) REFERENCES departments(department_id),
    class_code          VARCHAR2(50) NOT NULL,
    class_name          VARCHAR2(200),
    year                NUMBER(1),
    semester            NUMBER(2),
    division            VARCHAR2(10),
    batch               VARCHAR2(20),
    academic_year       VARCHAR2(20),
    class_teacher_id    RAW(16) REFERENCES faculty(faculty_id),
    max_students        NUMBER(4) DEFAULT 60,
    is_active           NUMBER(1) DEFAULT 1,
    is_deleted          NUMBER(1) DEFAULT 0,
    created_by          RAW(16),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          RAW(16),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_class_college UNIQUE (college_id, class_code, academic_year)
);

-- ============================================================================
-- SUBJECTS TABLE
-- ============================================================================
CREATE TABLE subjects (
    subject_id          RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) NOT NULL REFERENCES colleges(college_id),
    department_id       RAW(16) REFERENCES departments(department_id),
    subject_code        VARCHAR2(50),
    subject_name        VARCHAR2(200) NOT NULL,
    short_name          VARCHAR2(50),
    credits             NUMBER(2),
    lecture_hours       NUMBER(2),
    practical_hours     NUMBER(2),
    tutorial_hours      NUMBER(2),
    semester            NUMBER(2),
    subject_type        VARCHAR2(20) DEFAULT 'CORE'
                        CHECK (subject_type IN ('CORE', 'ELECTIVE', 'LAB', 'PROJECT', 'SEMINAR')),
    is_active           NUMBER(1) DEFAULT 1,
    is_deleted          NUMBER(1) DEFAULT 0,
    created_by          RAW(16),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          RAW(16),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- ROOMS TABLE
-- ============================================================================
CREATE TABLE rooms (
    room_id             RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) NOT NULL REFERENCES colleges(college_id),
    room_code           VARCHAR2(50) NOT NULL,
    room_name           VARCHAR2(100),
    building            VARCHAR2(100),
    floor               NUMBER(3),
    capacity            NUMBER(4),
    room_type           VARCHAR2(30) DEFAULT 'CLASSROOM'
                        CHECK (room_type IN ('CLASSROOM', 'LAB', 'SEMINAR_HALL', 'AUDITORIUM', 
                                             'LIBRARY', 'OFFICE', 'STAFF_ROOM', 'OTHER')),
    has_projector       NUMBER(1) DEFAULT 0,
    has_ac              NUMBER(1) DEFAULT 0,
    has_whiteboard      NUMBER(1) DEFAULT 1,
    is_active           NUMBER(1) DEFAULT 1,
    is_deleted          NUMBER(1) DEFAULT 0,
    created_by          RAW(16),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          RAW(16),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_room_college UNIQUE (college_id, room_code)
);

-- ============================================================================
-- SCHEDULES TABLE (Core timetable data)
-- ============================================================================
CREATE TABLE schedules (
    schedule_id         RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) NOT NULL REFERENCES colleges(college_id),
    class_id            RAW(16) REFERENCES classes(class_id),
    class_code          VARCHAR2(50),
    subject_id          RAW(16) REFERENCES subjects(subject_id),
    subject_name        VARCHAR2(200),
    faculty_id          RAW(16) REFERENCES faculty(faculty_id),
    instructor_name     VARCHAR2(200),
    room_id             RAW(16) REFERENCES rooms(room_id),
    room_code           VARCHAR2(50),
    day_of_week         NUMBER(1) NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time          VARCHAR2(10) NOT NULL,
    end_time            VARCHAR2(10) NOT NULL,
    schedule_type       VARCHAR2(20) DEFAULT 'LECTURE'
                        CHECK (schedule_type IN ('LECTURE', 'LAB', 'TUTORIAL', 'SEMINAR', 
                                                  'PRACTICAL', 'BREAK', 'OTHER')),
    is_break            NUMBER(1) DEFAULT 0,
    academic_year       VARCHAR2(20),
    semester            NUMBER(2),
    effective_from      DATE,
    effective_to        DATE,
    notes               VARCHAR2(500),
    is_deleted          NUMBER(1) DEFAULT 0,
    created_by          RAW(16),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          RAW(16),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- STUDENTS TABLE
-- ============================================================================
CREATE TABLE students (
    student_id          RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) NOT NULL REFERENCES colleges(college_id),
    user_id             RAW(16) REFERENCES users(user_id),
    class_id            RAW(16) REFERENCES classes(class_id),
    enrollment_number   VARCHAR2(50),
    roll_number         VARCHAR2(20),
    first_name          VARCHAR2(100),
    last_name           VARCHAR2(100),
    email               VARCHAR2(255),
    phone               VARCHAR2(50),
    date_of_birth       DATE,
    gender              VARCHAR2(10),
    admission_year      NUMBER(4),
    academic_status     VARCHAR2(20) DEFAULT 'ACTIVE'
                        CHECK (academic_status IN ('ACTIVE', 'GRADUATED', 'DROPPED', 
                                                    'SUSPENDED', 'ON_LEAVE')),
    is_deleted          NUMBER(1) DEFAULT 0,
    created_by          RAW(16),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          RAW(16),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_student_enrollment UNIQUE (college_id, enrollment_number)
);

-- ============================================================================
-- RESULTS TABLE
-- ============================================================================
CREATE TABLE results (
    result_id           RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) NOT NULL REFERENCES colleges(college_id),
    student_id          RAW(16) NOT NULL REFERENCES students(student_id),
    subject_id          RAW(16) REFERENCES subjects(subject_id),
    class_id            RAW(16) REFERENCES classes(class_id),
    exam_type           VARCHAR2(30) DEFAULT 'REGULAR'
                        CHECK (exam_type IN ('REGULAR', 'SUPPLEMENTARY', 'IMPROVEMENT', 'INTERNAL')),
    internal_marks      NUMBER(5,2),
    external_marks      NUMBER(5,2),
    total_marks         NUMBER(5,2),
    max_marks           NUMBER(5,2) DEFAULT 100,
    grade               VARCHAR2(5),
    grade_points        NUMBER(4,2),
    result_status       VARCHAR2(20) DEFAULT 'PENDING'
                        CHECK (result_status IN ('PENDING', 'PASS', 'FAIL', 'ABSENT', 'WITHHELD')),
    academic_year       VARCHAR2(20),
    semester            NUMBER(2),
    exam_date           DATE,
    published_at        TIMESTAMP,
    is_deleted          NUMBER(1) DEFAULT 0,
    created_by          RAW(16),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          RAW(16),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- FACULTY CLASS MAPPING
-- ============================================================================
CREATE TABLE faculty_class_mapping (
    mapping_id          RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) NOT NULL REFERENCES colleges(college_id),
    faculty_id          RAW(16) NOT NULL REFERENCES faculty(faculty_id),
    class_id            RAW(16) NOT NULL REFERENCES classes(class_id),
    subject_id          RAW(16) REFERENCES subjects(subject_id),
    academic_year       VARCHAR2(20),
    is_primary          NUMBER(1) DEFAULT 0,
    is_active           NUMBER(1) DEFAULT 1,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_fcm UNIQUE (faculty_id, class_id, subject_id, academic_year)
);

-- ============================================================================
-- QNA LOGS TABLE (AI Query logging)
-- ============================================================================
CREATE TABLE qna_logs (
    log_id              RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) NOT NULL REFERENCES colleges(college_id),
    user_id             RAW(16) REFERENCES users(user_id),
    session_id          VARCHAR2(100),
    question            CLOB NOT NULL,
    parsed_intent       VARCHAR2(100),
    extracted_entities  CLOB,
    response            CLOB,
    response_time_ms    NUMBER(10),
    was_successful      NUMBER(1) DEFAULT 1,
    error_message       VARCHAR2(500),
    feedback_rating     NUMBER(1),
    feedback_comment    VARCHAR2(500),
    ip_address          VARCHAR2(50),
    user_agent          VARCHAR2(500),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- AUDIT LOGS TABLE (Security audit trail)
-- ============================================================================
CREATE TABLE audit_logs (
    log_id              RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) REFERENCES colleges(college_id),
    user_id             RAW(16) REFERENCES users(user_id),
    user_email          VARCHAR2(255),
    user_role           VARCHAR2(50),
    action_type         VARCHAR2(50) NOT NULL,
    entity_type         VARCHAR2(100),
    entity_id           RAW(16),
    entity_name         VARCHAR2(200),
    old_value           CLOB,
    new_value           CLOB,
    change_summary      VARCHAR2(500),
    ip_address          VARCHAR2(50),
    user_agent          VARCHAR2(500),
    request_path        VARCHAR2(500),
    request_method      VARCHAR2(10),
    response_status     NUMBER(3),
    severity            VARCHAR2(20) DEFAULT 'INFO'
                        CHECK (severity IN ('DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL')),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- REFRESH TOKENS TABLE
-- ============================================================================
CREATE TABLE refresh_tokens (
    token_id            RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    user_id             RAW(16) NOT NULL REFERENCES users(user_id),
    token_hash          VARCHAR2(256) NOT NULL,
    device_info         VARCHAR2(500),
    ip_address          VARCHAR2(50),
    expires_at          TIMESTAMP NOT NULL,
    is_revoked          NUMBER(1) DEFAULT 0,
    revoked_at          TIMESTAMP,
    revoked_reason      VARCHAR2(100),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- SYSTEM SETTINGS TABLE
-- ============================================================================
CREATE TABLE system_settings (
    setting_id          RAW(16) DEFAULT SYS_GUID() PRIMARY KEY,
    college_id          RAW(16) REFERENCES colleges(college_id),
    setting_key         VARCHAR2(100) NOT NULL,
    setting_value       CLOB,
    setting_type        VARCHAR2(20) DEFAULT 'STRING'
                        CHECK (setting_type IN ('STRING', 'NUMBER', 'BOOLEAN', 'JSON')),
    is_system           NUMBER(1) DEFAULT 0,
    description         VARCHAR2(500),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_settings UNIQUE (college_id, setting_key)
);

COMMIT;
