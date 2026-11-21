"""One-time script: creates all tables, functions, triggers, views and sample data
in the PostgreSQL database. Usage:  python setup_db.py "<DATABASE_PUBLIC_URL>"
"""
import os
import sys
import psycopg2

url = sys.argv[1] if len(sys.argv) > 1 else os.getenv("DATABASE_URL")
if not url:
    sys.exit('Database URL missing. Run:  python setup_db.py "postgresql://..."')

here = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(here, "postgres_setup.sql"), encoding="utf-8") as f:
    sql = f.read()

conn = psycopg2.connect(url, options="-c timezone=Asia/Kolkata")
try:
    cur = conn.cursor()
    cur.execute(sql)
    conn.commit()
    cur.execute("SELECT (SELECT COUNT(*) FROM hotel), (SELECT COUNT(*) FROM room), "
                "(SELECT COUNT(*) FROM reservation), (SELECT COUNT(*) FROM payment)")
    h, r, b, p = cur.fetchone()
    print(f"Done! hotels={h}, rooms={r}, reservations={b}, payments={p}")
except Exception as e:
    conn.rollback()
    print("ERROR:", e)
    sys.exit(1)
finally:
    conn.close()
