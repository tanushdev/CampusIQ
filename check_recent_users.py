from dotenv import load_dotenv
import os
import sys
from flask import Flask
from sqlalchemy import text
load_dotenv()

# Add current directory to path so we can import app
sys.path.append(os.getcwd())
from app.services.db_engine import get_db_engine

app = Flask(__name__)
# Mock config
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('SQLALCHEMY_DATABASE_URI') or os.environ.get('DATABASE_URL')
app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {}

with app.app_context():
    engine = get_db_engine()
    with engine.connect() as conn:
        print("--- RECENT USERS ---")
        res = conn.execute(text("SELECT user_id, email, google_id, role_id, college_id, created_at FROM users ORDER BY created_at DESC LIMIT 10"))
        for row in res:
            user_dict = dict(row._mapping)
            print(f"User: {user_dict['email']} | ID: {user_dict['user_id']} | GID: {user_dict['google_id']}")
            
            # Check role
            r_res = conn.execute(text("SELECT role_code FROM roles WHERE role_id = :rid"), {'rid': user_dict['role_id']})
            role = r_res.fetchone()
            print(f"  Role: {role[0] if role else 'MISSING'}")
            
            # Check college
            if user_dict['college_id']:
                c_res = conn.execute(text("SELECT college_name, status FROM colleges WHERE college_id = :cid"), {'cid': user_dict['college_id']})
                college = c_res.fetchone()
                print(f"  College: {college[0] if college else 'MISSING'} ({college[1] if college else 'N/A'})")
            print("-" * 30)
