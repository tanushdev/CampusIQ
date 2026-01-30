"""
CampusIQ - Configuration Management
Environment-based configuration for production, development, testing
"""
import os
from datetime import timedelta
from sqlalchemy.pool import NullPool

class Config:
    """Base configuration"""
    # App
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'campusiq-super-secret-key-change-in-production'
    APP_NAME = 'CampusIQ'
    VERSION = '1.0.0'
    
    # Database - Default to Postgres if URL provided, else Oracle/SQLite
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL')
    if SQLALCHEMY_DATABASE_URI and SQLALCHEMY_DATABASE_URI.startswith('postgres://'):
        SQLALCHEMY_DATABASE_URI = SQLALCHEMY_DATABASE_URI.replace('postgres://', 'postgresql://', 1)
        
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_POOL_SIZE = 5
    SQLALCHEMY_MAX_OVERFLOW = 10
    
    # JWT Configuration
    JWT_SECRET_KEY = os.environ.get('JWT_SECRET_KEY') or SECRET_KEY
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=1)
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(days=30)
    JWT_TOKEN_LOCATION = ['headers']
    JWT_HEADER_NAME = 'Authorization'
    JWT_HEADER_TYPE = 'Bearer'
    
    # Google OAuth
    GOOGLE_CLIENT_ID = os.environ.get('GOOGLE_CLIENT_ID', '')
    GOOGLE_CLIENT_SECRET = os.environ.get('GOOGLE_CLIENT_SECRET', '')
    GOOGLE_DISCOVERY_URL = 'https://accounts.google.com/.well-known/openid-configuration'
    
    # CORS
    CORS_ORIGINS = os.environ.get('CORS_ORIGINS', 'http://localhost:3000,http://localhost:5173').split(',')
    
    # Rate Limiting
    RATELIMIT_ENABLED = True
    RATELIMIT_STORAGE_URL = os.environ.get('REDIS_URL', 'memory://')
    RATELIMIT_DEFAULT = "100 per minute"
    
    # Security
    SESSION_COOKIE_SECURE = True
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'
    
    # QnA Configuration
    QNA_MAX_QUERY_LENGTH = 500
    QNA_RESPONSE_CACHE_TTL = 300  # 5 minutes
    GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', '')
    GEMINI_MODEL = os.environ.get('GEMINI_MODEL', 'gemini-2.0-flash')
    
    # Audit
    AUDIT_ENABLED = True
    AUDIT_SENSITIVE_FIELDS = ['password', 'token', 'secret']

    # Access Control
    # Access Control
    SUPER_ADMIN_EMAILS = [e.strip() for e in os.environ.get('SUPER_ADMIN_EMAILS', '').split(',') if e.strip()]


class DevelopmentConfig(Config):
    """Development configuration"""
    DEBUG = True
    SQLALCHEMY_ECHO = False
    DATABASE_PATH = 'campusiq.db'
    
    # Relaxed security for development
    SESSION_COOKIE_SECURE = False
    CORS_ORIGINS = ['http://localhost:3000', 'http://localhost:5173', 'http://127.0.0.1:5173']
    
    # Use SQLite for easy development
    USE_SQLITE = os.environ.get('USE_SQLITE', 'true').lower() == 'true'
    if USE_SQLITE and not Config.SQLALCHEMY_DATABASE_URI:
        SQLALCHEMY_DATABASE_URI = 'sqlite:///campusiq_dev.db'


class TestingConfig(Config):
    """Testing configuration"""
    TESTING = True
    DEBUG = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///:memory:'
    WTF_CSRF_ENABLED = False
    RATELIMIT_ENABLED = False


class ProductionConfig(Config):
    """Production configuration"""
    DEBUG = False
    SQLALCHEMY_ECHO = False
    
    # Stricter security for production
    SESSION_COOKIE_SECURE = True
    SESSION_COOKIE_SAMESITE = 'Lax'
    
    # Serverless/Cloud stability: Use NullPool to avoid stale connections
    SQLALCHEMY_ENGINE_OPTIONS = {
        'poolclass': NullPool,
        'pool_pre_ping': True,
    }
    
    # Ensure secrets are set
    @classmethod
    def init_app(cls, app):
        pass


class VercelConfig(ProductionConfig):
    """Vercel serverless configuration"""
    # Serverless-specific settings - NO connection pooling
    # This prevents "connection slots reserved" errors
    SQLALCHEMY_ENGINE_OPTIONS = {
        'poolclass': NullPool,  # Create connections on-demand, close immediately
    }


# Configuration dictionary
config = {
    'development': DevelopmentConfig,
    'testing': TestingConfig,
    'production': ProductionConfig,
    'vercel': VercelConfig,
    'default': DevelopmentConfig
}
