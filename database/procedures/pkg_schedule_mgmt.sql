-- ============================================================================
-- CAMPUSIQ - SCHEDULE MANAGEMENT PL/SQL PACKAGE
-- ============================================================================

CREATE OR REPLACE PACKAGE pkg_schedule_mgmt AS
    -- Types
    TYPE t_schedule_rec IS RECORD (
        schedule_id     RAW(16),
        class_code      VARCHAR2(50),
        subject_name    VARCHAR2(200),
        instructor_name VARCHAR2(200),
        room_code       VARCHAR2(50),
        start_time      VARCHAR2(10),
        end_time        VARCHAR2(10),
        day_of_week     NUMBER(1)
    );
    
    TYPE t_schedule_tab IS TABLE OF t_schedule_rec;
    TYPE t_room_list IS TABLE OF VARCHAR2(50);
    TYPE t_faculty_list IS TABLE OF VARCHAR2(200);
    
    -- Schedule CRUD
    PROCEDURE create_schedule(
        p_college_id    IN RAW,
        p_class_code    IN VARCHAR2,
        p_subject_name  IN VARCHAR2,
        p_instructor    IN VARCHAR2,
        p_room_code     IN VARCHAR2,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_academic_year IN VARCHAR2,
        p_created_by    IN RAW,
        p_schedule_id   OUT RAW,
        p_error_msg     OUT VARCHAR2
    );
    
    PROCEDURE update_schedule(
        p_schedule_id   IN RAW,
        p_college_id    IN RAW,
        p_class_code    IN VARCHAR2,
        p_subject_name  IN VARCHAR2,
        p_instructor    IN VARCHAR2,
        p_room_code     IN VARCHAR2,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_updated_by    IN RAW,
        p_error_msg     OUT VARCHAR2
    );
    
    PROCEDURE delete_schedule(
        p_schedule_id   IN RAW,
        p_college_id    IN RAW,
        p_deleted_by    IN RAW,
        p_error_msg     OUT VARCHAR2
    );
    
    -- Availability Checks
    FUNCTION is_room_available(
        p_college_id    IN RAW,
        p_room_code     IN VARCHAR2,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_exclude_id    IN RAW DEFAULT NULL
    ) RETURN BOOLEAN;
    
    FUNCTION is_faculty_available(
        p_college_id    IN RAW,
        p_instructor    IN VARCHAR2,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_exclude_id    IN RAW DEFAULT NULL
    ) RETURN BOOLEAN;
    
    FUNCTION is_class_available(
        p_college_id    IN RAW,
        p_class_code    IN VARCHAR2,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_exclude_id    IN RAW DEFAULT NULL
    ) RETURN BOOLEAN;
    
    -- Query Functions for QnA
    FUNCTION get_free_rooms(
        p_college_id    IN RAW,
        p_day_of_week   IN NUMBER,
        p_time          IN VARCHAR2
    ) RETURN SYS_REFCURSOR;
    
    FUNCTION get_free_faculty(
        p_college_id    IN RAW,
        p_day_of_week   IN NUMBER,
        p_time          IN VARCHAR2
    ) RETURN SYS_REFCURSOR;
    
    FUNCTION get_class_schedule(
        p_college_id    IN RAW,
        p_class_code    IN VARCHAR2,
        p_day_of_week   IN NUMBER DEFAULT NULL
    ) RETURN SYS_REFCURSOR;
    
    FUNCTION get_faculty_schedule(
        p_college_id    IN RAW,
        p_instructor    IN VARCHAR2,
        p_day_of_week   IN NUMBER DEFAULT NULL
    ) RETURN SYS_REFCURSOR;
    
    FUNCTION get_room_schedule(
        p_college_id    IN RAW,
        p_room_code     IN VARCHAR2,
        p_day_of_week   IN NUMBER DEFAULT NULL
    ) RETURN SYS_REFCURSOR;
    
    -- Conflict Detection
    FUNCTION check_schedule_conflicts(
        p_college_id    IN RAW,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_class_code    IN VARCHAR2 DEFAULT NULL,
        p_instructor    IN VARCHAR2 DEFAULT NULL,
        p_room_code     IN VARCHAR2 DEFAULT NULL,
        p_exclude_id    IN RAW DEFAULT NULL
    ) RETURN SYS_REFCURSOR;
    
END pkg_schedule_mgmt;
/

CREATE OR REPLACE PACKAGE BODY pkg_schedule_mgmt AS

    -- Helper function to check time overlap
    FUNCTION times_overlap(
        p_start1 VARCHAR2, p_end1 VARCHAR2,
        p_start2 VARCHAR2, p_end2 VARCHAR2
    ) RETURN BOOLEAN IS
        v_start1 NUMBER;
        v_end1   NUMBER;
        v_start2 NUMBER;
        v_end2   NUMBER;
    BEGIN
        -- Convert to minutes since midnight
        v_start1 := TO_NUMBER(SUBSTR(p_start1, 1, INSTR(p_start1, ':') - 1)) * 60 +
                    TO_NUMBER(SUBSTR(p_start1, INSTR(p_start1, ':') + 1));
        v_end1   := TO_NUMBER(SUBSTR(p_end1, 1, INSTR(p_end1, ':') - 1)) * 60 +
                    TO_NUMBER(SUBSTR(p_end1, INSTR(p_end1, ':') + 1));
        v_start2 := TO_NUMBER(SUBSTR(p_start2, 1, INSTR(p_start2, ':') - 1)) * 60 +
                    TO_NUMBER(SUBSTR(p_start2, INSTR(p_start2, ':') + 1));
        v_end2   := TO_NUMBER(SUBSTR(p_end2, 1, INSTR(p_end2, ':') - 1)) * 60 +
                    TO_NUMBER(SUBSTR(p_end2, INSTR(p_end2, ':') + 1));
        
        -- Handle PM times
        IF v_start1 < 540 AND INSTR(UPPER(p_start1), 'PM') > 0 THEN v_start1 := v_start1 + 720; END IF;
        IF v_end1 < 540 AND INSTR(UPPER(p_end1), 'PM') > 0 THEN v_end1 := v_end1 + 720; END IF;
        IF v_start2 < 540 AND INSTR(UPPER(p_start2), 'PM') > 0 THEN v_start2 := v_start2 + 720; END IF;
        IF v_end2 < 540 AND INSTR(UPPER(p_end2), 'PM') > 0 THEN v_end2 := v_end2 + 720; END IF;
        
        RETURN NOT (v_end1 <= v_start2 OR v_end2 <= v_start1);
    EXCEPTION
        WHEN OTHERS THEN
            RETURN FALSE;
    END times_overlap;

    -- Create Schedule
    PROCEDURE create_schedule(
        p_college_id    IN RAW,
        p_class_code    IN VARCHAR2,
        p_subject_name  IN VARCHAR2,
        p_instructor    IN VARCHAR2,
        p_room_code     IN VARCHAR2,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_academic_year IN VARCHAR2,
        p_created_by    IN RAW,
        p_schedule_id   OUT RAW,
        p_error_msg     OUT VARCHAR2
    ) IS
        v_conflict_count NUMBER;
    BEGIN
        p_error_msg := NULL;
        p_schedule_id := SYS_GUID();
        
        -- Check room availability
        IF NOT is_room_available(p_college_id, p_room_code, p_day_of_week, p_start_time, p_end_time) THEN
            p_error_msg := 'Room ' || p_room_code || ' is not available at the specified time';
            RETURN;
        END IF;
        
        -- Check faculty availability
        IF p_instructor IS NOT NULL AND 
           NOT is_faculty_available(p_college_id, p_instructor, p_day_of_week, p_start_time, p_end_time) THEN
            p_error_msg := 'Faculty ' || p_instructor || ' is not available at the specified time';
            RETURN;
        END IF;
        
        -- Check class availability
        IF NOT is_class_available(p_college_id, p_class_code, p_day_of_week, p_start_time, p_end_time) THEN
            p_error_msg := 'Class ' || p_class_code || ' already has a schedule at the specified time';
            RETURN;
        END IF;
        
        -- Insert schedule
        INSERT INTO schedules (
            schedule_id, college_id, class_code, subject_name, instructor_name,
            room_code, day_of_week, start_time, end_time, academic_year,
            created_by, created_at, updated_at
        ) VALUES (
            p_schedule_id, p_college_id, p_class_code, p_subject_name, p_instructor,
            p_room_code, p_day_of_week, p_start_time, p_end_time, p_academic_year,
            p_created_by, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        );
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            p_error_msg := SQLERRM;
            ROLLBACK;
    END create_schedule;

    -- Update Schedule
    PROCEDURE update_schedule(
        p_schedule_id   IN RAW,
        p_college_id    IN RAW,
        p_class_code    IN VARCHAR2,
        p_subject_name  IN VARCHAR2,
        p_instructor    IN VARCHAR2,
        p_room_code     IN VARCHAR2,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_updated_by    IN RAW,
        p_error_msg     OUT VARCHAR2
    ) IS
    BEGIN
        p_error_msg := NULL;
        
        -- Validate schedule exists and belongs to college
        DECLARE
            v_count NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_count
            FROM schedules
            WHERE schedule_id = p_schedule_id
              AND college_id = p_college_id
              AND is_deleted = 0;
              
            IF v_count = 0 THEN
                p_error_msg := 'Schedule not found or access denied';
                RETURN;
            END IF;
        END;
        
        -- Check room availability (excluding current schedule)
        IF NOT is_room_available(p_college_id, p_room_code, p_day_of_week, 
                                 p_start_time, p_end_time, p_schedule_id) THEN
            p_error_msg := 'Room ' || p_room_code || ' is not available at the specified time';
            RETURN;
        END IF;
        
        -- Check faculty availability (excluding current schedule)
        IF p_instructor IS NOT NULL AND 
           NOT is_faculty_available(p_college_id, p_instructor, p_day_of_week, 
                                    p_start_time, p_end_time, p_schedule_id) THEN
            p_error_msg := 'Faculty ' || p_instructor || ' is not available at the specified time';
            RETURN;
        END IF;
        
        -- Check class availability (excluding current schedule)
        IF NOT is_class_available(p_college_id, p_class_code, p_day_of_week, 
                                  p_start_time, p_end_time, p_schedule_id) THEN
            p_error_msg := 'Class ' || p_class_code || ' already has a schedule at the specified time';
            RETURN;
        END IF;
        
        -- Update schedule
        UPDATE schedules
        SET class_code = p_class_code,
            subject_name = p_subject_name,
            instructor_name = p_instructor,
            room_code = p_room_code,
            day_of_week = p_day_of_week,
            start_time = p_start_time,
            end_time = p_end_time,
            updated_at = CURRENT_TIMESTAMP,
            updated_by = p_updated_by
        WHERE schedule_id = p_schedule_id
          AND college_id = p_college_id;
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            p_error_msg := SQLERRM;
            ROLLBACK;
    END update_schedule;

    -- Delete Schedule (Soft Delete)
    PROCEDURE delete_schedule(
        p_schedule_id   IN RAW,
        p_college_id    IN RAW,
        p_deleted_by    IN RAW,
        p_error_msg     OUT VARCHAR2
    ) IS
    BEGIN
        p_error_msg := NULL;
        
        UPDATE schedules
        SET is_deleted = 1,
            updated_at = CURRENT_TIMESTAMP,
            updated_by = p_deleted_by
        WHERE schedule_id = p_schedule_id
          AND college_id = p_college_id
          AND is_deleted = 0;
        
        IF SQL%ROWCOUNT = 0 THEN
            p_error_msg := 'Schedule not found or access denied';
            RETURN;
        END IF;
        
        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            p_error_msg := SQLERRM;
            ROLLBACK;
    END delete_schedule;

    -- Check Room Availability
    FUNCTION is_room_available(
        p_college_id    IN RAW,
        p_room_code     IN VARCHAR2,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_exclude_id    IN RAW DEFAULT NULL
    ) RETURN BOOLEAN IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO v_count
        FROM schedules
        WHERE college_id = p_college_id
          AND room_code = p_room_code
          AND day_of_week = p_day_of_week
          AND is_deleted = 0
          AND is_break = 0
          AND (p_exclude_id IS NULL OR schedule_id != p_exclude_id)
          AND (
              -- Check time overlap
              (start_time <= p_start_time AND end_time > p_start_time) OR
              (start_time < p_end_time AND end_time >= p_end_time) OR
              (start_time >= p_start_time AND end_time <= p_end_time)
          );
        
        RETURN v_count = 0;
    END is_room_available;

    -- Check Faculty Availability
    FUNCTION is_faculty_available(
        p_college_id    IN RAW,
        p_instructor    IN VARCHAR2,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_exclude_id    IN RAW DEFAULT NULL
    ) RETURN BOOLEAN IS
        v_count NUMBER;
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
          AND is_deleted = 0
          AND is_break = 0
          AND (p_exclude_id IS NULL OR schedule_id != p_exclude_id)
          AND (
              (start_time <= p_start_time AND end_time > p_start_time) OR
              (start_time < p_end_time AND end_time >= p_end_time) OR
              (start_time >= p_start_time AND end_time <= p_end_time)
          );
        
        RETURN v_count = 0;
    END is_faculty_available;

    -- Check Class Availability
    FUNCTION is_class_available(
        p_college_id    IN RAW,
        p_class_code    IN VARCHAR2,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_exclude_id    IN RAW DEFAULT NULL
    ) RETURN BOOLEAN IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*)
        INTO v_count
        FROM schedules
        WHERE college_id = p_college_id
          AND class_code = p_class_code
          AND day_of_week = p_day_of_week
          AND is_deleted = 0
          AND is_break = 0
          AND (p_exclude_id IS NULL OR schedule_id != p_exclude_id)
          AND (
              (start_time <= p_start_time AND end_time > p_start_time) OR
              (start_time < p_end_time AND end_time >= p_end_time) OR
              (start_time >= p_start_time AND end_time <= p_end_time)
          );
        
        RETURN v_count = 0;
    END is_class_available;

    -- Get Free Rooms at a specific time
    FUNCTION get_free_rooms(
        p_college_id    IN RAW,
        p_day_of_week   IN NUMBER,
        p_time          IN VARCHAR2
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT r.room_code, r.room_name, r.room_type, r.capacity, r.building
            FROM rooms r
            WHERE r.college_id = p_college_id
              AND r.is_deleted = 0
              AND NOT EXISTS (
                  SELECT 1
                  FROM schedules s
                  WHERE s.college_id = p_college_id
                    AND s.room_code = r.room_code
                    AND s.day_of_week = p_day_of_week
                    AND s.is_deleted = 0
                    AND s.is_break = 0
                    AND s.start_time <= p_time
                    AND s.end_time > p_time
              )
            ORDER BY r.room_code;
        
        RETURN v_cursor;
    END get_free_rooms;

    -- Get Free Faculty at a specific time
    FUNCTION get_free_faculty(
        p_college_id    IN RAW,
        p_day_of_week   IN NUMBER,
        p_time          IN VARCHAR2
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT DISTINCT f.faculty_id, u.full_name, f.designation, f.department_id
            FROM faculty f
            JOIN users u ON f.user_id = u.user_id
            WHERE f.college_id = p_college_id
              AND f.status = 'ACTIVE'
              AND f.is_deleted = 0
              AND NOT EXISTS (
                  SELECT 1
                  FROM schedules s
                  WHERE s.college_id = p_college_id
                    AND UPPER(s.instructor_name) = UPPER(u.full_name)
                    AND s.day_of_week = p_day_of_week
                    AND s.is_deleted = 0
                    AND s.is_break = 0
                    AND s.start_time <= p_time
                    AND s.end_time > p_time
              )
            ORDER BY u.full_name;
        
        RETURN v_cursor;
    END get_free_faculty;

    -- Get Class Schedule
    FUNCTION get_class_schedule(
        p_college_id    IN RAW,
        p_class_code    IN VARCHAR2,
        p_day_of_week   IN NUMBER DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT schedule_id, class_code, subject_name, instructor_name,
                   room_code, day_of_week, start_time, end_time,
                   schedule_type, is_break, notes
            FROM schedules
            WHERE college_id = p_college_id
              AND class_code = p_class_code
              AND is_deleted = 0
              AND (p_day_of_week IS NULL OR day_of_week = p_day_of_week)
            ORDER BY day_of_week, start_time;
        
        RETURN v_cursor;
    END get_class_schedule;

    -- Get Faculty Schedule
    FUNCTION get_faculty_schedule(
        p_college_id    IN RAW,
        p_instructor    IN VARCHAR2,
        p_day_of_week   IN NUMBER DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT schedule_id, class_code, subject_name, instructor_name,
                   room_code, day_of_week, start_time, end_time,
                   schedule_type, notes
            FROM schedules
            WHERE college_id = p_college_id
              AND UPPER(instructor_name) LIKE UPPER('%' || p_instructor || '%')
              AND is_deleted = 0
              AND (p_day_of_week IS NULL OR day_of_week = p_day_of_week)
            ORDER BY day_of_week, start_time;
        
        RETURN v_cursor;
    END get_faculty_schedule;

    -- Get Room Schedule
    FUNCTION get_room_schedule(
        p_college_id    IN RAW,
        p_room_code     IN VARCHAR2,
        p_day_of_week   IN NUMBER DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT schedule_id, class_code, subject_name, instructor_name,
                   room_code, day_of_week, start_time, end_time,
                   schedule_type, notes
            FROM schedules
            WHERE college_id = p_college_id
              AND room_code = p_room_code
              AND is_deleted = 0
              AND (p_day_of_week IS NULL OR day_of_week = p_day_of_week)
            ORDER BY day_of_week, start_time;
        
        RETURN v_cursor;
    END get_room_schedule;

    -- Check Schedule Conflicts
    FUNCTION check_schedule_conflicts(
        p_college_id    IN RAW,
        p_day_of_week   IN NUMBER,
        p_start_time    IN VARCHAR2,
        p_end_time      IN VARCHAR2,
        p_class_code    IN VARCHAR2 DEFAULT NULL,
        p_instructor    IN VARCHAR2 DEFAULT NULL,
        p_room_code     IN VARCHAR2 DEFAULT NULL,
        p_exclude_id    IN RAW DEFAULT NULL
    ) RETURN SYS_REFCURSOR IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT schedule_id, class_code, subject_name, instructor_name,
                   room_code, day_of_week, start_time, end_time,
                   CASE 
                       WHEN p_class_code IS NOT NULL AND class_code = p_class_code 
                            THEN 'CLASS_CONFLICT'
                       WHEN p_instructor IS NOT NULL AND UPPER(instructor_name) = UPPER(p_instructor) 
                            THEN 'FACULTY_CONFLICT'
                       WHEN p_room_code IS NOT NULL AND room_code = p_room_code 
                            THEN 'ROOM_CONFLICT'
                   END AS conflict_type
            FROM schedules
            WHERE college_id = p_college_id
              AND day_of_week = p_day_of_week
              AND is_deleted = 0
              AND is_break = 0
              AND (p_exclude_id IS NULL OR schedule_id != p_exclude_id)
              AND (
                  (start_time <= p_start_time AND end_time > p_start_time) OR
                  (start_time < p_end_time AND end_time >= p_end_time) OR
                  (start_time >= p_start_time AND end_time <= p_end_time)
              )
              AND (
                  (p_class_code IS NOT NULL AND class_code = p_class_code) OR
                  (p_instructor IS NOT NULL AND UPPER(instructor_name) = UPPER(p_instructor)) OR
                  (p_room_code IS NOT NULL AND room_code = p_room_code)
              )
            ORDER BY start_time;
        
        RETURN v_cursor;
    END check_schedule_conflicts;

END pkg_schedule_mgmt;
/

COMMIT;
