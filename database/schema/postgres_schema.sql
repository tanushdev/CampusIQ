-- ============================================================================
-- CAMPUSIQ - COMPLETE POSTGRESQL PRODUCTION SCHEMA
-- For hosting on Aiven, Render, Railway, or Supabase
-- Robust version with explicit schema references and UUID extension checks
-- ============================================================================

-- 1. SETUP EXTENSIONS (Run this first!)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. CLEANUP (Drop tables if they exist to start fresh)
DROP TABLE IF EXISTS public.audit_logs CASCADE;
DROP TABLE IF EXISTS public.qna_logs CASCADE;
DROP TABLE IF EXISTS public.faculty_class_mapping CASCADE;
DROP TABLE IF EXISTS public.results CASCADE;
DROP TABLE IF EXISTS public.students CASCADE;
DROP TABLE IF EXISTS public.schedules CASCADE;
DROP TABLE IF EXISTS public.rooms CASCADE;
DROP TABLE IF EXISTS public.subjects CASCADE;
DROP TABLE IF EXISTS public.classes CASCADE;
DROP TABLE IF EXISTS public.faculty CASCADE;
DROP TABLE IF EXISTS public.departments CASCADE;
DROP TABLE IF EXISTS public.email_domain_mapping CASCADE;
DROP TABLE IF EXISTS public.refresh_tokens CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;
DROP TABLE IF EXISTS public.colleges CASCADE;
DROP TABLE IF EXISTS public.roles CASCADE;
DROP TABLE IF EXISTS public.system_settings CASCADE;

-- ============================================================================
-- 3. TABLES (Created in dependency order)
-- ============================================================================

-- ROLES TABLE
CREATE TABLE public.roles (
    role_id         UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    role_name       VARCHAR(50) NOT NULL UNIQUE,
    role_code       VARCHAR(20) NOT NULL UNIQUE,
    description     TEXT,
    hierarchy_level INTEGER NOT NULL,
    is_system_role  BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert predefined roles
INSERT INTO public.roles (role_name, role_code, hierarchy_level, description) VALUES
    ('Super Admin', 'SUPER_ADMIN', 100, 'Platform owner with full system access'),
    ('College Admin', 'COLLEGE_ADMIN', 50, 'Tenant-level administrator for a college'),
    ('Faculty', 'FACULTY', 10, 'Teaching staff with class/schedule access'),
    ('Staff', 'STAFF', 5, 'Non-teaching staff with limited access'),
    ('Student', 'STUDENT', 1, 'Student with read-only access');

-- COLLEGES TABLE
CREATE TABLE public.colleges (
    college_id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_name        VARCHAR(200) NOT NULL,
    college_code        VARCHAR(50) UNIQUE,
    college_logo_url    VARCHAR(1000),
    email_domain        VARCHAR(100),
    website_url         VARCHAR(500),
    address             VARCHAR(500),
    city                VARCHAR(100),
    state               VARCHAR(100),
    country             VARCHAR(100) DEFAULT 'India',
    postal_code         VARCHAR(20),
    phone               VARCHAR(50),
    status              VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'SUSPENDED', 'DELETED')),
    timezone            VARCHAR(50) DEFAULT 'Asia/Kolkata',
    academic_year       VARCHAR(20),
    subscription_tier   VARCHAR(20) DEFAULT 'BASIC' CHECK (subscription_tier IN ('BASIC', 'STANDARD', 'PREMIUM', 'ENTERPRISE')),
    max_users           INTEGER DEFAULT 100,
    approved_by         UUID,
    approved_at         TIMESTAMP,
    suspended_reason    VARCHAR(500),
    is_deleted          BOOLEAN DEFAULT FALSE,
    created_by          UUID,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- EMAIL DOMAIN MAPPING (The one that was failing)
CREATE TABLE public.email_domain_mapping (
    mapping_id      UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id      UUID NOT NULL REFERENCES public.colleges(college_id),
    domain          VARCHAR(100) NOT NULL UNIQUE,
    is_primary      BOOLEAN DEFAULT FALSE,
    is_active       BOOLEAN DEFAULT TRUE,
    verified_at     TIMESTAMP,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- USERS TABLE
CREATE TABLE public.users (
    user_id             UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    email               VARCHAR(255) NOT NULL UNIQUE,
    google_id           VARCHAR(100) UNIQUE,
    full_name           VARCHAR(200),
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    avatar_url          VARCHAR(1000),
    phone               VARCHAR(50),
    role_id             UUID NOT NULL REFERENCES public.roles(role_id),
    college_id          UUID REFERENCES public.colleges(college_id),
    department_id       UUID,
    status              VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING')),
    email_verified      BOOLEAN DEFAULT FALSE,
    last_login_at       TIMESTAMP,
    last_login_ip       VARCHAR(50),
    login_count         INTEGER DEFAULT 0,
    failed_login_count  INTEGER DEFAULT 0,
    locked_until        TIMESTAMP,
    preferences         JSONB,
    is_deleted          BOOLEAN DEFAULT FALSE,
    created_by          UUID,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- DEPARTMENTS TABLE
CREATE TABLE public.departments (
    department_id       UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID NOT NULL REFERENCES public.colleges(college_id),
    department_name     VARCHAR(200) NOT NULL,
    department_code     VARCHAR(50),
    description         VARCHAR(500),
    head_user_id        UUID REFERENCES public.users(user_id),
    is_active           BOOLEAN DEFAULT TRUE,
    is_deleted          BOOLEAN DEFAULT FALSE,
    created_by          UUID,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_dept_college UNIQUE (college_id, department_code)
);

-- FACULTY TABLE
CREATE TABLE public.faculty (
    faculty_id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID NOT NULL REFERENCES public.colleges(college_id),
    user_id             UUID NOT NULL UNIQUE REFERENCES public.users(user_id),
    department_id       UUID REFERENCES public.departments(department_id),
    employee_code       VARCHAR(50),
    designation         VARCHAR(100),
    qualification       VARCHAR(200),
    specialization      VARCHAR(200),
    experience_years    INTEGER,
    joining_date        DATE,
    status              VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'ON_LEAVE', 'RESIGNED')),
    is_deleted          BOOLEAN DEFAULT FALSE,
    created_by          UUID,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- CLASSES TABLE
CREATE TABLE public.classes (
    class_id            UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID NOT NULL REFERENCES public.colleges(college_id),
    department_id       UUID REFERENCES public.departments(department_id),
    class_code          VARCHAR(50) NOT NULL,
    class_name          VARCHAR(200),
    year                INTEGER,
    semester            INTEGER,
    division            VARCHAR(10),
    batch               VARCHAR(20),
    academic_year       VARCHAR(20),
    class_teacher_id    UUID REFERENCES public.faculty(faculty_id),
    max_students        INTEGER DEFAULT 60,
    is_active           BOOLEAN DEFAULT TRUE,
    is_deleted          BOOLEAN DEFAULT FALSE,
    created_by          UUID,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_class_college UNIQUE (college_id, class_code, academic_year)
);

-- SUBJECTS TABLE
CREATE TABLE public.subjects (
    subject_id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID NOT NULL REFERENCES public.colleges(college_id),
    department_id       UUID REFERENCES public.departments(department_id),
    subject_code        VARCHAR(50),
    subject_name        VARCHAR(200) NOT NULL,
    short_name          VARCHAR(50),
    credits             INTEGER,
    lecture_hours       INTEGER,
    practical_hours     INTEGER,
    tutorial_hours      INTEGER,
    semester            INTEGER,
    subject_type        VARCHAR(20) DEFAULT 'CORE' CHECK (subject_type IN ('CORE', 'ELECTIVE', 'LAB', 'PROJECT', 'SEMINAR')),
    is_active           BOOLEAN DEFAULT TRUE,
    is_deleted          BOOLEAN DEFAULT FALSE,
    created_by          UUID,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ROOMS TABLE
CREATE TABLE public.rooms (
    room_id             UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID NOT NULL REFERENCES public.colleges(college_id),
    room_code           VARCHAR(50) NOT NULL,
    room_name           VARCHAR(100),
    building            VARCHAR(100),
    floor               INTEGER,
    capacity            INTEGER,
    room_type           VARCHAR(30) DEFAULT 'CLASSROOM' CHECK (room_type IN ('CLASSROOM', 'LAB', 'SEMINAR_HALL', 'AUDITORIUM', 'LIBRARY', 'OFFICE', 'STAFF_ROOM', 'OTHER')),
    has_projector       BOOLEAN DEFAULT FALSE,
    has_ac              BOOLEAN DEFAULT FALSE,
    has_whiteboard      BOOLEAN DEFAULT TRUE,
    is_active           BOOLEAN DEFAULT TRUE,
    is_deleted          BOOLEAN DEFAULT FALSE,
    created_by          UUID,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_room_college UNIQUE (college_id, room_code)
);

-- SCHEDULES TABLE
CREATE TABLE public.schedules (
    schedule_id         UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID NOT NULL REFERENCES public.colleges(college_id),
    class_id            UUID REFERENCES public.classes(class_id),
    class_code          VARCHAR(50),
    subject_id          UUID REFERENCES public.subjects(subject_id),
    subject_name        VARCHAR(200),
    faculty_id          UUID REFERENCES public.faculty(faculty_id),
    instructor_name     VARCHAR(200),
    room_id             UUID REFERENCES public.rooms(room_id),
    room_code           VARCHAR(50),
    day_of_week         INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time          VARCHAR(10) NOT NULL,
    end_time            VARCHAR(10) NOT NULL,
    schedule_type       VARCHAR(20) DEFAULT 'LECTURE' CHECK (schedule_type IN ('LECTURE', 'LAB', 'TUTORIAL', 'SEMINAR', 'PRACTICAL', 'BREAK', 'OTHER')),
    is_break            BOOLEAN DEFAULT FALSE,
    academic_year       VARCHAR(20),
    semester            INTEGER,
    effective_from      DATE,
    effective_to        DATE,
    notes               TEXT,
    is_deleted          BOOLEAN DEFAULT FALSE,
    created_by          UUID,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- STUDENTS TABLE
CREATE TABLE public.students (
    student_id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID NOT NULL REFERENCES public.colleges(college_id),
    user_id             UUID REFERENCES public.users(user_id),
    class_id            UUID REFERENCES public.classes(class_id),
    enrollment_number   VARCHAR(50),
    roll_number         VARCHAR(20),
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    email               VARCHAR(255),
    phone               VARCHAR(50),
    date_of_birth       DATE,
    gender              VARCHAR(10),
    admission_year      INTEGER,
    academic_status     VARCHAR(20) DEFAULT 'ACTIVE' CHECK (academic_status IN ('ACTIVE', 'GRADUATED', 'DROPPED', 'SUSPENDED', 'ON_LEAVE')),
    is_deleted          BOOLEAN DEFAULT FALSE,
    created_by          UUID,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_student_enrollment UNIQUE (college_id, enrollment_number)
);

-- RESULTS TABLE
CREATE TABLE public.results (
    result_id           UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID NOT NULL REFERENCES public.colleges(college_id),
    student_id          UUID NOT NULL REFERENCES public.students(student_id),
    subject_id          UUID REFERENCES public.subjects(subject_id),
    class_id            UUID REFERENCES public.classes(class_id),
    exam_type           VARCHAR(30) DEFAULT 'REGULAR' CHECK (exam_type IN ('REGULAR', 'SUPPLEMENTARY', 'IMPROVEMENT', 'INTERNAL')),
    internal_marks      NUMERIC(5,2),
    external_marks      NUMERIC(5,2),
    total_marks         NUMERIC(5,2),
    max_marks           NUMERIC(5,2) DEFAULT 100,
    grade               VARCHAR(5),
    grade_points        NUMERIC(4,2),
    result_status       VARCHAR(20) DEFAULT 'PENDING' CHECK (result_status IN ('PENDING', 'PASS', 'FAIL', 'ABSENT', 'WITHHELD')),
    academic_year       VARCHAR(20),
    semester            INTEGER,
    exam_date           DATE,
    published_at        TIMESTAMP,
    is_deleted          BOOLEAN DEFAULT FALSE,
    created_by          UUID,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by          UUID,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- FACULTY CLASS MAPPING
CREATE TABLE public.faculty_class_mapping (
    mapping_id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID NOT NULL REFERENCES public.colleges(college_id),
    faculty_id          UUID NOT NULL REFERENCES public.faculty(faculty_id),
    class_id            UUID NOT NULL REFERENCES public.classes(class_id),
    subject_id          UUID REFERENCES public.subjects(subject_id),
    academic_year       VARCHAR(20),
    is_primary          BOOLEAN DEFAULT FALSE,
    is_active           BOOLEAN DEFAULT TRUE,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_fcm UNIQUE (faculty_id, class_id, subject_id, academic_year)
);

-- QNA LOGS TABLE
CREATE TABLE public.qna_logs (
    log_id              UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID NOT NULL REFERENCES public.colleges(college_id),
    user_id             UUID REFERENCES public.users(user_id),
    session_id          VARCHAR(100),
    question            TEXT NOT NULL,
    parsed_intent       VARCHAR(100),
    extracted_entities  JSONB,
    response            TEXT,
    response_time_ms    INTEGER,
    was_successful      BOOLEAN DEFAULT TRUE,
    error_message       TEXT,
    feedback_rating     INTEGER,
    feedback_comment    TEXT,
    ip_address          VARCHAR(50),
    user_agent          VARCHAR(500),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- AUDIT LOGS TABLE
CREATE TABLE public.audit_logs (
    log_id              UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID REFERENCES public.colleges(college_id),
    user_id             UUID REFERENCES public.users(user_id),
    user_email          VARCHAR(255),
    user_role           VARCHAR(50),
    action_type         VARCHAR(50) NOT NULL,
    entity_type         VARCHAR(100),
    entity_id           UUID,
    entity_name         VARCHAR(200),
    old_value           JSONB,
    new_value           JSONB,
    change_summary      VARCHAR(500),
    ip_address          VARCHAR(50),
    user_agent          VARCHAR(500),
    request_path        VARCHAR(500),
    request_method      VARCHAR(10),
    response_status     INTEGER,
    severity            VARCHAR(20) DEFAULT 'INFO' CHECK (severity IN ('DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL')),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- REFRESH TOKENS TABLE
CREATE TABLE public.refresh_tokens (
    token_id            UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id             UUID NOT NULL REFERENCES public.users(user_id),
    token_hash          VARCHAR(256) NOT NULL,
    device_info         VARCHAR(500),
    ip_address          VARCHAR(50),
    expires_at          TIMESTAMP NOT NULL,
    is_revoked          BOOLEAN DEFAULT FALSE,
    revoked_at          TIMESTAMP,
    revoked_reason      VARCHAR(100),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- SYSTEM SETTINGS TABLE
CREATE TABLE public.system_settings (
    setting_id          UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    college_id          UUID REFERENCES public.colleges(college_id),
    setting_key         VARCHAR(100) NOT NULL,
    setting_value       TEXT,
    setting_type        VARCHAR(20) DEFAULT 'STRING' CHECK (setting_type IN ('STRING', 'NUMBER', 'BOOLEAN', 'JSON')),
    is_system           BOOLEAN DEFAULT FALSE,
    description         VARCHAR(500),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_settings UNIQUE (college_id, setting_key)
);

-- ============================================================================
-- 4. INDEXES
-- ============================================================================

-- COLLEGES TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_colleges_status ON public.colleges(status);
CREATE INDEX IF NOT EXISTS idx_colleges_email_domain ON public.colleges(email_domain);
CREATE INDEX IF NOT EXISTS idx_colleges_is_deleted ON public.colleges(is_deleted);

-- USERS TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_users_college_id ON public.users(college_id);
CREATE INDEX IF NOT EXISTS idx_users_role_id ON public.users(role_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(LOWER(email));
CREATE INDEX IF NOT EXISTS idx_users_google_id ON public.users(google_id);
CREATE INDEX IF NOT EXISTS idx_users_status ON public.users(status);
CREATE INDEX IF NOT EXISTS idx_users_is_deleted ON public.users(is_deleted);
CREATE INDEX IF NOT EXISTS idx_users_college_status ON public.users(college_id, status) WHERE is_deleted = FALSE;

-- FACULTY TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_faculty_college_id ON public.faculty(college_id);
CREATE INDEX IF NOT EXISTS idx_faculty_user_id ON public.faculty(user_id);
CREATE INDEX IF NOT EXISTS idx_faculty_department_id ON public.faculty(department_id);
CREATE INDEX IF NOT EXISTS idx_faculty_status ON public.faculty(status);
CREATE INDEX IF NOT EXISTS idx_faculty_is_deleted ON public.faculty(is_deleted);
CREATE INDEX IF NOT EXISTS idx_faculty_college_active ON public.faculty(college_id, status) WHERE is_deleted = FALSE AND status = 'ACTIVE';

-- CLASSES TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_classes_college_id ON public.classes(college_id);
CREATE INDEX IF NOT EXISTS idx_classes_department_id ON public.classes(department_id);
CREATE INDEX IF NOT EXISTS idx_classes_class_code ON public.classes(class_code);
CREATE INDEX IF NOT EXISTS idx_classes_academic_year ON public.classes(academic_year);
CREATE INDEX IF NOT EXISTS idx_classes_is_deleted ON public.classes(is_deleted);
CREATE INDEX IF NOT EXISTS idx_classes_college_year ON public.classes(college_id, academic_year) WHERE is_deleted = FALSE;

-- SUBJECTS TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_subjects_college_id ON public.subjects(college_id);
CREATE INDEX IF NOT EXISTS idx_subjects_department_id ON public.subjects(department_id);
CREATE INDEX IF NOT EXISTS idx_subjects_subject_code ON public.subjects(subject_code);
CREATE INDEX IF NOT EXISTS idx_subjects_short_name ON public.subjects(short_name);
CREATE INDEX IF NOT EXISTS idx_subjects_semester ON public.subjects(semester);
CREATE INDEX IF NOT EXISTS idx_subjects_is_deleted ON public.subjects(is_deleted);

-- ROOMS TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_rooms_college_id ON public.rooms(college_id);
CREATE INDEX IF NOT EXISTS idx_rooms_room_code ON public.rooms(room_code);
CREATE INDEX IF NOT EXISTS idx_rooms_room_type ON public.rooms(room_type);
CREATE INDEX IF NOT EXISTS idx_rooms_building ON public.rooms(building);
CREATE INDEX IF NOT EXISTS idx_rooms_is_deleted ON public.rooms(is_deleted);

-- SCHEDULES TABLE INDEXES (Critical for QnA)
CREATE INDEX IF NOT EXISTS idx_schedules_college_id ON public.schedules(college_id);
CREATE INDEX IF NOT EXISTS idx_schedules_class_id ON public.schedules(class_id);
CREATE INDEX IF NOT EXISTS idx_schedules_faculty_id ON public.schedules(faculty_id);
CREATE INDEX IF NOT EXISTS idx_schedules_room_id ON public.schedules(room_id);
CREATE INDEX IF NOT EXISTS idx_schedules_subject_id ON public.schedules(subject_id);
CREATE INDEX IF NOT EXISTS idx_schedules_day_of_week ON public.schedules(day_of_week);
CREATE INDEX IF NOT EXISTS idx_schedules_class_code ON public.schedules(class_code);
CREATE INDEX IF NOT EXISTS idx_schedules_instructor_name ON public.schedules(instructor_name);
CREATE INDEX IF NOT EXISTS idx_schedules_room_code ON public.schedules(room_code);
CREATE INDEX IF NOT EXISTS idx_schedules_academic_year ON public.schedules(academic_year);
CREATE INDEX IF NOT EXISTS idx_schedules_is_deleted ON public.schedules(is_deleted);
CREATE INDEX IF NOT EXISTS idx_schedules_time_lookup ON public.schedules(college_id, day_of_week, start_time, end_time) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_schedules_faculty_time ON public.schedules(college_id, faculty_id, day_of_week, start_time, end_time) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_schedules_room_time ON public.schedules(college_id, room_id, day_of_week, start_time, end_time) WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_schedules_class_day ON public.schedules(college_id, class_code, day_of_week) WHERE is_deleted = FALSE;

-- STUDENTS TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_students_college_id ON public.students(college_id);
CREATE INDEX IF NOT EXISTS idx_students_class_id ON public.students(class_id);
CREATE INDEX IF NOT EXISTS idx_students_enrollment_number ON public.students(enrollment_number);
CREATE INDEX IF NOT EXISTS idx_students_email ON public.students(email);
CREATE INDEX IF NOT EXISTS idx_students_academic_status ON public.students(academic_status);
CREATE INDEX IF NOT EXISTS idx_students_is_deleted ON public.students(is_deleted);

-- RESULTS TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_results_college_id ON public.results(college_id);
CREATE INDEX IF NOT EXISTS idx_results_student_id ON public.results(student_id);
CREATE INDEX IF NOT EXISTS idx_results_subject_id ON public.results(subject_id);
CREATE INDEX IF NOT EXISTS idx_results_class_id ON public.results(class_id);
CREATE INDEX IF NOT EXISTS idx_results_academic_year ON public.results(academic_year);
CREATE INDEX IF NOT EXISTS idx_results_semester ON public.results(semester);
CREATE INDEX IF NOT EXISTS idx_results_status ON public.results(result_status);
CREATE INDEX IF NOT EXISTS idx_results_is_deleted ON public.results(is_deleted);
CREATE INDEX IF NOT EXISTS idx_results_analytics ON public.results(college_id, academic_year, semester, result_status) WHERE is_deleted = FALSE;

-- FACULTY_CLASS_MAPPING TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_fcm_college_id ON public.faculty_class_mapping(college_id);
CREATE INDEX IF NOT EXISTS idx_fcm_faculty_id ON public.faculty_class_mapping(faculty_id);
CREATE INDEX IF NOT EXISTS idx_fcm_class_id ON public.faculty_class_mapping(class_id);
CREATE INDEX IF NOT EXISTS idx_fcm_subject_id ON public.faculty_class_mapping(subject_id);
CREATE INDEX IF NOT EXISTS idx_fcm_academic_year ON public.faculty_class_mapping(academic_year);

-- QNA_LOGS TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_qna_logs_college_id ON public.qna_logs(college_id);
CREATE INDEX IF NOT EXISTS idx_qna_logs_user_id ON public.qna_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_qna_logs_created_at ON public.qna_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_qna_logs_intent ON public.qna_logs(parsed_intent);
CREATE INDEX IF NOT EXISTS idx_qna_logs_success ON public.qna_logs(was_successful);

-- AUDIT_LOGS TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_audit_logs_college_id ON public.audit_logs(college_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action_type ON public.audit_logs(action_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity_type ON public.audit_logs(entity_type);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity_id ON public.audit_logs(entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_severity ON public.audit_logs(severity);
CREATE INDEX IF NOT EXISTS idx_audit_logs_security ON public.audit_logs(college_id, action_type, created_at DESC);

-- REFRESH_TOKENS TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON public.refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON public.refresh_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_revoked ON public.refresh_tokens(is_revoked);

-- EMAIL_DOMAIN_MAPPING TABLE INDEXES
CREATE INDEX IF NOT EXISTS idx_edm_college_id ON public.email_domain_mapping(college_id);
CREATE INDEX IF NOT EXISTS idx_edm_active ON public.email_domain_mapping(is_active);
