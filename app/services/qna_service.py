"""
CampusIQ - QnA Service
RAG-based Question Answering System for Timetables
Optimized for Vercel Serverless (No Spacy, No Pandas, No Numpy)
"""
import re
from datetime import datetime
from flask import current_app
import google.generativeai as genai
from sqlalchemy import create_engine, text

class QnAService:
    def __init__(self, db_path: str = None):
        self.uri = current_app.config.get('SQLALCHEMY_DATABASE_URI')
        # Lazy initialization of engine to avoid connection overhead on import
        self.engine = None

    def _get_engine(self):
        if not self.engine:
            self.engine = create_engine(self.uri)
        return self.engine

    def _execute(self, sql: str, params: dict) -> list[dict]:
        with self._get_engine().connect() as conn:
            result = conn.execute(text(sql), params)
            if result.returns_rows:
                return [dict(row._mapping) for row in result]
            return []

    def _get_timetable_data(self, college_id):
        """Fetch all timetable entries for the college as list of dicts"""
        try:
            rows = self._execute("""
                SELECT day_of_week, start_time, end_time, class_code, 
                       subject_name, instructor_name, room_code
                FROM schedules 
                WHERE college_id = :cid AND is_deleted = false
            """, {'cid': college_id})
            
            days = {0: 'Monday', 1: 'Tuesday', 2: 'Wednesday', 3: 'Thursday', 4: 'Friday', 5: 'Saturday', 6: 'Sunday'}
            for r in rows:
                r['day_name'] = days.get(r['day_of_week'], 'Unknown')
            return rows
        except Exception as e:
            current_app.logger.error(f"Error loading timetable: {e}")
            return []

    def _get_user_name(self, user_id):
        try:
            rows = self._execute("SELECT full_name FROM users WHERE user_id = :uid", {'uid': user_id})
            return rows[0]['full_name'] if rows else None
        except: return None

    def _understand_query(self, query):
        """Regex-based NLU"""
        query_lower = query.lower().strip()
        entities = {
            'days': [],
            'rooms': [],
            'classes': [],
            'time': None,
            'relative_time': None,
            'personal': any(w in query_lower for w in ['my', 'i teach', 'me']),
            'intent': 'academic_search'
        }

        if any(w in query_lower for w in ['free room', 'empty room', 'vacant']):
            entities['intent'] = 'free_rooms'

        # Temporal
        if 'next' in query_lower: entities['relative_time'] = 'next'
        elif any(w in query_lower for w in ['now', 'current']): entities['relative_time'] = 'current'
        elif 'tomorrow' in query_lower: entities['relative_time'] = 'tomorrow'
        
        # Time (e.g. 3:30 pm)
        time_match = re.search(r'(\d{1,2})[:.]?(\d{2})?\s?(am|pm)', query_lower)
        if time_match:
            h = int(time_match.group(1))
            m = int(time_match.group(2)) if time_match.group(2) else 0
            if time_match.group(3) == 'pm' and h < 12: h += 12
            if time_match.group(3) == 'am' and h == 12: h = 0
            entities['time'] = h * 60 + m

        # Days
        days_map = {'mon': 0, 'tue': 1, 'wed': 2, 'thu': 3, 'fri': 4, 'sat': 5, 'sun': 6}
        for d, idx in days_map.items():
            if d in query_lower: entities['days'].append(idx)
        
        # Rooms (A-101)
        entities['rooms'] = [r.upper() for r in re.findall(r'[a-z]-\d{3}[a-z]?', query_lower)]

        # Classes (SE IT)
        for year, branch in re.findall(r'\b(fe|se|ty|be)\s+(it|comp|ecs|extc|mech|civil)\b', query_lower):
            entities['classes'].append(f"{year.upper()} {branch.upper()}")

        return entities

    def _parse_time_min(self, t_str):
        try:
            t_str = str(t_str).upper().strip().replace('AM','').replace('PM','').strip()
            if ':' in t_str: h, m = map(int, t_str.split(':')[:2])
            else: h, m = int(t_str), 0
            # Simple heuristic
            if h < 7: h += 12 
            return h * 60 + m
        except: return 0

    def _semantic_filter(self, rows, query, entities, user_name=None):
        if not rows: return []
        
        now = datetime.now()
        target_day = now.weekday()
        if entities['relative_time'] == 'tomorrow': 
            target_day = (target_day + 1) % 7
        elif entities['days']: 
            target_day = entities['days'][0]
            
        now_min = now.hour * 60 + now.minute
        if entities['time']: now_min = entities['time']

        # Filter by day (unless it's a "my schedule" query without explicit day)
        filtered = rows
        is_personal = entities['personal'] or 'my' in query.lower()
        has_day = entities['days'] or entities['relative_time']
        
        if not (is_personal and not has_day):
            filtered = [r for r in rows if r['day_of_week'] == target_day]

        # Filter by User Name
        if is_personal and user_name:
            filtered = [r for r in filtered if user_name.split()[0].lower() in (r['instructor_name'] or '').lower()]
            if not filtered and is_personal: return []

        # Current/Next Logic
        if entities['relative_time'] == 'current':
            matches = []
            for r in filtered:
                s = self._parse_time_min(r['start_time'])
                e = self._parse_time_min(r['end_time'])
                if s <= now_min < e: matches.append(r)
            if matches: return matches
            
        elif entities['relative_time'] == 'next':
            upcoming = []
            for r in filtered:
                s = self._parse_time_min(r['start_time'])
                if s >= now_min: upcoming.append((s, r))
            upcoming.sort(key=lambda x: x[0])
            return [x[1] for x in upcoming[:3]]

        # Keyword Scoring (No Numpy)
        scored_results = []
        query_words = [w for w in query.lower().split() if len(w) > 3]
        
        for r in filtered:
            score = 0
            row_text = f"{r['class_code']} {r['subject_name']} {r['instructor_name']} {r['room_code']}".lower()
            
            if r['room_code'] in entities['rooms']: score += 20
            if any(c in r['class_code'].upper() for c in entities['classes']): score += 15
            for w in query_words:
                if w in row_text: score += 5
            
            if score > 0: scored_results.append((score, r))
            
        scored_results.sort(key=lambda x: x[0], reverse=True)
        return [x[1] for x in scored_results[:5]]

    def _generate_ai_response(self, query, results):
        api_key = current_app.config.get('GEMINI_API_KEY')
        if not api_key: return "API Key missing."
        
        try:
            genai.configure(api_key=api_key)
            model = genai.GenerativeModel(current_app.config.get('GEMINI_MODEL', 'gemini-1.5-flash'))
            
            context = "\n".join([f"- {r.get('day_name')} {r.get('start_time')}-{r.get('end_time')}: {r.get('subject_name')} in {r.get('room_code')}" for r in results]) or "No records found."
            
            prompt = f"""
            Context: {datetime.now().strftime('%A %H:%M')}
            Query: {query}
            DB Records:
            {context}
            
            Answer nicely in 2-3 lines. State facts only.
            """
            resp = model.generate_content(prompt)
            return resp.text.strip() if resp else "No response generated."
        except Exception as e:
            return f"AI Error: {e}"

    def _handle_free_rooms(self, college_id, entities):
        # reuse schedule service logic or simple SQL
        now = datetime.now()
        day = now.weekday()
        time_str = now.strftime('%H:%M')
        
        # Get all rooms
        all_rooms = self._execute("SELECT room_code FROM rooms WHERE college_id = :cid AND is_deleted = false", {'cid': college_id})
        all_codes = {r['room_code'] for r in all_rooms}
        
        # Get busy
        busy = self._execute("""
            SELECT DISTINCT room_code FROM schedules 
            WHERE college_id = :cid AND day_of_week = :day AND is_deleted = false
            AND (start_time <= :time AND end_time > :time)
        """, {'cid': college_id, 'day': day, 'time': time_str})
        busy_codes = {r['room_code'] for r in busy}
        
        free = sorted(list(all_codes - busy_codes))[:10]
        return [{'room_code': r, 'status': 'FREE'} for r in free]

    def process_query(self, query, college_id=None, user_id=None, user_role=None):
        entities = self._understand_query(query)
        user_name = self._get_user_name(user_id) if user_id else None
        
        if entities['intent'] == 'free_rooms':
            results = self._handle_free_rooms(college_id, entities)
        else:
            rows = self._get_timetable_data(college_id)
            results = self._semantic_filter(rows, query, entities, user_name)
            
        response = self._generate_ai_response(query, results)
        return {
            'intent': entities['intent'],
            'response': response,
            'results': results
        }
    
    # Stubs
    def get_user_history(self, **kwargs): return []
