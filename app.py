"""
Hotel Chain Reservation & Revenue Management System - Flask backend.
Every route talks to Oracle directly. Business rules live in PL/SQL
(sp_book_room, sp_cancel_reservation ...), Flask only passes data.
"""
import re
from datetime import datetime, date
import oracledb
from flask import Flask, jsonify, request, session, render_template
import config

app = Flask(__name__)
app.secret_key = config.SECRET_KEY

# ------------------------- database helpers -----------------------------
def conn():
    return oracledb.connect(user=config.DB_USER, password=config.DB_PASSWORD, dsn=config.DB_DSN)

def clean(v):
    """Make Oracle values JSON friendly (dates -> text)."""
    return v.strftime('%Y-%m-%d') if isinstance(v, (datetime, date)) else v

def query(sql, p=None):
    """Run a SELECT, return list of dicts with lower-case keys."""
    with conn() as c:
        cur = c.cursor()
        cur.execute(sql, p or {})
        cols = [d[0].lower() for d in cur.description]
        return [{k: clean(v) for k, v in zip(cols, row)} for row in cur.fetchall()]

def execute(sql, p=None):
    """Run INSERT/UPDATE/DELETE and COMMIT."""
    with conn() as c:
        cur = c.cursor()
        cur.execute(sql, p or {})
        c.commit()

def plsql(block, p):
    """Run an anonymous PL/SQL block that calls a stored procedure."""
    with conn() as c:
        cur = c.cursor()
        cur.execute(block, p)
        return cur

def to_date(s):
    return datetime.strptime(s, '%Y-%m-%d')

@app.errorhandler(oracledb.DatabaseError)
def db_error(e):
    msg = str(e.args[0].message if e.args and hasattr(e.args[0], 'message') else e)
    if 'ORA-02292' in msg:
        msg = 'Cannot delete: related records exist (foreign key).'
    elif 'ORA-00001' in msg:
        msg = 'Duplicate value: a record with this unique value already exists.'
    else:
        m = re.search(r'ORA-200\d\d: (.*)', msg)
        msg = m.group(1).split('\n')[0] if m else msg.split('\n')[0]
    return jsonify(error=msg), 400

# ------------------------------ login -----------------------------------
@app.before_request
def require_login():
    open_paths = ('/', '/api/login', '/api/me')
    if request.path.startswith('/api/') and request.path not in open_paths and 'user' not in session:
        return jsonify(error='Please log in'), 401

@app.get('/')
def home():
    return render_template('index.html')

@app.post('/api/login')
def login():
    j = request.json
    if config.USERS.get(j.get('username')) == j.get('password'):
        session['user'] = j['username']
        return jsonify(user=j['username'])
    return jsonify(error='Invalid username or password'), 401

@app.post('/api/logout')
def logout():
    session.clear()
    return jsonify(ok=True)

@app.get('/api/me')
def me():
    return jsonify(user=session.get('user'))

# --------------------- generic CRUD (hotel/guest/room/service) -----------
def crud(name, table, pk, fields, list_sql):
    @app.get(f'/api/{name}', endpoint=f'list_{name}')
    def _list():
        return jsonify(query(list_sql))

    @app.post(f'/api/{name}', endpoint=f'add_{name}')
    def _add():
        j = request.json
        cols = ','.join(fields)
        binds = ','.join(':' + f for f in fields)
        execute(f'INSERT INTO {table}({cols}) VALUES({binds})', {f: j.get(f) or None for f in fields})
        return jsonify(ok=True)

    @app.put(f'/api/{name}/<int:i>', endpoint=f'upd_{name}')
    def _upd(i):
        j = request.json
        sets = ','.join(f'{f}=:{f}' for f in fields)
        execute(f'UPDATE {table} SET {sets} WHERE {pk}=:id', {**{f: j.get(f) or None for f in fields}, 'id': i})
        return jsonify(ok=True)

    @app.delete(f'/api/{name}/<int:i>', endpoint=f'del_{name}')
    def _del(i):
        execute(f'DELETE FROM {table} WHERE {pk}=:id', {'id': i})
        return jsonify(ok=True)

crud('hotels', 'hotel', 'hotel_id',
     ['hotel_name', 'city', 'state', 'address', 'phone', 'email', 'star_rating', 'status'],
     """SELECT h.*, (SELECT COUNT(*) FROM room r WHERE r.hotel_id=h.hotel_id) rooms,
               (SELECT COUNT(*) FROM room r WHERE r.hotel_id=h.hotel_id AND r.status='AVAILABLE') available
          FROM hotel h ORDER BY hotel_id""")
crud('guests', 'guest', 'guest_id',
     ['first_name', 'last_name', 'email', 'phone', 'address', 'id_proof_type', 'id_proof_no'],
     "SELECT * FROM guest ORDER BY guest_id")
crud('rooms', 'room', 'room_id',
     ['hotel_id', 'type_id', 'room_number', 'floor_no', 'price_per_night', 'status'],
     """SELECT r.*, h.hotel_name, t.type_name FROM room r
          JOIN hotel h ON h.hotel_id=r.hotel_id JOIN room_type t ON t.type_id=r.type_id
         ORDER BY r.hotel_id, r.room_number""")
crud('services', 'service', 'service_id',
     ['hotel_id', 'service_name', 'category', 'unit_price'],
     """SELECT s.*, h.hotel_name FROM service s JOIN hotel h ON h.hotel_id=s.hotel_id
         ORDER BY s.hotel_id, s.service_id""")
crud('room-types', 'room_type', 'type_id',
     ['type_name', 'description', 'base_price', 'max_occupancy'],
     "SELECT * FROM room_type ORDER BY type_id")

@app.get('/api/guests/<int:i>/history')
def guest_history(i):
    return jsonify(query("SELECT * FROM v_booking_summary WHERE guest_id=:i ORDER BY check_in_date DESC", {'i': i}))

# ----------------------------- availability ------------------------------
@app.get('/api/availability')
def availability():
    a = request.args
    p = {'h': a['hotel_id'], 'ci': to_date(a['check_in']), 'co': to_date(a['check_out'])}
    sql = """SELECT r.room_id, r.room_number, r.floor_no, r.price_per_night, r.status, t.type_name
               FROM room r JOIN room_type t ON t.type_id = r.type_id
              WHERE r.hotel_id = :h
                AND NOT (r.status = 'MAINTENANCE' AND :ci <= TRUNC(SYSDATE))
                AND NOT EXISTS (SELECT 1 FROM reservation_room x
                                 WHERE x.room_id = r.room_id AND x.status = 'ACTIVE'
                                   AND x.check_in_date < :co AND x.check_out_date > :ci)
              ORDER BY r.room_number"""
    return jsonify(query(sql, p))

# ----------------------------- reservations ------------------------------
@app.get('/api/reservations')
def reservations():
    return jsonify(query("SELECT * FROM v_booking_summary ORDER BY reservation_id DESC"))

@app.post('/api/reservations')
def book():
    j = request.json
    with conn() as c:
        cur = c.cursor()
        ref = cur.var(str)
        cur.execute("BEGIN sp_book_room(:g,:h,:r,:ci,:co,:n,:ref); END;",
                    dict(g=j['guest_id'], h=j['hotel_id'], r=j['room_id'], ci=to_date(j['check_in']),
                         co=to_date(j['check_out']), n=j.get('num_guests') or 1, ref=ref))
        return jsonify(booking_ref=ref.getvalue())

@app.post('/api/reservations/<int:i>/cancel')
def cancel(i):
    with conn() as c:
        cur = c.cursor()
        refund = cur.var(float)
        cur.execute("BEGIN sp_cancel_reservation(:i,'CASH',:rf); END;", dict(i=i, rf=refund))
        return jsonify(refund=refund.getvalue())

@app.post('/api/reservations/<int:i>/checkin')
def checkin(i):
    plsql("BEGIN sp_check_in(:i); END;", dict(i=i))
    return jsonify(ok=True)

@app.post('/api/reservations/<int:i>/checkout')
def checkout(i):
    plsql("BEGIN sp_check_out(:i); END;", dict(i=i))
    return jsonify(ok=True)

@app.get('/api/calendar')
def calendar():
    y, m = map(int, request.args['month'].split('-'))
    start = datetime(y, m, 1)
    end = datetime(y + (m == 12), m % 12 + 1, 1)
    return jsonify(query("""SELECT booking_ref, guest, hotel, check_in_date, check_out_date, status
                              FROM v_booking_summary
                             WHERE status <> 'CANCELLED' AND check_in_date < :e AND check_out_date > :s""",
                         {'s': start, 'e': end}))

# ------------------------------ services ---------------------------------
@app.get('/api/service-usage')
def usage_list():
    return jsonify(query("""SELECT u.usage_id, rs.booking_ref, s.service_name, s.category, u.quantity,
                                   u.unit_price, u.total_amount, u.usage_date
                              FROM service_usage u JOIN service s ON s.service_id=u.service_id
                              JOIN reservation rs ON rs.reservation_id=u.reservation_id
                             ORDER BY u.usage_id DESC"""))

@app.post('/api/service-usage')
def usage_add():
    j = request.json
    plsql("BEGIN sp_add_service(:r,:s,:q); END;",
          dict(r=j['reservation_id'], s=j['service_id'], q=j.get('quantity') or 1))
    return jsonify(ok=True)

# --------------------------- billing / payments --------------------------
@app.get('/api/invoices')
def invoices():
    return jsonify(query("""SELECT i.*, r.booking_ref, g.first_name||' '||g.last_name guest,
                   NVL((SELECT SUM(DECODE(payment_type,'REFUND',-amount,amount)) FROM payment p
                         WHERE p.invoice_id=i.invoice_id),0) paid
              FROM invoice i JOIN reservation r ON r.reservation_id=i.reservation_id
              JOIN guest g ON g.guest_id=r.guest_id ORDER BY i.invoice_id DESC"""))

@app.get('/api/payments')
def payments():
    return jsonify(query("""SELECT p.*, r.booking_ref FROM payment p
              JOIN invoice i ON i.invoice_id=p.invoice_id
              JOIN reservation r ON r.reservation_id=i.reservation_id ORDER BY p.payment_id DESC"""))

@app.post('/api/payments')
def pay():
    j = request.json
    plsql("BEGIN sp_record_payment(:i,:a,'PAYMENT',:m); END;",
          dict(i=j['invoice_id'], a=j['amount'], m=j['method']))
    return jsonify(ok=True)

# ----------------------------- housekeeping ------------------------------
@app.get('/api/housekeeping')
def hk_list():
    return jsonify(query("""SELECT k.*, r.room_number, h.hotel_name FROM housekeeping k
              JOIN room r ON r.room_id=k.room_id JOIN hotel h ON h.hotel_id=r.hotel_id
             ORDER BY DECODE(k.task_status,'CLEAN',2,1), k.task_id DESC"""))

@app.post('/api/housekeeping')
def hk_add():
    j = request.json
    execute("INSERT INTO housekeeping(room_id, assigned_to, notes) VALUES(:r,:a,:n)",
            dict(r=j['room_id'], a=j.get('assigned_to'), n=j.get('notes')))
    return jsonify(ok=True)

@app.post('/api/housekeeping/<int:i>/assign')
def hk_assign(i):
    execute("UPDATE housekeeping SET assigned_to=:a, task_status='IN_PROGRESS' WHERE task_id=:i",
            dict(a=request.json['assigned_to'], i=i))
    return jsonify(ok=True)

@app.post('/api/housekeeping/<int:i>/complete')
def hk_done(i):
    plsql("BEGIN sp_complete_housekeeping(:i); END;", dict(i=i))
    return jsonify(ok=True)

# ------------------------- dashboard & revenue ---------------------------
@app.get('/api/dashboard')
def dashboard():
    s = query("""SELECT (SELECT COUNT(*) FROM hotel) hotels, (SELECT COUNT(*) FROM room) rooms,
                 (SELECT COUNT(*) FROM room WHERE status='AVAILABLE') available,
                 (SELECT COUNT(*) FROM reservation WHERE status IN ('BOOKED','CHECKED_IN')) active,
                 (SELECT COUNT(*) FROM room WHERE status='OCCUPIED') occupied,
                 (SELECT NVL(SUM(revenue),0) FROM v_revenue_daily) revenue FROM dual""")[0]
    s['occupancy'] = round(100 * s['occupied'] / s['rooms'], 1) if s['rooms'] else 0
    return jsonify(s)

REVENUE = {
    'daily': """SELECT TO_CHAR(day,'YYYY-MM-DD') label, SUM(revenue) revenue FROM v_revenue_daily
                 WHERE day >= TRUNC(SYSDATE)-30 GROUP BY day ORDER BY day""",
    'monthly': """SELECT TO_CHAR(day,'YYYY-MM') label, SUM(revenue) revenue FROM v_revenue_daily
                   GROUP BY TO_CHAR(day,'YYYY-MM') ORDER BY 1""",
    'yearly': """SELECT TO_CHAR(day,'YYYY') label, SUM(revenue) revenue FROM v_revenue_daily
                  GROUP BY TO_CHAR(day,'YYYY') ORDER BY 1""",
    'hotels': """SELECT h.hotel_name label,
                   NVL((SELECT SUM(revenue) FROM v_revenue_daily v WHERE v.hotel_id=h.hotel_id),0) revenue,
                   (SELECT COUNT(*) FROM room r WHERE r.hotel_id=h.hotel_id) rooms,
                   (SELECT COUNT(*) FROM room r WHERE r.hotel_id=h.hotel_id AND r.status='OCCUPIED') occupied
              FROM hotel h ORDER BY h.hotel_id""",
    'seasonal': """SELECT TO_CHAR(check_in_date,'Mon') label, COUNT(*) bookings FROM reservation
                    WHERE status <> 'CANCELLED' GROUP BY TO_CHAR(check_in_date,'Mon'), TO_CHAR(check_in_date,'MM')
                    ORDER BY TO_CHAR(check_in_date,'MM')""",
}

@app.get('/api/revenue/<kind>')
def revenue(kind):
    if kind not in REVENUE:
        return jsonify(error='Unknown report'), 404
    rows = query(REVENUE[kind])
    if kind == 'hotels':
        for r in rows:
            r['occupancy'] = round(100 * r['occupied'] / r['rooms'], 1) if r['rooms'] else 0
    return jsonify(rows)

if __name__ == '__main__':
    app.run(debug=True)