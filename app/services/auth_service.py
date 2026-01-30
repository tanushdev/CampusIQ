"""
CampusIQ - Authentication Service
Production Google OAuth 2.0 implementation with JWT sessions
Updated for PostgreSQL compatibility
"""
import requests
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from flask import current_app, g
import jwt
import hashlib
import uuid
import json
from sqlalchemy import text
from .db_engine import get_db_engine

class AuthService:
    """Service for authentication with Google OAuth 2.0"""
    
    GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'
    GOOGLE_USERINFO_URL = 'https://www.googleapis.com/oauth2/v3/userinfo'
    
    def __init__(self, db_path: str = None):
        # Use shared engine to prevent connection exhaustion
        self.engine = get_db_engine()
    
    def _execute(self, sql: str, params: Dict = None) -> list:
        if params is None: params = {}
        with self.engine.connect() as conn:
            result = conn.execute(text(sql), params)
            if result.returns_rows:
                return [dict(row._mapping) for row in result]
            conn.commit()
            return []

    def process_google_callback(self, auth_code: str, redirect_uri: str) -> Dict:
        """Process Google OAuth callback and create user session"""
        from ..utils.exceptions import CollegeNotApprovedException, UnauthorizedException
        
        # 1. Exchange code for tokens
        try:
            token_response = requests.post(self.GOOGLE_TOKEN_URL, data={
                'code': auth_code,
                'client_id': current_app.config['GOOGLE_CLIENT_ID'],
                'client_secret': current_app.config['GOOGLE_CLIENT_SECRET'],
                'redirect_uri': redirect_uri,
                'grant_type': 'authorization_code'
            }, timeout=10)
            
            if token_response.status_code != 200:
                raise UnauthorizedException(f"Google Token Error: {token_response.text}")
            
            tokens = token_response.json()
            google_access_token = tokens.get('access_token')
            
        except requests.RequestException:
            raise UnauthorizedException('Failed to connect to Google services')
        
        # 2. Get user info
        try:
            userinfo_response = requests.get(
                self.GOOGLE_USERINFO_URL,
                headers={'Authorization': f'Bearer {google_access_token}'},
                timeout=10
            )
            google_user = userinfo_response.json()
        except requests.RequestException:
            raise UnauthorizedException('Failed to get user info from Google')
        
        # 3. Extract data
        email = google_user.get('email', '').lower().strip()
        google_id = google_user.get('sub')
        full_name = google_user.get('name', '')
        avatar_url = google_user.get('picture', '')
        
        if not email: raise UnauthorizedException('Email not provided')
        
        # 4. Detect college
        email_domain = email.split('@')[1] if '@' in email else None
        college = self.get_college_by_domain(email_domain) if email_domain else None
        
        # 5. Find or create user - Normalized case-insensitive check
        user_rows = self._execute("SELECT * FROM users WHERE LOWER(email) = LOWER(:email) OR google_id = :gid", 
                                  {'email': email, 'gid': google_id})
        
        user_id = None
        user = None
        
        if user_rows:
            user = dict(user_rows[0])
            user_id = str(user['user_id'])
            
            if user.get('status') in ['INACTIVE', 'SUSPENDED']:
                raise UnauthorizedException('Account deactivated.')

            # Check if role_id is valid, if not, heal it
            role_check = self._execute("SELECT role_code FROM roles WHERE role_id = CAST(:rid AS UUID)", {'rid': str(user['role_id'])})
            if not role_check:
                current_app.logger.warning(f"User {email} has invalid role_id {user['role_id']}. Healing...")
                # Try to determine role again
                healed_role_id = self._determine_user_role(email, user_id=user_id)
                if healed_role_id:
                    self._execute("UPDATE users SET role_id = CAST(:rid AS UUID) WHERE user_id = CAST(:uid AS UUID)", 
                                  {'rid': str(healed_role_id), 'uid': str(user_id)})
                    user['role_id'] = healed_role_id

            # Check for Super Admin promotion (Env Var Override)
            super_admins = current_app.config.get('SUPER_ADMIN_EMAILS', [])
            if email in super_admins:
                sa_role_rows = self._execute("SELECT role_id FROM roles WHERE role_code = 'SUPER_ADMIN'")
                if sa_role_rows:
                    sa_role_id = sa_role_rows[0]['role_id']
                    if str(user['role_id']) != str(sa_role_id):
                        self._execute("UPDATE users SET role_id = CAST(:rid AS UUID) WHERE user_id = CAST(:uid AS UUID)", 
                                      {'rid': str(sa_role_id), 'uid': str(user_id)})
                        user['role_id'] = sa_role_id

            # Update login stats and link google_id
            self._execute("""
                UPDATE users 
                SET last_login_at = :ts, login_count = login_count + 1,
                    avatar_url = COALESCE(:avatar, avatar_url),
                    google_id = COALESCE(:gid, google_id)
                WHERE user_id = CAST(:uid AS UUID)
            """, {'ts': datetime.utcnow(), 'avatar': avatar_url, 'gid': google_id, 'uid': str(user_id)})
        else:
            # Auto-create super admin ONLY
            if email in current_app.config.get('SUPER_ADMIN_EMAILS', []):
                user_id = str(uuid.uuid4())
                role_id = self._determine_user_role(email)
                
                self._execute("""
                    INSERT INTO users (
                        user_id, email, google_id, full_name, avatar_url,
                        role_id, college_id, status, email_verified,
                        login_count, created_at, updated_at
                    ) VALUES (CAST(:uid AS UUID), :email, :gid, :name, :avatar, CAST(:rid AS UUID), CAST(:cid AS UUID), 'ACTIVE', true, 1, :ts, :ts)
                """, {
                    'uid': str(user_id), 'email': email, 'gid': google_id, 'name': full_name,
                    'avatar': avatar_url, 'rid': str(role_id), 'cid': str(college['college_id']) if college else None,
                    'ts': datetime.utcnow()
                })
                
                user = {'user_id': user_id, 'email': email, 'role_id': role_id, 'college_id': college['college_id'] if college else None}
            else:
                raise UnauthorizedException('Access Denied. Contact your administrator.')

        # 6. Get Role Code (Fresh check)
        role_rows = self._execute("SELECT role_code FROM roles WHERE role_id = :rid", {'rid': user['role_id']})
        role_code = role_rows[0]['role_code'] if role_rows else 'FACULTY'
        
        # 7. Generate Tokens with strict stringification
        access_token = self._create_access_token({
            'user_id': str(user_id), 
            'email': email, 
            'college_id': str(user.get('college_id') or ''), 
            'role': str(role_code)
        })
        refresh_token = self._create_refresh_token(str(user_id))
        self._store_refresh_token(str(user_id), refresh_token)

        return {
            'access_token': access_token,
            'refresh_token': refresh_token,
            'user': {
                'id': user_id, 'email': email, 'name': full_name,
                'avatar': avatar_url, 'role': role_code,
                'college_id': user.get('college_id'),
                'college_name': college.get('college_name') if college else None
            }
        }

    def _determine_user_role(self, email, user_id=None):
        if email in current_app.config.get('SUPER_ADMIN_EMAILS', []):
            rows = self._execute("SELECT role_id FROM roles WHERE role_code = 'SUPER_ADMIN'")
            return rows[0]['role_id'] if rows else None
        
        if user_id:
            # Join with roles to ensure the role_id actually exists
            rows = self._execute("""
                SELECT u.role_id FROM users u 
                JOIN roles r ON u.role_id = r.role_id 
                WHERE u.user_id = CAST(:uid AS UUID)
            """, {'uid': str(user_id)})
            if rows and rows[0]['role_id']:
                return rows[0]['role_id']
                
        # Default to FACULTY if email domain matches a college
        rows = self._execute("SELECT role_id FROM roles WHERE role_code = 'FACULTY'")
        return rows[0]['role_id'] if rows else None

    def get_college_by_domain(self, domain: str) -> Optional[Dict]:
        rows = self._execute("""
            SELECT c.college_id, c.college_name, c.college_code, c.status
            FROM colleges c
            JOIN email_domain_mapping edm ON c.college_id = edm.college_id
            WHERE edm.domain = :domain AND edm.is_active = true AND c.is_deleted = false
        """, {'domain': domain.lower()})
        return rows[0] if rows else None

    def _create_access_token(self, user_data: Dict) -> str:
        secret_key = current_app.config['JWT_SECRET_KEY']
        payload = {
            'sub': str(user_data['user_id']),
            'email': user_data['email'],
            'college_id': str(user_data.get('college_id') or ''),
            'role': user_data['role'],
            'iat': datetime.utcnow(),
            'exp': datetime.utcnow() + timedelta(hours=1)
        }
        return jwt.encode(payload, secret_key, algorithm='HS256')
    
    def _create_refresh_token(self, user_id: str) -> str:
        secret_key = current_app.config['JWT_SECRET_KEY']
        payload = {
            'sub': str(user_id), 'type': 'refresh',
            'iat': datetime.utcnow(),
            'exp': datetime.utcnow() + timedelta(days=30)
        }
        return jwt.encode(payload, secret_key, algorithm='HS256')
    
    def _store_refresh_token(self, user_id: str, token: str):
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        self._execute("""
            INSERT INTO refresh_tokens (token_id, user_id, token_hash, expires_at, created_at)
            VALUES (:tid, :uid, :hash, :exp, :ts)
        """, {
            'tid': str(uuid.uuid4()), 'uid': str(user_id), 'hash': token_hash,
            'exp': datetime.utcnow() + timedelta(days=30), 'ts': datetime.utcnow()
        })
