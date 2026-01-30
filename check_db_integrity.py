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
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL') or os.environ.get('SQLALCHEMY_DATABASE_URI')
app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {}

with app.app_context():
    engine = get_db_engine()
    try:
        with engine.connect() as conn:
            print("--- DATABASE INTEGRITY CHECK ---")
            
            # 1. Check Roled
            try:
                res = conn.execute(text("SELECT COUNT(*) FROM roles"))
                count = res.fetchone()[0]
                print(f"Roles count: {count}")
                if count > 0:
                    res = conn.execute(text("SELECT role_code, role_id FROM roles"))
                    for row in res:
                        print(f"  - {row[0]}: {row[1]}")
            except Exception as e:
                print(f"Error checking roles: {e}")

            # 2. Check Colleges
            try:
                res = conn.execute(text("SELECT COUNT(*) FROM colleges"))
                count = res.fetchone()[0]
                print(f"Colleges count: {count}")
            except Exception as e:
                print(f"Error checking colleges: {e}")

            # 3. Check Users
            try:
                res = conn.execute(text("SELECT COUNT(*) FROM users"))
                count = res.fetchone()[0]
                print(f"Users count: {count}")
                if count > 0:
                    res = conn.execute(text("SELECT email, role_id, college_id FROM users LIMIT 5"))
                    for row in res:
                        print(f"  - {row[0]} | RoleID: {row[1]} | CollegeID: {row[2]}")
            except Exception as e:
                print(f"Error checking users: {e}")

    except Exception as e:
        print(f"CRITICAL: Connection failed: {e}")
