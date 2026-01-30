"""
CampusIQ - User Service
User management with role validation and tenant isolation
Updated for PostgreSQL compatibility via SQLAlchemy
"""
from datetime import datetime
from typing import Optional, Dict, List, Any
from flask import current_app, g
from sqlalchemy import text
from .db_engine import get_db_engine
import uuid
import json


class UserService:
    """Service for user management with RBAC enforcement"""
    
    def __init__(self, db_path: str = None):
        self.engine = get_db_engine()
    
    def _execute(self, sql: str, params: Dict = None) -> List[Dict]:
        """Execute SQL with named parameters safely"""
        if params is None:
            params = {}
        with self.engine.connect() as conn:
            result = conn.execute(text(sql), params)
            if result.returns_rows:
                return [dict(row._mapping) for row in result]
            conn.commit()
            return []
    
    def _get_user_context(self) -> Dict:
        """Get current user context from Flask g"""
        user = getattr(g, 'current_user', None)
        if not user:
            return {'role': None, 'user_id': None, 'college_id': None}
        return user
    
    # =========================================================================
    # USER PROFILE OPERATIONS
    # =========================================================================
    
    def get_user_profile(self, user_id: str) -> Dict:
        """
        Get user profile with role information
        """
        current_user = self._get_user_context()
        
        # Users can view their own profile
        # Admins can view users in their scope
        if current_user['role'] in ('FACULTY', 'STAFF', 'STUDENT'):
            if current_user['user_id'] != user_id:
                return {'error': 'ACCESS_DENIED', 'message': 'You can only view your own profile'}
        
        try:
            # Add explicit logging for debugging
            current_app.logger.info(f"[AUTH] Fetching profile for UID: {user_id}")
            
            # Use explicit UUID casting for PostgreSQL
            rows = self._execute("""
                SELECT u.user_id, u.email, u.full_name, u.first_name, u.last_name,
                       u.avatar_url, u.phone, u.status, u.email_verified,
                       u.last_login_at, u.college_id,
                       r.role_code, r.role_name,
                       c.college_name, c.college_logo_url
                FROM users u
                JOIN roles r ON u.role_id = r.role_id
                LEFT JOIN colleges c ON u.college_id = c.college_id
                WHERE u.user_id = :uid::uuid AND u.is_deleted = false
            """, {'uid': user_id})
            
            if not rows:
                current_app.logger.error(f"[AUTH] User record not found for UID: {user_id}")
                return {'error': 'NOT_FOUND', 'message': f'User {user_id} not found in database'}
            
            row = rows[0]
            
            # Tenant check for college admin
            if current_user['role'] == 'COLLEGE_ADMIN':
                if str(row['college_id']) != str(current_user['college_id']):
                    current_app.logger.warning(f"[AUTH] Tenant mismatch for {user_id}")
                    return {'error': 'ACCESS_DENIED', 'message': 'User not in your college scope'}
            
            return {
                'user_id': row['user_id'],
                'email': row['email'],
                'full_name': row['full_name'],
                'first_name': row['first_name'],
                'last_name': row['last_name'],
                'avatar_url': row['avatar_url'],
                'phone': row['phone'],
                'status': row['status'],
                'email_verified': bool(row['email_verified']),
                'last_login_at': row['last_login_at'],
                'role': {
                    'code': row['role_code'],
                    'name': row['role_name']
                },
                'college': {
                    'id': row['college_id'],
                    'name': row['college_name'],
                    'logo_url': row['college_logo_url']
                } if row['college_id'] else None
            }
        except Exception as e:
            current_app.logger.error(f"Error fetching profile: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    def update_profile(self, user_id: str, data: Dict) -> Dict:
        """
        Update user profile (limited fields)
        
        Users can only update: full_name, phone
        Admins can update more fields
        """
        current_user = self._get_user_context()
        
        # Users can only update their own profile
        if current_user['role'] in ('FACULTY', 'STAFF', 'STUDENT'):
            if current_user['user_id'] != user_id:
                return {'error': 'ACCESS_DENIED', 'message': 'You can only update your own profile'}
        
        try:
            # Determine allowed fields based on role
            allowed_fields = ['full_name', 'first_name', 'last_name', 'phone']
            
            if current_user['role'] in ('SUPER_ADMIN', 'COLLEGE_ADMIN'):
                allowed_fields.extend(['status'])
            
            # Filter data to allowed fields
            update_data = {k: v for k, v in data.items() if k in allowed_fields}
            
            if not update_data:
                return {'error': 'VALIDATION', 'message': 'No valid fields to update'}
            
            # Build update query dynamically
            set_parts = [f"{k} = :{k}" for k in update_data.keys()]
            set_clause = ', '.join(set_parts)
            
            params = {**update_data, 'ts': datetime.utcnow(), 'uid': current_user['user_id'], 'target_uid': user_id}
            
            self._execute(f"""
                UPDATE users
                SET {set_clause}, updated_at = :ts, updated_by = :uid
                WHERE user_id = :target_uid AND is_deleted = false
            """, params)
            
            # Log audit
            self._log_audit(
                action='UPDATE',
                entity_type='user',
                entity_id=user_id,
                new_value=json.dumps(update_data),
                summary='Profile updated'
            )
            
            return {'success': True}
        except Exception as e:
            current_app.logger.error(f"Error updating profile: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    def get_stats(self, college_id: str = None) -> Dict:
        """Get aggregate user stats (Admin only)"""
        current_user = self._get_user_context()
        if current_user['role'] not in ('SUPER_ADMIN', 'COLLEGE_ADMIN'):
            return {}
            
        try:
            if not college_id and current_user['role'] == 'SUPER_ADMIN':
                total = self._execute("SELECT COUNT(*) as cnt FROM users WHERE is_deleted = false")[0]['cnt']
                return {'total_users': total}
            
            # Specific college stats
            target_cid = college_id or current_user['college_id']
            stats = {}
            for role in ('FACULTY', 'STAFF', 'STUDENT'):
                count = self._execute("""
                    SELECT COUNT(*) as cnt FROM users u
                    JOIN roles r ON u.role_id = r.role_id
                    WHERE u.college_id = :cid AND r.role_code = :role AND u.is_deleted = false
                """, {'cid': target_cid, 'role': role})[0]['cnt']
                stats[f'total_{role.lower()}'] = count
            
            return stats
        except Exception as e:
            current_app.logger.error(f"Error getting stats: {e}")
            return {}

    # =========================================================================
    # ADMIN USER MANAGEMENT
    # =========================================================================
    
    def get_users(self, 
                  role_filter: str = None,
                  status_filter: str = None,
                  college_id_filter: str = None,
                  page: int = 1,
                  per_page: int = 20) -> Dict:
        """
        Get users list (Admin only, tenant-scoped)
        
        Super Admin: Can view ALL users OR filtered by college
        College Admin: Can view ONLY their college's users
        """
        current_user = self._get_user_context()
        
        if current_user['role'] not in ('SUPER_ADMIN', 'COLLEGE_ADMIN', 'FACULTY', 'STUDENT'):
            return {'error': 'ACCESS_DENIED', 'message': 'Admin access required'}
        
        # Determine fixed college filter
        fixed_college_id = None
        if current_user['role'] in ('COLLEGE_ADMIN', 'FACULTY', 'STUDENT'):
            fixed_college_id = current_user['college_id']
        elif current_user['role'] == 'SUPER_ADMIN' and college_id_filter:
            fixed_college_id = college_id_filter
        
        try:
            query = """
                SELECT u.user_id, u.email, u.full_name, u.status, u.last_login_at,
                       r.role_code, r.role_name, c.college_name
                FROM users u
                JOIN roles r ON u.role_id = r.role_id
                LEFT JOIN colleges c ON u.college_id = c.college_id
                WHERE u.is_deleted = false
            """
            params = {}
            
            # Tenant filter
            if fixed_college_id:
                query += " AND u.college_id = :cid"
                params['cid'] = fixed_college_id
            
            if role_filter:
                query += " AND r.role_code = :role"
                params['role'] = role_filter
            
            if status_filter:
                query += " AND u.status = :status"
                params['status'] = status_filter
            
            # Count total
            count_query = query.replace(
                "SELECT u.user_id, u.email, u.full_name, u.status, u.last_login_at,\n"
                "                       r.role_code, r.role_name, c.college_name",
                "SELECT COUNT(*) as cnt"
            )
            total = self._execute(count_query, params)[0]['cnt']
            
            # Add pagination
            query += " ORDER BY u.created_at DESC LIMIT :limit OFFSET :offset"
            params['limit'] = per_page
            params['offset'] = (page - 1) * per_page
            
            users = self._execute(query, params)
            
            return {
                'items': users,
                'total': total,
                'page': page,
                'per_page': per_page,
                'pages': (total + per_page - 1) // per_page
            }
        except Exception as e:
            current_app.logger.error(f"Error fetching users: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    def create_user(self, data: Dict) -> Dict:
        """
        Create new user (Admin only)
        
        College Admin can only create users in their college
        with roles lower than their own
        """
        current_user = self._get_user_context()
        
        if current_user['role'] not in ('SUPER_ADMIN', 'COLLEGE_ADMIN'):
            return {'error': 'ACCESS_DENIED', 'message': 'Admin access required'}
        
        # Validate required fields
        required = ['email', 'role_code']
        for field in required:
            if not data.get(field):
                return {'error': 'VALIDATION', 'message': f'{field} is required'}
        
        email = data['email'].lower().strip()
        
        try:
            # Check for existing user (including inactive/deleted)
            existing = self._execute(
                "SELECT user_id, status, is_deleted FROM users WHERE LOWER(email) = :email", 
                {'email': email}
            )
            
            if existing and not (existing[0]['is_deleted'] or existing[0]['status'] == 'INACTIVE'):
                return {'error': 'DUPLICATE', 'message': 'Email already registered and active'}
            
            # Get role_id
            role_rows = self._execute(
                "SELECT role_id, hierarchy_level FROM roles WHERE role_code = :role", 
                {'role': data['role_code']}
            )
            
            if not role_rows:
                return {'error': 'VALIDATION', 'message': 'Invalid role'}
            
            role_row = role_rows[0]
            
            # Role hierarchy check for College Admin
            if current_user['role'] == 'COLLEGE_ADMIN':
                admin_level = self._execute(
                    "SELECT hierarchy_level FROM roles WHERE role_code = 'COLLEGE_ADMIN'"
                )[0]['hierarchy_level']
                
                if role_row['hierarchy_level'] >= admin_level:
                    return {'error': 'ACCESS_DENIED', 'message': 'Cannot create user with equal or higher role'}
            
            # Determine college_id
            college_id = data.get('college_id')
            if current_user['role'] == 'COLLEGE_ADMIN':
                college_id = current_user['college_id']  # Force own college
            
            if existing:
                # Re-activate and update existing record
                user_id = existing[0]['user_id']
                self._execute("""
                    UPDATE users SET
                        full_name = :name,
                        role_id = :rid,
                        college_id = :cid,
                        status = 'ACTIVE',
                        is_deleted = false,
                        updated_by = :uid,
                        updated_at = :ts
                    WHERE user_id = :target_uid
                """, {
                    'name': data.get('full_name', ''),
                    'rid': role_row['role_id'],
                    'cid': college_id,
                    'uid': current_user['user_id'],
                    'ts': datetime.utcnow(),
                    'target_uid': user_id
                })
                summary = f"Re-activated user: {email}"
            else:
                # Create entirely new user
                user_id = str(uuid.uuid4())
                self._execute("""
                    INSERT INTO users (
                        user_id, email, full_name, role_id, college_id,
                        status, created_by, created_at, updated_at
                    ) VALUES (:uid, :email, :name, :rid, :cid, 'ACTIVE', :creator, :ts, :ts)
                """, {
                    'uid': user_id,
                    'email': email,
                    'name': data.get('full_name', ''),
                    'rid': role_row['role_id'],
                    'cid': college_id,
                    'creator': current_user['user_id'],
                    'ts': datetime.utcnow()
                })
                summary = f"Created user: {email}"
            
            self._log_audit(
                action='CREATE' if not existing else 'REACTIVATE',
                entity_type='user',
                entity_id=user_id,
                new_value=json.dumps({'email': email, 'role': data['role_code']}),
                summary=summary
            )
            
            return {'success': True, 'user_id': user_id, 'reactivated': bool(existing)}
        except Exception as e:
            current_app.logger.error(f"Error creating user: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    def update_user_role(self, user_id: str, new_role: str, new_college_id: str = None) -> Dict:
        """
        Update user role and optionally college (with role escalation prevention)
        """
        from ..middleware.rbac_middleware import validate_role_change
        
        current_user = self._get_user_context()
        
        if current_user['role'] not in ('SUPER_ADMIN', 'COLLEGE_ADMIN'):
            return {'error': 'ACCESS_DENIED', 'message': 'Admin access required'}
        
        try:
            # Get target user's current data
            target_rows = self._execute("""
                SELECT u.user_id, u.college_id, r.role_code
                FROM users u
                JOIN roles r ON u.role_id = r.role_id
                WHERE u.user_id = :uid AND u.is_deleted = false
            """, {'uid': user_id})
            
            if not target_rows:
                return {'error': 'NOT_FOUND', 'message': 'User not found'}
            
            target_user = target_rows[0]
            
            # Tenant check for College Admin
            if current_user['role'] == 'COLLEGE_ADMIN':
                if target_user['college_id'] != current_user['college_id']:
                    return {'error': 'ACCESS_DENIED', 'message': 'User not in your college'}
                # College admins cannot change college assignment, force to their own college
                new_college_id = current_user['college_id']
            
            # Role escalation check
            try:
                validate_role_change(current_user['role'], target_user['role_code'], new_role)
            except Exception as e:
                return {'error': 'ROLE_ESCALATION', 'message': str(e)}
            
            # Get new role_id
            new_role_rows = self._execute("SELECT role_id FROM roles WHERE role_code = :role", {'role': new_role})
            
            if not new_role_rows:
                return {'error': 'VALIDATION', 'message': 'Invalid role'}
            
            # Determine college_id to set
            college_to_set = target_user['college_id']
            if current_user['role'] == 'SUPER_ADMIN' and new_college_id is not None:
                college_to_set = new_college_id if new_college_id != "" else None

            self._execute("""
                UPDATE users
                SET role_id = :rid, college_id = :cid, updated_by = :uid, updated_at = :ts
                WHERE user_id = :target_uid
            """, {
                'rid': new_role_rows[0]['role_id'], 
                'cid': college_to_set, 
                'uid': current_user['user_id'], 
                'ts': datetime.utcnow(), 
                'target_uid': user_id
            })
            
            self._log_audit(
                action='UPDATE_USER_ADMIN',
                entity_type='user',
                entity_id=user_id,
                old_value=json.dumps({'role': target_user['role_code'], 'college': target_user['college_id']}),
                new_value=json.dumps({'role': new_role, 'college': college_to_set}),
                summary=f"Admin updated user role/college"
            )
            
            return {'success': True}
        except Exception as e:
            current_app.logger.error(f"Error updating user role: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    def deactivate_user(self, user_id: str) -> Dict:
        """Deactivate a user (soft delete)"""
        current_user = self._get_user_context()
        
        if current_user['role'] not in ('SUPER_ADMIN', 'COLLEGE_ADMIN'):
            return {'error': 'ACCESS_DENIED', 'message': 'Admin access required'}
        
        # Cannot deactivate yourself
        if current_user['user_id'] == user_id:
            return {'error': 'VALIDATION', 'message': 'Cannot deactivate yourself'}
        
        try:
            # Tenant check
            if current_user['role'] == 'COLLEGE_ADMIN':
                target = self._execute(
                    "SELECT college_id FROM users WHERE user_id = :uid",
                    {'uid': user_id}
                )
                if not target or target[0]['college_id'] != current_user['college_id']:
                    return {'error': 'ACCESS_DENIED', 'message': 'User not in your college'}
            
            self._execute("""
                UPDATE users
                SET status = 'INACTIVE', updated_by = :uid, updated_at = :ts
                WHERE user_id = :target_uid AND is_deleted = false
            """, {'uid': current_user['user_id'], 'ts': datetime.utcnow(), 'target_uid': user_id})
            
            self._log_audit(
                action='DEACTIVATE',
                entity_type='user',
                entity_id=user_id,
                summary='User deactivated'
            )
            
            return {'success': True}
        except Exception as e:
            current_app.logger.error(f"Error deactivating user: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    # =========================================================================
    # HELPER METHODS
    # =========================================================================
    
    def _log_audit(self, action: str, entity_type: str, entity_id: str,
                   old_value: str = None, new_value: str = None, summary: str = None):
        """Log audit event"""
        try:
            from .audit_service import get_audit_service
            audit = get_audit_service()
            audit.log(
                action_type=action,
                entity_type=entity_type,
                entity_id=entity_id,
                old_value=old_value,
                new_value=new_value,
                change_summary=summary
            )
        except Exception:
            pass  # Never fail on audit logging
