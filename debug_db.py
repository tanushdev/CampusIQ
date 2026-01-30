from app.services.db_engine import get_db_engine
from sqlalchemy import text
from flask import Flask
import os

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL')

with app.app_context():
    engine = get_db_engine()
    with engine.connect() as conn:
        print("--- ROLES ---")
        res = conn.execute(text("SELECT role_id, role_name, role_code FROM roles"))
        for row in res:
            print(row)
        
        print("\n--- RECENT USERS ---")
        res = conn.execute(text("SELECT email, role_id, college_id FROM users ORDER BY created_at DESC LIMIT 5"))
        for row in res:
            print(row)
