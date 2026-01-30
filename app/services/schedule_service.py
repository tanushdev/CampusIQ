"""
CampusIQ - Schedule Service
Production service for timetable management and CSV bulk imports
Compatible with both SQLite (Dev) and PostgreSQL (Vercel) via SQLAlchemy
"""
import csv
import io
import uuid
from datetime import datetime
from typing import Optional, Dict, List, Any
from flask import current_app, g
from sqlalchemy import text
from .db_engine import get_db_engine

class ScheduleService:
    """Service for schedule management with multi-tenant isolation"""
    
    def __init__(self, db_path: str = None):
        self.engine = get_db_engine()
    
    def _execute(self, sql: str, params: Dict = None) -> List[Dict]:
        """Execute SQL with named parameters safely"""
        if params is None:
            params = {}
        with self.engine.connect() as conn:
            # Use text() for safe parameterized queries
            result = conn.execute(text(sql), params)
            # For SELECT statements, return list of dicts
            if result.returns_rows:
                return [dict(row._mapping) for row in result]
            # For INSERT/UPDATE, commit is required
            conn.commit()
            return []

    def get_schedules(self, 
                      college_id: str,
                      day_of_week: Optional[int] = None,
                      class_code: Optional[str] = None,
                      faculty_name: Optional[str] = None,
                      room_code: Optional[str] = None,
                      page: int = 1,
                      per_page: int = 50) -> Dict:
        """Get schedules with filtering and pagination"""
        
        query = "SELECT * FROM schedules WHERE college_id = :college_id AND is_deleted = false"
        params = {'college_id': college_id}
        
        if day_of_week is not None:
            query += " AND day_of_week = :day_of_week"
            params['day_of_week'] = day_of_week
        
        if class_code:
            query += " AND class_code LIKE :class_code"
            params['class_code'] = f"%{class_code}%"
            
        if faculty_name:
            query += " AND instructor_name LIKE :faculty_name"
            params['faculty_name'] = f"%{faculty_name}%"
            
        if room_code:
            query += " AND room_code LIKE :room_code"
            params['room_code'] = f"%{room_code}%"
        
        # Count total
        with self.engine.connect() as conn:
            count_query = query.replace("SELECT *", "SELECT COUNT(*)")
            total = conn.execute(text(count_query), params).scalar()
        
        # Pagination
        query += " ORDER BY day_of_week, start_time LIMIT :limit OFFSET :offset"
        params['limit'] = per_page
        params['offset'] = (page - 1) * per_page
        
        items = self._execute(query, params)
        
        return {
            'items': items,
            'total': total,
            'page': page,
            'per_page': per_page,
            'pages': (total + per_page - 1) // per_page if per_page > 0 else 1
        }

    def get_relevant_schedules(self, college_id: str, day: int, time: str, limit: int = 4) -> List[Dict]:
        """Get current and upcoming classes"""
        time = self._normalize_time(time)
        
        # Ongoing
        ongoing = self._execute("""
            SELECT * FROM schedules 
            WHERE college_id = :cid AND day_of_week = :day AND is_deleted = false
            AND start_time <= :time AND end_time > :time
            ORDER BY start_time
        """, {'cid': college_id, 'day': day, 'time': time})
        
        # Upcoming
        needed = limit - len(ongoing)
        upcoming = []
        if needed > 0:
            upcoming = self._execute("""
                SELECT * FROM schedules 
                WHERE college_id = :cid AND day_of_week = :day AND is_deleted = false
                AND start_time >= :time
                ORDER BY start_time
                LIMIT :limit
            """, {'cid': college_id, 'day': day, 'time': time, 'limit': needed})
        
        return ongoing + upcoming

    def get_schedule_by_id(self, schedule_id: str, college_id: str) -> Optional[Dict]:
        """Get a specific schedule entry"""
        rows = self._execute(
            "SELECT * FROM schedules WHERE schedule_id = :sid AND college_id = :cid AND is_deleted = false",
            {'sid': schedule_id, 'cid': college_id}
        )
        return rows[0] if rows else None

    def create_schedule(self, college_id: str, data: Dict, created_by: str) -> Dict:
        """Create a single schedule entry"""
        schedule_id = str(uuid.uuid4())
        
        try:
            self._execute("""
                INSERT INTO schedules (
                    schedule_id, college_id, class_code, subject_name, 
                    instructor_name, room_code, day_of_week, 
                    start_time, end_time, created_by, created_at, updated_at
                ) VALUES (:sid, :cid, :class, :sub, :inst, :room, :day, :start, :end, :uid, :ts, :ts)
            """, {
                'sid': schedule_id,
                'cid': college_id,
                'class': data.get('class_code'),
                'sub': data.get('subject_name'),
                'inst': data.get('instructor_name'),
                'room': data.get('room_code'),
                'day': data.get('day_of_week'),
                'start': data.get('start_time'),
                'end': data.get('end_time'),
                'uid': created_by,
                'ts': datetime.utcnow()
            })
            return {'success': True, 'schedule_id': schedule_id}
        except Exception as e:
            return {'error': 'DATABASE', 'message': str(e)}

    def delete_schedule(self, schedule_id: str, college_id: str, deleted_by: str):
        """Soft delete a schedule entry"""
        self._execute("""
            UPDATE schedules 
            SET is_deleted = true, updated_by = :uid, updated_at = :ts 
            WHERE schedule_id = :sid AND college_id = :cid
        """, {
            'uid': deleted_by,
            'ts': datetime.utcnow(),
            'sid': schedule_id,
            'cid': college_id
        })

    def check_conflicts(self, 
                        college_id: str, 
                        day_of_week: int, 
                        start_time: str, 
                        end_time: str,
                        class_code: Optional[str] = None,
                        instructor_name: Optional[str] = None,
                        room_code: Optional[str] = None,
                        exclude_id: Optional[str] = None) -> List[Dict]:
        """Check for scheduling conflicts"""
        
        query = """
            SELECT * FROM schedules 
            WHERE college_id = :cid AND day_of_week = :day AND is_deleted = false
            AND (start_time < :end AND end_time > :start)
        """
        params = {
            'cid': college_id, 'day': day_of_week, 
            'end': end_time, 'start': start_time
        }
        
        if exclude_id:
            query += " AND schedule_id != :exclude"
            params['exclude'] = exclude_id
        
        overlaps = self._execute(query, params)
        conflicts = []
        
        for o in overlaps:
            if class_code and o['class_code'] == class_code:
                conflicts.append({'type': 'CLASS_CONFLICT', 'message': f"Class {class_code} is busy", 'entry': o})
            if instructor_name and o['instructor_name'] == instructor_name:
                conflicts.append({'type': 'FACULTY_CONFLICT', 'message': f"Instructor {instructor_name} is busy", 'entry': o})
            if room_code and o['room_code'] == room_code:
                conflicts.append({'type': 'ROOM_CONFLICT', 'message': f"Room {room_code} is busy", 'entry': o})
        
        return conflicts

    def import_from_csv(self, file_storage, college_id: str, imported_by: str) -> Dict:
        """Bulk import schedules from CSV file"""
        try:
            raw_data = file_storage.stream.read()
            try:
                content = raw_data.decode("utf-8-sig")
            except UnicodeDecodeError:
                content = raw_data.decode("latin-1")
                
            delimiter = ','
            if '\t' in content and content.count('\t') > content.count(','): delimiter = '\t'
            elif ';' in content and content.count(';') > content.count(','): delimiter = ';'
                
            stream = io.StringIO(content, newline=None)
            reader = csv.DictReader(stream, delimiter=delimiter)
        except Exception as e:
            return {'imported': 0, 'skipped': 0, 'errors': [f"File read error: {str(e)}"]}
            
        imported = 0
        skipped = 0
        errors = []
        
        # Batch insert would be better but keeping it simple for now
        for row_idx, row in enumerate(reader):
            try:
                # Normalize keys: lower, strip, replace space with underscore, remove BOM artifacts
                data = {}
                for k, v in row.items():
                    clean_key = k.lower().strip().replace(' ', '_').replace('\ufeff', '')
                    data[clean_key] = v
                
                day_val = data.get('day') or data.get('weekday') or data.get('day_of_week')
                day = self._parse_day(day_val)
                
                start = data.get('start_time') or data.get('start') or data.get('from')
                end = data.get('end_time') or data.get('end') or data.get('to')
                
                # Check for "9:00 - 10:00" format
                time_val = data.get('time') or data.get('slot')
                if time_val and not (start and end):
                    if '-' in time_val: start, end = time_val.split('-')[:2]
                    elif ' to ' in time_val.lower(): start, end = time_val.lower().split(' to ')[:2]

                class_code = data.get('class_code') or data.get('class') or data.get('batch')
                
                if day is None or not start or not end or not class_code:
                    skipped += 1; continue

                self.create_schedule(college_id, {
                    'class_code': class_code,
                    'subject_name': data.get('subject_name') or data.get('subject'),
                    'instructor_name': data.get('instructor_name') or data.get('faculty'),
                    'room_code': data.get('room_code') or data.get('room'),
                    'day_of_week': day,
                    'start_time': self._normalize_time(start),
                    'end_time': self._normalize_time(end)
                }, imported_by)
                imported += 1
                
            except Exception as e:
                errors.append(f"Row {row_idx + 1}: {str(e)}")
                skipped += 1
        
        return {'imported': imported, 'skipped': skipped, 'errors': errors}

    def _normalize_time(self, time_str: str) -> str:
        """Standardize time to 24h HH:MM format"""
        if not time_str: return "00:00"
        t = time_str.upper().strip().replace('AM', '').replace('PM', '').strip()
        is_pm = 'PM' in time_str.upper()
        
        try:
            if ':' in t: h, m = map(int, t.split(':')[:2])
            else: h, m = int(t), 0
                
            if is_pm and h < 12: h += 12
            if not is_pm and h == 12 and 'AM' in time_str.upper(): h = 0
            
            return f"{h:02d}:{m:02d}"
        except: return time_str

    def _parse_day(self, day_str: Optional[str]) -> Optional[int]:
        """Convert string day to index (0=Monday)"""
        if not day_str: return None
        d = day_str.lower().strip()
        if 'sun' in d: return 6
        if 'mon' in d: return 0
        if 'tue' in d: return 1
        if 'wed' in d: return 2
        if 'thu' in d: return 3
        if 'fri' in d: return 4
        if 'sat' in d: return 5
        return None

    def get_free_rooms(self, college_id: str, day: int, time: str) -> List[str]:
        """Get list of rooms NOT in use safely"""
        all_rooms = self._execute("SELECT room_code FROM rooms WHERE college_id = :cid AND is_deleted = false", {'cid': college_id})
        all_codes = {r['room_code'] for r in all_rooms}
        
        busy = self._execute("""
            SELECT DISTINCT room_code FROM schedules 
            WHERE college_id = :cid AND day_of_week = :day AND is_deleted = false
            AND (start_time <= :time AND end_time > :time)
        """, {'cid': college_id, 'day': day, 'time': time})
        busy_codes = {r['room_code'] for r in busy}
        
        return list(all_codes - busy_codes)

    def get_free_faculty(self, college_id: str, day: int, time: str) -> List[str]:
        """Get list of faculty NOT in use safely"""
        all_fac = self._execute("SELECT DISTINCT instructor_name FROM schedules WHERE college_id = :cid AND is_deleted = false", {'cid': college_id})
        all_names = {r['instructor_name'] for r in all_fac if r['instructor_name']}
        
        busy = self._execute("""
            SELECT DISTINCT instructor_name FROM schedules 
            WHERE college_id = :cid AND day_of_week = :day AND is_deleted = false
            AND (start_time <= :time AND end_time > :time)
        """, {'cid': college_id, 'day': day, 'time': time})
        busy_names = {r['instructor_name'] for r in busy}
        
        return list(all_names - busy_names)
