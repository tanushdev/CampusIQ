from dotenv import load_dotenv
load_dotenv()

app = Flask(__name__)
# Mock config
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('SQLALCHEMY_DATABASE_URI') or os.environ.get('DATABASE_URL')
app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {}

email_to_check = sys.argv[1] if len(sys.argv) > 1 else 'pceadmin@example.com'

with app.app_context():
    engine = get_db_engine()
    with engine.connect() as conn:
        print(f"Checking for user: {email_to_check}")
        res = conn.execute(text("SELECT user_id, email, google_id, role_id, college_id FROM users WHERE LOWER(email) = LOWER(:email)"), {'email': email_to_check})
        user = res.fetchone()
        if user:
            user_dict = dict(user._mapping)
            print("Found User:", user_dict)
            
            # Check role
            res = conn.execute(text("SELECT role_code FROM roles WHERE role_id = :rid"), {'rid': user_dict['role_id']})
            role = res.fetchone()
            print("Role:", dict(role._mapping) if role else "NOT FOUND")
            
            # Check college
            if user_dict['college_id']:
                res = conn.execute(text("SELECT college_name, status FROM colleges WHERE college_id = :cid"), {'cid': user_dict['college_id']})
                college = res.fetchone()
                print("College:", dict(college._mapping) if college else "NOT FOUND")
            else:
                print("College: NONE")
        else:
            print("User NOT FOUND")
