"""
Shared Database Engine Singleton
Prevents connection exhaustion by reusing a single engine across all services
"""
from flask import current_app
from sqlalchemy import create_engine

_engine = None

def get_db_engine():
    """Get or create the shared database engine"""
    global _engine
    
    if _engine is None:
        uri = current_app.config.get('SQLALCHEMY_DATABASE_URI')
        engine_options = current_app.config.get('SQLALCHEMY_ENGINE_OPTIONS', {})
        _engine = create_engine(uri, **engine_options)
    
    return _engine

def reset_engine():
    """Reset engine (for testing/cleanup)"""
    global _engine
    if _engine:
        _engine.dispose()
        _engine = None
