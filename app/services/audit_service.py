"""
CampusIQ - Audit Service
Comprehensive audit logging for security and compliance
Updated for PostgreSQL compatibility
"""
import json
import uuid
from datetime import datetime
from typing import Optional, Dict, List, Any
from flask import current_app, g, request
from sqlalchemy import text
from .db_engine import get_db_engine

class AuditService:
    """Service for audit logging and security trail"""
    
    ACTION_LOGIN = 'LOGIN'
    ACTION_LOGOUT = 'LOGOUT'
    ACTION_LOGIN_FAILED = 'LOGIN_FAILED'
    ACTION_SECURITY_VIOLATION = 'SECURITY_VIOLATION'
    
    SEVERITY_INFO = 'INFO'
    SEVERITY_WARNING = 'WARNING'
    
    def __init__(self, db_path: str = None):
        self.engine = get_db_engine()
    
    def _execute(self, sql: str, params: Dict = None):
        if params is None: params = {}
        try:
            with self.engine.connect() as conn:
                conn.execute(text(sql), params)
                conn.commit()
        except Exception as e:
            current_app.logger.error(f"Audit Log Failed: {e}")

    def _get_request_info(self) -> Dict:
        try:
            return {
                'ip': request.remote_addr or request.headers.get('X-Forwarded-For', ''),
                'ua': request.headers.get('User-Agent', '')[:200],
                'path': request.path,
                'method': request.method
            }
        except:
            return {'ip': None, 'ua': None, 'path': None, 'method': None}

    def log(self, action_type, entity_type, entity_id=None, entity_name=None, 
            college_id=None, old_value=None, new_value=None, change_summary=None, 
            severity='INFO', user_id=None, user_email=None):
        
        user = getattr(g, 'current_user', {})
        req = self._get_request_info()
        
        # Serialize JSON
        if old_value and not isinstance(old_value, str): old_value = json.dumps(old_value, default=str)
        if new_value and not isinstance(new_value, str): new_value = json.dumps(new_value, default=str)
        
        self._execute("""
            INSERT INTO audit_logs (
                log_id, college_id, user_id, user_email, user_role,
                action_type, entity_type, entity_id, entity_name,
                old_value, new_value, change_summary,
                ip_address, user_agent, request_path, request_method,
                severity, created_at
            ) VALUES (:lid, :cid, :uid, :email, :role, :act, :ent_t, :ent_id, :ent_n, 
                      :old, :new, :summary, :ip, :ua, :path, :method, :sev, :ts)
        """, {
            'lid': str(uuid.uuid4()),
            'cid': college_id or user.get('college_id'),
            'uid': user_id or user.get('user_id'),
            'email': user_email or user.get('email'),
            'role': user.get('role'),
            'act': action_type,
            'ent_t': entity_type,
            'ent_id': entity_id,
            'ent_n': entity_name,
            'old': old_value,
            'new': new_value,
            'summary': change_summary,
            'ip': req['ip'],
            'ua': req['ua'],
            'path': req['path'],
            'method': req['method'],
            'sev': severity,
            'ts': datetime.utcnow()
        })
        return True

    def log_login(self, user_id, user_email, college_id=None, success=True):
        return self.log(
            action_type=self.ACTION_LOGIN if success else self.ACTION_LOGIN_FAILED,
            entity_type='session',
            entity_id=user_id,
            entity_name=user_email,
            college_id=college_id,
            change_summary='Login successful' if success else 'Login failed',
            severity='INFO' if success else 'WARNING',
            user_id=user_id,
            user_email=user_email
        )


# Singleton instance for easy import
_audit_service = None

def get_audit_service() -> AuditService:
    """Get shared audit service instance"""
    global _audit_service
    if _audit_service is None:
        _audit_service = AuditService()
    return _audit_service
