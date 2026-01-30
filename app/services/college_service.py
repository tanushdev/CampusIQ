"""
CampusIQ - College Service
Production service for college management with tenant isolation
Updated for PostgreSQL compatibility via SQLAlchemy
"""
from datetime import datetime
from typing import Optional, Dict, List, Any
from flask import current_app, g
from sqlalchemy import text
from .db_engine import get_db_engine
import uuid
import json


class CollegeService:
    """Service for college management with RBAC enforcement"""
    
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
    # SUPER ADMIN OPERATIONS
    # =========================================================================
    
    def get_stats(self) -> Dict:
        """Get aggregate stats for colleges (Super Admin only)"""
        user = self._get_user_context()
        if user['role'] != 'SUPER_ADMIN':
            return {'total_colleges': 0, 'pending_approval': 0}
            
        try:
            total = self._execute("SELECT COUNT(*) as cnt FROM colleges WHERE is_deleted = false")[0]['cnt']
            pending = self._execute("SELECT COUNT(*) as cnt FROM colleges WHERE status = 'PENDING' AND is_deleted = false")[0]['cnt']
            
            return {
                'total_colleges': total,
                'pending_approval': pending
            }
        except Exception as e:
            current_app.logger.error(f"Error getting stats: {e}")
            return {'total_colleges': 0, 'pending_approval': 0}

    def get_all_colleges(self, 
                         status_filter: Optional[str] = None,
                         page: int = 1, 
                         per_page: int = 20) -> Dict:
        """
        Get all colleges (Super Admin only)
        """
        user = self._get_user_context()
        
        if user['role'] != 'SUPER_ADMIN':
            return {'error': 'ACCESS_DENIED', 'message': 'Only Super Admin can view all colleges'}
        
        try:
            query = """
                SELECT college_id, college_name, college_code, college_logo_url,
                       email_domain, status, created_at, updated_at
                FROM colleges
                WHERE is_deleted = false
            """
            params = {}
            
            if status_filter:
                query += " AND status = :status"
                params['status'] = status_filter
            
            query += " ORDER BY created_at DESC LIMIT :limit OFFSET :offset"
            params['limit'] = per_page
            params['offset'] = (page - 1) * per_page
            
            colleges = self._execute(query, params)
            
            # Get total count
            count_query = "SELECT COUNT(*) as cnt FROM colleges WHERE is_deleted = false"
            if status_filter:
                count_query += " AND status = :status"
                total = self._execute(count_query, {'status': status_filter} if status_filter else {})[0]['cnt']
            else:
                total = self._execute(count_query)[0]['cnt']
            
            return {
                'items': colleges,
                'total': total,
                'page': page,
                'per_page': per_page,
                'pages': (total + per_page - 1) // per_page
            }
            
        except Exception as e:
            current_app.logger.error(f"Error fetching colleges: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    def create_college(self, data: Dict) -> Dict:
        """
        Create new college (Super Admin only)
        """
        user = self._get_user_context()
        
        if user['role'] != 'SUPER_ADMIN':
            return {'error': 'ACCESS_DENIED', 'message': 'Only Super Admin can create colleges'}
        
        # Validate required fields
        required = ['college_name', 'email_domain', 'admin_email']
        for field in required:
            if not data.get(field):
                return {'error': 'VALIDATION', 'message': f'{field} is required'}
        
        admin_email = data['admin_email'].lower().strip()
        
        try:
            # Check for duplicate email domain
            check = self._execute(
                "SELECT COUNT(*) as cnt FROM email_domain_mapping WHERE domain = :domain AND is_active = true",
                {'domain': data['email_domain'].lower()}
            )
            if check[0]['cnt'] > 0:
                return {'error': 'DUPLICATE', 'message': 'Email domain already registered'}
            
            # Check if admin email already exists
            check = self._execute("SELECT COUNT(*) as cnt FROM users WHERE email = :email", {'email': admin_email})
            if check[0]['cnt'] > 0:
                return {'error': 'DUPLICATE', 'message': 'Admin email already registered as a user'}

            college_id = str(uuid.uuid4())
            
            # Create College
            self._execute("""
                INSERT INTO colleges (
                    college_id, college_name, college_code, email_domain,
                    website_url, address, city, state, phone,
                    status, created_by, created_at, updated_at
                ) VALUES (:cid, :name, :code, :domain, :web, :addr, :city, :state, :phone, 'PENDING', :uid, :ts, :ts)
            """, {
                'cid': college_id,
                'name': data['college_name'],
                'code': data.get('college_code'),
                'domain': data['email_domain'].lower(),
                'web': data.get('website_url'),
                'addr': data.get('address'),
                'city': data.get('city'),
                'state': data.get('state'),
                'phone': data.get('phone'),
                'uid': user['user_id'],
                'ts': datetime.utcnow()
            })
            
            # Create email domain mapping
            self._execute("""
                INSERT INTO email_domain_mapping (
                    mapping_id, college_id, domain, is_primary, is_active, created_at
                ) VALUES (:mid, :cid, :domain, true, true, :ts)
            """, {
                'mid': str(uuid.uuid4()),
                'cid': college_id,
                'domain': data['email_domain'].lower(),
                'ts': datetime.utcnow()
            })
            
            # Create College Admin User
            role_rows = self._execute("SELECT role_id FROM roles WHERE role_code = 'COLLEGE_ADMIN'")
            if not role_rows:
                raise Exception("COLLEGE_ADMIN role not found in database")
            
            admin_user_id = str(uuid.uuid4())
            self._execute("""
                INSERT INTO users (
                    user_id, email, full_name, role_id, college_id,
                    status, created_by, created_at, updated_at
                ) VALUES (:uid, :email, :name, :rid, :cid, 'ACTIVE', :creator, :ts, :ts)
            """, {
                'uid': admin_user_id,
                'email': admin_email,
                'name': f"{data['college_name']} Admin",
                'rid': role_rows[0]['role_id'],
                'cid': college_id,
                'creator': user['user_id'],
                'ts': datetime.utcnow()
            })

            # Log audit
            self._log_audit(
                college_id=college_id,
                action='CREATE',
                entity_type='college',
                entity_id=college_id,
                new_value=json.dumps(data),
                summary=f"Created college: {data['college_name']} with admin {admin_email}"
            )
            
            return {'success': True, 'college_id': college_id, 'admin_user_id': admin_user_id}
            
        except Exception as e:
            current_app.logger.error(f"Error creating college: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    def approve_college(self, college_id: str) -> Dict:
        """Approve a pending college (Super Admin only)"""
        user = self._get_user_context()
        
        if user['role'] != 'SUPER_ADMIN':
            return {'error': 'ACCESS_DENIED', 'message': 'Only Super Admin can approve colleges'}
        
        try:
            # Check current status
            rows = self._execute(
                "SELECT status, college_name FROM colleges WHERE college_id = :cid AND is_deleted = false",
                {'cid': college_id}
            )
            
            if not rows:
                return {'error': 'NOT_FOUND', 'message': 'College not found'}
            
            row = rows[0]
            if row['status'] == 'APPROVED':
                return {'error': 'INVALID_STATE', 'message': 'College is already approved'}
            
            self._execute("""
                UPDATE colleges
                SET status = 'APPROVED',
                    approved_by = :uid,
                    approved_at = :ts,
                    updated_by = :uid,
                    updated_at = :ts
                WHERE college_id = :cid
            """, {
                'uid': user['user_id'],
                'ts': datetime.utcnow(),
                'cid': college_id
            })
            
            self._log_audit(
                college_id=college_id,
                action='APPROVE',
                entity_type='college',
                entity_id=college_id,
                old_value=json.dumps({'status': row['status']}),
                new_value=json.dumps({'status': 'APPROVED'}),
                summary=f"Approved college: {row['college_name']}"
            )
            
            return {'success': True}
            
        except Exception as e:
            current_app.logger.error(f"Error approving college: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    def suspend_college(self, college_id: str, reason: str) -> Dict:
        """Suspend a college (Super Admin only)"""
        user = self._get_user_context()
        
        if user['role'] != 'SUPER_ADMIN':
            return {'error': 'ACCESS_DENIED', 'message': 'Only Super Admin can suspend colleges'}
        
        try:
            self._execute("""
                UPDATE colleges 
                SET status = 'SUSPENDED', updated_by = :uid, updated_at = :ts 
                WHERE college_id = :cid AND is_deleted = false
            """, {'uid': user['user_id'], 'ts': datetime.utcnow(), 'cid': college_id})
            
            self._log_audit(
                college_id=college_id,
                action='SUSPEND',
                entity_type='college',
                entity_id=college_id,
                summary=f"Suspended college: {college_id}. Reason: {reason}"
            )
            
            return {'success': True}
        except Exception as e:
            return {'error': 'DATABASE', 'message': str(e)}

    def delete_college(self, college_id: str) -> Dict:
        """Soft delete a college (Super Admin only)"""
        user = self._get_user_context()
        
        if user['role'] != 'SUPER_ADMIN':
            return {'error': 'ACCESS_DENIED', 'message': 'Only Super Admin can delete colleges'}
        
        try:
            # Check if college exists
            rows = self._execute("SELECT college_name FROM colleges WHERE college_id = :cid AND is_deleted = false", {'cid': college_id})
            if not rows:
                return {'error': 'NOT_FOUND', 'message': 'College not found'}

            # Soft delete college
            self._execute("""
                UPDATE colleges 
                SET is_deleted = true, status = 'DELETED', updated_by = :uid, updated_at = :ts 
                WHERE college_id = :cid
            """, {'uid': user['user_id'], 'ts': datetime.utcnow(), 'cid': college_id})
            
            # Soft delete associated users
            self._execute("""
                UPDATE users 
                SET is_deleted = true, updated_by = :uid, updated_at = :ts 
                WHERE college_id = :cid
            """, {'uid': user['user_id'], 'ts': datetime.utcnow(), 'cid': college_id})

            # Deactivate domain mappings
            self._execute("""
                UPDATE email_domain_mapping 
                SET is_active = false 
                WHERE college_id = :cid
            """, {'cid': college_id})

            self._log_audit(
                college_id=college_id,
                action='DELETE',
                entity_type='college',
                entity_id=college_id,
                summary=f"Soft deleted college: {rows[0]['college_name']}"
            )
            
            return {'success': True}
        except Exception as e:
            return {'error': 'DATABASE', 'message': str(e)}
    
    # =========================================================================
    # BRANDING OPERATIONS (Super Admin + College Admin)
    # =========================================================================
    
    def update_branding(self, college_id: str, data: Dict) -> Dict:
        """
        Update college branding (name and logo)
        
        Access Control (DB-layer enforced):
        - Super Admin: Can update ANY college
        - College Admin: Can ONLY update their OWN college
        - Faculty/Staff: NO access (returns error)
        """
        user = self._get_user_context()
        
        # SECURITY: Faculty/Staff cannot update branding
        if user['role'] in ('FACULTY', 'STAFF', 'STUDENT'):
            self._log_audit(
                college_id=college_id,
                action='SECURITY_VIOLATION',
                entity_type='college_branding',
                entity_id=college_id,
                summary=f"Unauthorized branding update attempt by {user['role']}"
            )
            return {'error': 'ACCESS_DENIED', 'message': 'You do not have permission to update branding'}
        
        # SECURITY: College Admin can only update their own college
        if user['role'] == 'COLLEGE_ADMIN':
            if user['college_id'] != college_id:
                self._log_audit(
                    college_id=college_id,
                    action='CROSS_TENANT_VIOLATION',
                    entity_type='college_branding',
                    entity_id=college_id,
                    summary=f"Cross-tenant branding update attempt"
                )
                return {'error': 'ACCESS_DENIED', 'message': 'You can only update your own college branding'}
        
        try:
            # Get current values for audit
            rows = self._execute(
                "SELECT college_name, college_logo_url FROM colleges WHERE college_id = :cid AND is_deleted = false",
                {'cid': college_id}
            )
            
            if not rows:
                return {'error': 'NOT_FOUND', 'message': 'College not found'}
            
            row = rows[0]
            old_name = row['college_name']
            old_logo = row['college_logo_url']
            
            # Validate inputs
            new_name = data.get('college_name')
            new_logo = data.get('college_logo_url')
            
            if new_name and len(new_name.strip()) < 3:
                return {'error': 'VALIDATION', 'message': 'College name must be at least 3 characters'}
            
            if new_logo and not (new_logo.startswith('http://') or new_logo.startswith('https://')):
                return {'error': 'VALIDATION', 'message': 'Logo URL must start with http:// or https://'}
            
            # Update branding
            self._execute("""
                UPDATE colleges
                SET college_name = COALESCE(:name, college_name),
                    college_logo_url = COALESCE(:logo, college_logo_url),
                    updated_by = :uid,
                    updated_at = :ts
                WHERE college_id = :cid AND is_deleted = false
            """, {
                'name': new_name,
                'logo': new_logo,
                'uid': user['user_id'],
                'ts': datetime.utcnow(),
                'cid': college_id
            })
            
            self._log_audit(
                college_id=college_id,
                action='UPDATE_BRANDING',
                entity_type='college',
                entity_id=college_id,
                old_value=json.dumps({'name': old_name, 'logo': old_logo}),
                new_value=json.dumps({'name': new_name or old_name, 'logo': new_logo or old_logo}),
                summary=f"Branding updated by {user['role']}"
            )
            
            return {'success': True}
            
        except Exception as e:
            current_app.logger.error(f"Error updating branding: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    def get_college_branding(self, college_id: str) -> Dict:
        """
        Get college branding (read-only, all roles can access their own college)
        """
        user = self._get_user_context()
        
        # Non-super admins can only view their own college
        if user['role'] != 'SUPER_ADMIN' and user['college_id'] != college_id:
            return {'error': 'ACCESS_DENIED', 'message': 'You can only view your own college'}
        
        try:
            rows = self._execute("""
                SELECT college_id, college_name, college_code, college_logo_url,
                       website_url, status
                FROM colleges
                WHERE college_id = :cid AND is_deleted = false
            """, {'cid': college_id})
            
            if not rows:
                return {'error': 'NOT_FOUND', 'message': 'College not found'}
            
            row = rows[0]
            
            # Determine if user can edit
            can_edit = user['role'] == 'SUPER_ADMIN' or (
                user['role'] == 'COLLEGE_ADMIN' and user['college_id'] == college_id
            )
            
            return {
                'college_id': row['college_id'],
                'college_name': row['college_name'],
                'college_code': row['college_code'],
                'college_logo_url': row['college_logo_url'],
                'website_url': row['website_url'],
                'status': row['status'],
                'can_edit': can_edit
            }
            
        except Exception as e:
            current_app.logger.error(f"Error fetching branding: {e}")
            return {'error': 'DATABASE', 'message': str(e)}
    
    def get_college_by_domain(self, email_domain: str) -> Optional[Dict]:
        """Get college by email domain (for login auto-detection)"""
        try:
            rows = self._execute("""
                SELECT c.college_id, c.college_name, c.college_code, 
                       c.college_logo_url, c.status
                FROM colleges c
                JOIN email_domain_mapping edm ON c.college_id = edm.college_id
                WHERE edm.domain = :domain AND edm.is_active = true AND c.is_deleted = false
            """, {'domain': email_domain.lower()})
            
            return rows[0] if rows else None
            
        except:
            return None
    
    # =========================================================================
    # HELPER METHODS
    # =========================================================================
    
    def _log_audit(self, college_id: str, action: str, entity_type: str,
                   entity_id: str, old_value: str = None, new_value: str = None,
                   summary: str = None):
        """Log audit event"""
        user = self._get_user_context()
        
        try:
            self._execute("""
                INSERT INTO audit_logs (
                    log_id, college_id, user_id, user_role, action_type,
                    entity_type, entity_id, old_value, new_value,
                    change_summary, created_at
                ) VALUES (:lid, :cid, :uid, :role, :action, :etype, :eid, :old, :new, :summary, :ts)
            """, {
                'lid': str(uuid.uuid4()),
                'cid': college_id,
                'uid': user.get('user_id'),
                'role': user.get('role'),
                'action': action,
                'etype': entity_type,
                'eid': entity_id,
                'old': old_value,
                'new': new_value,
                'summary': summary,
                'ts': datetime.utcnow()
            })
        except Exception:
            # Never fail on audit logging
            pass
