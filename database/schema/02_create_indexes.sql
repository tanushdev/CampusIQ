-- ============================================================================
-- CAMPUSIQ - INDEX DEFINITIONS
-- Performance optimization for multi-tenant queries
-- ============================================================================

-- ============================================================================
-- COLLEGES TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_colleges_status ON colleges(status);
CREATE INDEX idx_colleges_email_domain ON colleges(email_domain);
CREATE INDEX idx_colleges_is_deleted ON colleges(is_deleted);

-- ============================================================================
-- USERS TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_users_college_id ON users(college_id);
CREATE INDEX idx_users_role_id ON users(role_id);
CREATE INDEX idx_users_email ON users(LOWER(email));
CREATE INDEX idx_users_google_id ON users(google_id);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_is_deleted ON users(is_deleted);

-- Composite index for tenant-scoped user lookups
CREATE INDEX idx_users_college_status ON users(college_id, status) 
    WHERE is_deleted = 0;

-- ============================================================================
-- FACULTY TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_faculty_college_id ON faculty(college_id);
CREATE INDEX idx_faculty_user_id ON faculty(user_id);
CREATE INDEX idx_faculty_department_id ON faculty(department_id);
CREATE INDEX idx_faculty_status ON faculty(status);
CREATE INDEX idx_faculty_is_deleted ON faculty(is_deleted);

-- Composite for active faculty by college
CREATE INDEX idx_faculty_college_active ON faculty(college_id, status) 
    WHERE is_deleted = 0 AND status = 'ACTIVE';

-- ============================================================================
-- CLASSES TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_classes_college_id ON classes(college_id);
CREATE INDEX idx_classes_department_id ON classes(department_id);
CREATE INDEX idx_classes_class_code ON classes(class_code);
CREATE INDEX idx_classes_academic_year ON classes(academic_year);
CREATE INDEX idx_classes_is_deleted ON classes(is_deleted);

-- Composite for class lookups
CREATE INDEX idx_classes_college_year ON classes(college_id, academic_year) 
    WHERE is_deleted = 0;

-- ============================================================================
-- SUBJECTS TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_subjects_college_id ON subjects(college_id);
CREATE INDEX idx_subjects_department_id ON subjects(department_id);
CREATE INDEX idx_subjects_subject_code ON subjects(subject_code);
CREATE INDEX idx_subjects_short_name ON subjects(short_name);
CREATE INDEX idx_subjects_semester ON subjects(semester);
CREATE INDEX idx_subjects_is_deleted ON subjects(is_deleted);

-- ============================================================================
-- ROOMS TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_rooms_college_id ON rooms(college_id);
CREATE INDEX idx_rooms_room_code ON rooms(room_code);
CREATE INDEX idx_rooms_room_type ON rooms(room_type);
CREATE INDEX idx_rooms_building ON rooms(building);
CREATE INDEX idx_rooms_is_deleted ON rooms(is_deleted);

-- ============================================================================
-- SCHEDULES TABLE INDEXES (CRITICAL FOR QnA QUERIES)
-- ============================================================================
CREATE INDEX idx_schedules_college_id ON schedules(college_id);
CREATE INDEX idx_schedules_class_id ON schedules(class_id);
CREATE INDEX idx_schedules_faculty_id ON schedules(faculty_id);
CREATE INDEX idx_schedules_room_id ON schedules(room_id);
CREATE INDEX idx_schedules_subject_id ON schedules(subject_id);
CREATE INDEX idx_schedules_day_of_week ON schedules(day_of_week);
CREATE INDEX idx_schedules_class_code ON schedules(class_code);
CREATE INDEX idx_schedules_instructor_name ON schedules(instructor_name);
CREATE INDEX idx_schedules_room_code ON schedules(room_code);
CREATE INDEX idx_schedules_academic_year ON schedules(academic_year);
CREATE INDEX idx_schedules_is_deleted ON schedules(is_deleted);

-- Composite indexes for common QnA queries
-- "Which class is free now?"
CREATE INDEX idx_schedules_time_lookup ON schedules(college_id, day_of_week, start_time, end_time) 
    WHERE is_deleted = 0;

-- "Is this faculty free?"
CREATE INDEX idx_schedules_faculty_time ON schedules(college_id, faculty_id, day_of_week, start_time, end_time) 
    WHERE is_deleted = 0;

-- "Free rooms at this time"
CREATE INDEX idx_schedules_room_time ON schedules(college_id, room_id, day_of_week, start_time, end_time) 
    WHERE is_deleted = 0;

-- Class schedule lookup
CREATE INDEX idx_schedules_class_day ON schedules(college_id, class_code, day_of_week) 
    WHERE is_deleted = 0;

-- ============================================================================
-- STUDENTS TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_students_college_id ON students(college_id);
CREATE INDEX idx_students_class_id ON students(class_id);
CREATE INDEX idx_students_enrollment_number ON students(enrollment_number);
CREATE INDEX idx_students_email ON students(email);
CREATE INDEX idx_students_academic_status ON students(academic_status);
CREATE INDEX idx_students_is_deleted ON students(is_deleted);

-- ============================================================================
-- RESULTS TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_results_college_id ON results(college_id);
CREATE INDEX idx_results_student_id ON results(student_id);
CREATE INDEX idx_results_subject_id ON results(subject_id);
CREATE INDEX idx_results_class_id ON results(class_id);
CREATE INDEX idx_results_academic_year ON results(academic_year);
CREATE INDEX idx_results_semester ON results(semester);
CREATE INDEX idx_results_status ON results(result_status);
CREATE INDEX idx_results_is_deleted ON results(is_deleted);

-- Composite for result trends
CREATE INDEX idx_results_analytics ON results(college_id, academic_year, semester, result_status) 
    WHERE is_deleted = 0;

-- ============================================================================
-- FACULTY_CLASS_MAPPING TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_fcm_college_id ON faculty_class_mapping(college_id);
CREATE INDEX idx_fcm_faculty_id ON faculty_class_mapping(faculty_id);
CREATE INDEX idx_fcm_class_id ON faculty_class_mapping(class_id);
CREATE INDEX idx_fcm_subject_id ON faculty_class_mapping(subject_id);
CREATE INDEX idx_fcm_academic_year ON faculty_class_mapping(academic_year);

-- ============================================================================
-- QNA_LOGS TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_qna_logs_college_id ON qna_logs(college_id);
CREATE INDEX idx_qna_logs_user_id ON qna_logs(user_id);
CREATE INDEX idx_qna_logs_created_at ON qna_logs(created_at DESC);
CREATE INDEX idx_qna_logs_intent ON qna_logs(parsed_intent);
CREATE INDEX idx_qna_logs_success ON qna_logs(was_successful);

-- ============================================================================
-- AUDIT_LOGS TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_audit_logs_college_id ON audit_logs(college_id);
CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_action_type ON audit_logs(action_type);
CREATE INDEX idx_audit_logs_entity_type ON audit_logs(entity_type);
CREATE INDEX idx_audit_logs_entity_id ON audit_logs(entity_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_severity ON audit_logs(severity);

-- Composite for security auditing
CREATE INDEX idx_audit_logs_security ON audit_logs(college_id, action_type, created_at DESC);

-- ============================================================================
-- REFRESH_TOKENS TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);
CREATE INDEX idx_refresh_tokens_revoked ON refresh_tokens(is_revoked);

-- ============================================================================
-- EMAIL_DOMAIN_MAPPING TABLE INDEXES
-- ============================================================================
CREATE INDEX idx_edm_college_id ON email_domain_mapping(college_id);
CREATE INDEX idx_edm_active ON email_domain_mapping(is_active);

COMMIT;
