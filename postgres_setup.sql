-- =====================================================================
-- HOTEL CHAIN RESERVATION & REVENUE MANAGEMENT SYSTEM  (PostgreSQL)
-- Converted from the Oracle scripts 01_schema.sql + 02_plsql_and_data.sql
-- Safe to re-run: it drops the old tables first (data is reset).
-- =====================================================================

DROP TABLE IF EXISTS housekeeping, payment, invoice, service_usage, service,
    check_in_check_out, reservation_room, reservation, guest, room, room_type, hotel CASCADE;
DROP SEQUENCE IF EXISTS seq_booking_ref;

-- 1. HOTEL ------------------------------------------------------------
CREATE TABLE hotel (
  hotel_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  hotel_name   VARCHAR(100) NOT NULL,
  city         VARCHAR(60)  NOT NULL,
  state        VARCHAR(60),
  address      VARCHAR(200),
  phone        VARCHAR(20),
  email        VARCHAR(100),
  star_rating  SMALLINT CHECK (star_rating BETWEEN 1 AND 5),
  status       VARCHAR(10) DEFAULT 'ACTIVE' NOT NULL
               CHECK (status IN ('ACTIVE','INACTIVE')),
  created_at   TIMESTAMP DEFAULT now() NOT NULL,
  CONSTRAINT uq_hotel_name_city UNIQUE (hotel_name, city)
);

-- 2. ROOM_TYPE --------------------------------------------------------
CREATE TABLE room_type (
  type_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  type_name      VARCHAR(40) NOT NULL UNIQUE,
  description    VARCHAR(200),
  base_price     NUMERIC(10,2) NOT NULL CHECK (base_price > 0),
  max_occupancy  SMALLINT      NOT NULL CHECK (max_occupancy > 0)
);

-- 3. ROOM -------------------------------------------------------------
CREATE TABLE room (
  room_id          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  hotel_id         INTEGER NOT NULL REFERENCES hotel(hotel_id),
  type_id          INTEGER NOT NULL REFERENCES room_type(type_id),
  room_number      VARCHAR(10) NOT NULL,
  floor_no         SMALLINT,
  price_per_night  NUMERIC(10,2) NOT NULL CHECK (price_per_night > 0),
  status           VARCHAR(12) DEFAULT 'AVAILABLE' NOT NULL
                   CHECK (status IN ('AVAILABLE','RESERVED','OCCUPIED','MAINTENANCE')),
  CONSTRAINT uq_room_per_hotel UNIQUE (hotel_id, room_number)
);

-- 4. GUEST ------------------------------------------------------------
CREATE TABLE guest (
  guest_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  first_name     VARCHAR(50) NOT NULL,
  last_name      VARCHAR(50) NOT NULL,
  email          VARCHAR(100) NOT NULL UNIQUE,
  phone          VARCHAR(20)  NOT NULL,
  address        VARCHAR(200),
  id_proof_type  VARCHAR(30),
  id_proof_no    VARCHAR(40),
  created_at     TIMESTAMP DEFAULT now() NOT NULL
);

-- 5. RESERVATION ------------------------------------------------------
CREATE SEQUENCE seq_booking_ref START WITH 1001 INCREMENT BY 1;

CREATE TABLE reservation (
  reservation_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_ref     VARCHAR(20) NOT NULL UNIQUE,
  guest_id        INTEGER NOT NULL REFERENCES guest(guest_id),
  hotel_id        INTEGER NOT NULL REFERENCES hotel(hotel_id),
  check_in_date   DATE NOT NULL,
  check_out_date  DATE NOT NULL,
  num_guests      SMALLINT DEFAULT 1 NOT NULL CHECK (num_guests > 0),
  status          VARCHAR(12) DEFAULT 'BOOKED' NOT NULL
                  CHECK (status IN ('BOOKED','CHECKED_IN','CHECKED_OUT','CANCELLED')),
  created_at      TIMESTAMP DEFAULT now() NOT NULL,
  cancelled_at    TIMESTAMP,
  CONSTRAINT ck_res_dates CHECK (check_out_date > check_in_date)
);

-- 6. RESERVATION_ROOM -------------------------------------------------
CREATE TABLE reservation_room (
  res_room_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reservation_id  INTEGER NOT NULL REFERENCES reservation(reservation_id),
  room_id         INTEGER NOT NULL REFERENCES room(room_id),
  rate_per_night  NUMERIC(10,2) NOT NULL CHECK (rate_per_night > 0),
  check_in_date   DATE NOT NULL,
  check_out_date  DATE NOT NULL,
  status          VARCHAR(10) DEFAULT 'ACTIVE' NOT NULL
                  CHECK (status IN ('ACTIVE','CANCELLED')),
  CONSTRAINT ck_rr_dates CHECK (check_out_date > check_in_date),
  CONSTRAINT uq_res_room UNIQUE (reservation_id, room_id)
);

-- 7. CHECK_IN_CHECK_OUT -----------------------------------------------
CREATE TABLE check_in_check_out (
  stay_id           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reservation_id    INTEGER NOT NULL REFERENCES reservation(reservation_id),
  room_id           INTEGER NOT NULL REFERENCES room(room_id),
  actual_check_in   TIMESTAMP NOT NULL,
  actual_check_out  TIMESTAMP,
  CONSTRAINT ck_stay_dates CHECK (actual_check_out IS NULL
                                  OR actual_check_out >= actual_check_in)
);

-- 8. SERVICE ----------------------------------------------------------
CREATE TABLE service (
  service_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  hotel_id      INTEGER NOT NULL REFERENCES hotel(hotel_id),
  service_name  VARCHAR(80) NOT NULL,
  category      VARCHAR(20) NOT NULL
                CHECK (category IN ('RESTAURANT','LAUNDRY','SPA','TRANSPORT','OTHER')),
  unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
  CONSTRAINT uq_service UNIQUE (hotel_id, service_name)
);

-- 9. SERVICE_USAGE ----------------------------------------------------
CREATE TABLE service_usage (
  usage_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reservation_id  INTEGER NOT NULL REFERENCES reservation(reservation_id),
  service_id      INTEGER NOT NULL REFERENCES service(service_id),
  quantity        INTEGER DEFAULT 1 NOT NULL CHECK (quantity > 0),
  unit_price      NUMERIC(10,2) NOT NULL,
  total_amount    NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  usage_date      TIMESTAMP DEFAULT now() NOT NULL
);

-- 10. INVOICE ---------------------------------------------------------
CREATE TABLE invoice (
  invoice_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  reservation_id   INTEGER NOT NULL UNIQUE REFERENCES reservation(reservation_id),
  room_charges     NUMERIC(12,2) DEFAULT 0 NOT NULL,
  service_charges  NUMERIC(12,2) DEFAULT 0 NOT NULL,
  tax_amount       NUMERIC(12,2) DEFAULT 0 NOT NULL,
  discount         NUMERIC(12,2) DEFAULT 0 NOT NULL,
  total_amount     NUMERIC(12,2) DEFAULT 0 NOT NULL,
  payment_status   VARCHAR(10) DEFAULT 'PENDING' NOT NULL
                   CHECK (payment_status IN ('PENDING','PARTIAL','PAID','REFUNDED')),
  issued_at        TIMESTAMP DEFAULT now() NOT NULL
);

-- 11. PAYMENT (also stores refunds as payment_type = 'REFUND') ---------
CREATE TABLE payment (
  payment_id    INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  invoice_id    INTEGER NOT NULL REFERENCES invoice(invoice_id),
  amount        NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  payment_type  VARCHAR(10) DEFAULT 'PAYMENT' NOT NULL
                CHECK (payment_type IN ('PAYMENT','REFUND')),
  method        VARCHAR(10) NOT NULL
                CHECK (method IN ('CASH','CARD','UPI','ONLINE')),
  paid_at       TIMESTAMP DEFAULT now() NOT NULL,
  reference_no  VARCHAR(40)
);

-- 12. HOUSEKEEPING ----------------------------------------------------
CREATE TABLE housekeeping (
  task_id       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  room_id       INTEGER NOT NULL REFERENCES room(room_id),
  assigned_to   VARCHAR(80),
  task_status   VARCHAR(12) DEFAULT 'PENDING' NOT NULL
                CHECK (task_status IN ('PENDING','IN_PROGRESS','CLEAN')),
  task_date     TIMESTAMP DEFAULT now() NOT NULL,
  completed_at  TIMESTAMP,
  notes         VARCHAR(200)
);

-- INDEXES -------------------------------------------------------------
CREATE INDEX idx_room_hotel_status   ON room(hotel_id, status);
CREATE INDEX idx_rr_room_dates       ON reservation_room(room_id, check_in_date, check_out_date);
CREATE INDEX idx_res_guest           ON reservation(guest_id);
CREATE INDEX idx_res_hotel_dates     ON reservation(hotel_id, check_in_date, check_out_date);
CREATE INDEX idx_usage_res           ON service_usage(reservation_id);
CREATE INDEX idx_payment_invoice     ON payment(invoice_id);
CREATE INDEX idx_hk_room_status      ON housekeeping(room_id, task_status);

-- ---------------------------------------------------------------------
-- FUNCTIONS: invoice calculation (date - date = number of nights)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_room_charges(p_res INTEGER) RETURNS NUMERIC AS $$
  SELECT COALESCE(SUM(rate_per_night * (check_out_date - check_in_date)), 0)
    FROM reservation_room
   WHERE reservation_id = p_res AND status = 'ACTIVE';
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_service_charges(p_res INTEGER) RETURNS NUMERIC AS $$
  SELECT COALESCE(SUM(total_amount), 0) FROM service_usage WHERE reservation_id = p_res;
$$ LANGUAGE sql STABLE;

-- Total = (room + services) + 12% tax
CREATE OR REPLACE FUNCTION fn_invoice_total(p_res INTEGER) RETURNS NUMERIC AS $$
  SELECT ROUND((fn_room_charges(p_res) + fn_service_charges(p_res)) * 1.12, 2);
$$ LANGUAGE sql STABLE;

-- Re-calculates (or creates) the invoice. Caller controls the transaction.
CREATE OR REPLACE FUNCTION sp_refresh_invoice(p_res INTEGER) RETURNS VOID AS $$
DECLARE
  v_room NUMERIC := fn_room_charges(p_res);
  v_svc  NUMERIC := fn_service_charges(p_res);
  v_tax  NUMERIC := ROUND((fn_room_charges(p_res) + fn_service_charges(p_res)) * 0.12, 2);
BEGIN
  UPDATE invoice
     SET room_charges = v_room, service_charges = v_svc, tax_amount = v_tax,
         total_amount = v_room + v_svc + v_tax - discount
   WHERE reservation_id = p_res;
  IF NOT FOUND THEN
    INSERT INTO invoice(reservation_id, room_charges, service_charges, tax_amount, total_amount)
    VALUES (p_res, v_room, v_svc, v_tax, v_room + v_svc + v_tax);
  END IF;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- TRIGGERS
-- ---------------------------------------------------------------------
-- Last line of defence against double booking
CREATE OR REPLACE FUNCTION trg_rr_no_overlap_fn() RETURNS TRIGGER AS $$
DECLARE v INTEGER;
BEGIN
  IF NEW.status = 'ACTIVE' THEN
    SELECT COUNT(*) INTO v FROM reservation_room
     WHERE room_id = NEW.room_id AND status = 'ACTIVE'
       AND check_in_date < NEW.check_out_date AND check_out_date > NEW.check_in_date;
    IF v > 0 THEN
      RAISE EXCEPTION 'Room already booked for these dates';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_rr_no_overlap BEFORE INSERT ON reservation_room
  FOR EACH ROW EXECUTE FUNCTION trg_rr_no_overlap_fn();

-- Room becomes RESERVED when a booking starts today; freed on cancellation
CREATE OR REPLACE FUNCTION trg_rr_room_status_fn() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.check_in_date <= CURRENT_DATE THEN
      UPDATE room SET status = 'RESERVED' WHERE room_id = NEW.room_id AND status = 'AVAILABLE';
    END IF;
  ELSIF NEW.status = 'CANCELLED' THEN
    UPDATE room SET status = 'AVAILABLE' WHERE room_id = NEW.room_id AND status = 'RESERVED';
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_rr_room_status AFTER INSERT OR UPDATE OF status ON reservation_room
  FOR EACH ROW EXECUTE FUNCTION trg_rr_room_status_fn();

-- Check-in -> OCCUPIED. Check-out -> MAINTENANCE + new housekeeping task
CREATE OR REPLACE FUNCTION trg_stay_room_status_fn() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE room SET status = 'OCCUPIED' WHERE room_id = NEW.room_id;
  ELSIF OLD.actual_check_out IS NULL AND NEW.actual_check_out IS NOT NULL THEN
    UPDATE room SET status = 'MAINTENANCE' WHERE room_id = NEW.room_id;
    INSERT INTO housekeeping(room_id, task_status, notes)
    VALUES (NEW.room_id, 'PENDING', 'Post check-out cleaning');
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_stay_room_status AFTER INSERT OR UPDATE OF actual_check_out ON check_in_check_out
  FOR EACH ROW EXECUTE FUNCTION trg_stay_room_status_fn();

-- Housekeeping finished -> room is AVAILABLE again
CREATE OR REPLACE FUNCTION trg_hk_room_status_fn() RETURNS TRIGGER AS $$
BEGIN
  UPDATE room SET status = 'AVAILABLE' WHERE room_id = NEW.room_id AND status = 'MAINTENANCE';
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_hk_room_status AFTER UPDATE OF task_status ON housekeeping
  FOR EACH ROW WHEN (NEW.task_status = 'CLEAN')
  EXECUTE FUNCTION trg_hk_room_status_fn();

-- ---------------------------------------------------------------------
-- "PROCEDURES" (PostgreSQL functions). Each call runs as one transaction;
-- Flask commits on success and rolls back if RAISE EXCEPTION happens.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION sp_book_room(
  p_guest INTEGER, p_hotel INTEGER, p_room INTEGER,
  p_in DATE, p_out DATE, p_guests INTEGER) RETURNS VARCHAR AS $$
DECLARE
  v_price  NUMERIC;
  v_rhotel INTEGER;
  v_res    INTEGER;
  v_cnt    INTEGER;
  v_ref    VARCHAR;
BEGIN
  IF p_out <= p_in THEN
    RAISE EXCEPTION 'Check-out must be after check-in';
  END IF;
  -- LOCK the room row so two users cannot book the same room together
  SELECT price_per_night, hotel_id INTO v_price, v_rhotel
    FROM room WHERE room_id = p_room FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Room not found';
  END IF;
  IF v_rhotel <> p_hotel THEN
    RAISE EXCEPTION 'Room does not belong to this hotel';
  END IF;
  SELECT COUNT(*) INTO v_cnt FROM reservation_room
   WHERE room_id = p_room AND status = 'ACTIVE'
     AND check_in_date < p_out AND check_out_date > p_in;
  IF v_cnt > 0 THEN
    RAISE EXCEPTION 'Room already booked for these dates';
  END IF;
  v_ref := 'BK-' || to_char(now(), 'YYYY') || '-' || nextval('seq_booking_ref')::TEXT;
  INSERT INTO reservation(booking_ref, guest_id, hotel_id, check_in_date, check_out_date, num_guests)
  VALUES (v_ref, p_guest, p_hotel, p_in, p_out, p_guests)
  RETURNING reservation_id INTO v_res;
  INSERT INTO reservation_room(reservation_id, room_id, rate_per_night, check_in_date, check_out_date)
  VALUES (v_res, p_room, v_price, p_in, p_out);
  PERFORM sp_refresh_invoice(v_res);
  RETURN v_ref;
END;
$$ LANGUAGE plpgsql;

-- Cancellation policy: 100% refund if >= 2 days before check-in, else 50%
CREATE OR REPLACE FUNCTION sp_cancel_reservation(
  p_res INTEGER, p_method VARCHAR DEFAULT 'CASH') RETURNS NUMERIC AS $$
DECLARE
  v_status VARCHAR;
  v_in     DATE;
  v_inv    INTEGER;
  v_paid   NUMERIC;
  v_refund NUMERIC;
BEGIN
  SELECT status, check_in_date INTO v_status, v_in
    FROM reservation WHERE reservation_id = p_res FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reservation not found';
  END IF;
  IF v_status <> 'BOOKED' THEN
    RAISE EXCEPTION 'Only BOOKED reservations can be cancelled';
  END IF;
  UPDATE reservation_room SET status = 'CANCELLED' WHERE reservation_id = p_res;
  UPDATE reservation SET status = 'CANCELLED', cancelled_at = now() WHERE reservation_id = p_res;
  SELECT invoice_id INTO v_inv FROM invoice WHERE reservation_id = p_res;
  SELECT COALESCE(SUM(CASE WHEN payment_type = 'REFUND' THEN -amount ELSE amount END), 0)
    INTO v_paid FROM payment WHERE invoice_id = v_inv;
  v_refund := ROUND(v_paid * CASE WHEN (v_in::TIMESTAMP - localtimestamp) >= INTERVAL '2 days'
                                  THEN 1 ELSE 0.5 END, 2);
  IF v_refund > 0 THEN
    INSERT INTO payment(invoice_id, amount, payment_type, method, reference_no)
    VALUES (v_inv, v_refund, 'REFUND', p_method, 'RF-' || p_res::TEXT);
  END IF;
  -- Whatever is retained becomes the cancellation fee
  UPDATE invoice
     SET room_charges = 0, service_charges = 0, tax_amount = 0,
         total_amount = v_paid - v_refund,
         payment_status = CASE WHEN v_paid - v_refund > 0 THEN 'PAID'
                               WHEN v_refund > 0 THEN 'REFUNDED' ELSE 'PAID' END
   WHERE invoice_id = v_inv;
  RETURN v_refund;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sp_check_in(p_res INTEGER, p_when TIMESTAMP DEFAULT localtimestamp)
RETURNS VOID AS $$
DECLARE
  v_status VARCHAR;
BEGIN
  SELECT status INTO v_status FROM reservation WHERE reservation_id = p_res FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reservation not found';
  END IF;
  IF v_status <> 'BOOKED' THEN
    RAISE EXCEPTION 'Only BOOKED reservations can be checked in';
  END IF;
  INSERT INTO check_in_check_out(reservation_id, room_id, actual_check_in)
  SELECT reservation_id, room_id, p_when FROM reservation_room
   WHERE reservation_id = p_res AND status = 'ACTIVE';
  UPDATE reservation SET status = 'CHECKED_IN' WHERE reservation_id = p_res;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sp_check_out(p_res INTEGER, p_when TIMESTAMP DEFAULT localtimestamp)
RETURNS VOID AS $$
DECLARE
  v_status VARCHAR;
BEGIN
  SELECT status INTO v_status FROM reservation WHERE reservation_id = p_res FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reservation not found';
  END IF;
  IF v_status <> 'CHECKED_IN' THEN
    RAISE EXCEPTION 'Only CHECKED_IN reservations can be checked out';
  END IF;
  UPDATE check_in_check_out SET actual_check_out = p_when
   WHERE reservation_id = p_res AND actual_check_out IS NULL;   -- trigger -> housekeeping
  UPDATE reservation SET status = 'CHECKED_OUT' WHERE reservation_id = p_res;
  PERFORM sp_refresh_invoice(p_res);
END;
$$ LANGUAGE plpgsql;

-- Record a service used by the guest; invoice is updated automatically
CREATE OR REPLACE FUNCTION sp_add_service(p_res INTEGER, p_service INTEGER, p_qty INTEGER DEFAULT 1)
RETURNS VOID AS $$
DECLARE
  v_price  NUMERIC;
  v_status VARCHAR;
BEGIN
  SELECT status INTO v_status FROM reservation WHERE reservation_id = p_res FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reservation or service not found';
  END IF;
  IF v_status IN ('CANCELLED', 'CHECKED_OUT') THEN
    RAISE EXCEPTION 'Cannot add services to a % reservation', v_status;
  END IF;
  SELECT unit_price INTO v_price FROM service WHERE service_id = p_service;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Reservation or service not found';
  END IF;
  INSERT INTO service_usage(reservation_id, service_id, quantity, unit_price)
  VALUES (p_res, p_service, p_qty, v_price);
  PERFORM sp_refresh_invoice(p_res);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sp_record_payment(
  p_inv INTEGER, p_amt NUMERIC, p_type VARCHAR, p_method VARCHAR,
  p_when TIMESTAMP DEFAULT localtimestamp) RETURNS VOID AS $$
DECLARE
  v_total NUMERIC;
  v_net   NUMERIC;
BEGIN
  INSERT INTO payment(invoice_id, amount, payment_type, method, paid_at, reference_no)
  VALUES (p_inv, p_amt, p_type, p_method, p_when,
          'PY-' || to_char(now(), 'YYMMDDHH24MISS') || p_inv::TEXT);
  SELECT total_amount INTO v_total FROM invoice WHERE invoice_id = p_inv;
  SELECT SUM(CASE WHEN payment_type = 'REFUND' THEN -amount ELSE amount END)
    INTO v_net FROM payment WHERE invoice_id = p_inv;
  UPDATE invoice
     SET payment_status = CASE WHEN v_net >= v_total THEN 'PAID'
                               WHEN v_net > 0 THEN 'PARTIAL' ELSE 'PENDING' END
   WHERE invoice_id = p_inv;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sp_complete_housekeeping(p_task INTEGER) RETURNS VOID AS $$
BEGIN
  UPDATE housekeeping SET task_status = 'CLEAN', completed_at = localtimestamp
   WHERE task_id = p_task;                        -- trigger frees the room
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- VIEWS
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_booking_summary AS
SELECT r.reservation_id, r.booking_ref, g.first_name || ' ' || g.last_name AS guest,
       h.hotel_name AS hotel, r.hotel_id, r.guest_id, r.check_in_date, r.check_out_date,
       (r.check_out_date - r.check_in_date) AS nights, r.num_guests, r.status,
       (SELECT string_agg(rm.room_number, ', ' ORDER BY rm.room_number)
          FROM reservation_room rr JOIN room rm ON rm.room_id = rr.room_id
         WHERE rr.reservation_id = r.reservation_id AND rr.status = 'ACTIVE') AS rooms,
       COALESCE(i.total_amount, 0) AS total_amount, i.payment_status
  FROM reservation r
  JOIN guest g ON g.guest_id = r.guest_id
  JOIN hotel h ON h.hotel_id = r.hotel_id
  LEFT JOIN invoice i ON i.reservation_id = r.reservation_id;

-- Revenue = payments minus refunds, per hotel per day
CREATE OR REPLACE VIEW v_revenue_daily AS
SELECT r.hotel_id, p.paid_at::DATE AS day,
       SUM(CASE WHEN p.payment_type = 'REFUND' THEN -p.amount ELSE p.amount END) AS revenue
  FROM payment p
  JOIN invoice i ON i.invoice_id = p.invoice_id
  JOIN reservation r ON r.reservation_id = i.reservation_id
 GROUP BY r.hotel_id, p.paid_at::DATE;

-- =====================================================================
-- SAMPLE DATA (dates are relative to today so dashboards always have data)
-- =====================================================================
INSERT INTO hotel(hotel_name, city, state, address, phone, email, star_rating) VALUES ('Azure Grand Delhi','Delhi','Delhi','12 Connaught Place','011-4000-1001','delhi@azurehotels.com',5);
INSERT INTO hotel(hotel_name, city, state, address, phone, email, star_rating) VALUES ('Azure Beach Resort','Goa','Goa','Calangute Beach Road','0832-250-2002','goa@azurehotels.com',4);
INSERT INTO hotel(hotel_name, city, state, address, phone, email, star_rating) VALUES ('Azure Hills Retreat','Shimla','Himachal Pradesh','Mall Road','0177-280-3003','shimla@azurehotels.com',4);

INSERT INTO room_type(type_name, description, base_price, max_occupancy) VALUES ('Standard','Comfortable room, city view',3000,2);
INSERT INTO room_type(type_name, description, base_price, max_occupancy) VALUES ('Deluxe','Larger room with balcony',5000,3);
INSERT INTO room_type(type_name, description, base_price, max_occupancy) VALUES ('Suite','Living area and premium bath',9000,4);
INSERT INTO room_type(type_name, description, base_price, max_occupancy) VALUES ('Family','Two bedrooms for families',6500,5);
INSERT INTO room_type(type_name, description, base_price, max_occupancy) VALUES ('Executive','Work desk and lounge access',7500,2);

-- Hotel 1 (room_id 1-5)
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (1,1,'101',1,3200);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (1,1,'102',1,3200);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (1,2,'201',2,5400);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (1,3,'301',3,9800);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (1,5,'302',3,7800);
-- Hotel 2 (6-10)
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (2,1,'G01',0,2800);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (2,2,'G02',0,4800);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (2,2,'A10',1,5200);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (2,3,'A11',1,10500);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (2,4,'A12',1,6800);
-- Hotel 3 (11-15)
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (3,1,'11',1,2900);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (3,2,'12',1,4900);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (3,4,'21',2,6600);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (3,3,'22',2,9500);
INSERT INTO room(hotel_id,type_id,room_number,floor_no,price_per_night) VALUES (3,5,'23',2,7200);

INSERT INTO guest(first_name,last_name,email,phone,address,id_proof_type,id_proof_no) VALUES ('Aarav','Sharma','aarav.sharma@mail.com','9810000001','Noida, UP','Aadhaar','XXXX-1111');
INSERT INTO guest(first_name,last_name,email,phone,address,id_proof_type,id_proof_no) VALUES ('Priya','Verma','priya.verma@mail.com','9810000002','Jaipur, RJ','Passport','P1234567');
INSERT INTO guest(first_name,last_name,email,phone,address,id_proof_type,id_proof_no) VALUES ('Rohan','Mehta','rohan.mehta@mail.com','9810000003','Mumbai, MH','Aadhaar','XXXX-3333');
INSERT INTO guest(first_name,last_name,email,phone,address,id_proof_type,id_proof_no) VALUES ('Sneha','Iyer','sneha.iyer@mail.com','9810000004','Chennai, TN','Driving Licence','DL-0044');
INSERT INTO guest(first_name,last_name,email,phone,address,id_proof_type,id_proof_no) VALUES ('Vikram','Singh','vikram.singh@mail.com','9810000005','Chandigarh','Aadhaar','XXXX-5555');
INSERT INTO guest(first_name,last_name,email,phone,address,id_proof_type,id_proof_no) VALUES ('Ananya','Das','ananya.das@mail.com','9810000006','Kolkata, WB','Passport','P7654321');
INSERT INTO guest(first_name,last_name,email,phone,address,id_proof_type,id_proof_no) VALUES ('Karan','Patel','karan.patel@mail.com','9810000007','Ahmedabad, GJ','Aadhaar','XXXX-7777');
INSERT INTO guest(first_name,last_name,email,phone,address,id_proof_type,id_proof_no) VALUES ('Meera','Nair','meera.nair@mail.com','9810000008','Kochi, KL','Aadhaar','XXXX-8888');
INSERT INTO guest(first_name,last_name,email,phone,address,id_proof_type,id_proof_no) VALUES ('Arjun','Reddy','arjun.reddy@mail.com','9810000009','Hyderabad, TS','Passport','P1112223');
INSERT INTO guest(first_name,last_name,email,phone,address,id_proof_type,id_proof_no) VALUES ('Divya','Kapoor','divya.kapoor@mail.com','9810000010','Delhi','Aadhaar','XXXX-1010');

INSERT INTO service(hotel_id,service_name,category,unit_price) VALUES (1,'Dinner Buffet','RESTAURANT',1200);
INSERT INTO service(hotel_id,service_name,category,unit_price) VALUES (1,'Laundry (per item)','LAUNDRY',150);
INSERT INTO service(hotel_id,service_name,category,unit_price) VALUES (1,'Airport Transfer','TRANSPORT',1500);
INSERT INTO service(hotel_id,service_name,category,unit_price) VALUES (2,'Seafood Dinner','RESTAURANT',1800);
INSERT INTO service(hotel_id,service_name,category,unit_price) VALUES (2,'Laundry (per item)','LAUNDRY',120);
INSERT INTO service(hotel_id,service_name,category,unit_price) VALUES (2,'Spa Session','SPA',2500);
INSERT INTO service(hotel_id,service_name,category,unit_price) VALUES (3,'Breakfast','RESTAURANT',600);
INSERT INTO service(hotel_id,service_name,category,unit_price) VALUES (3,'Laundry (per item)','LAUNDRY',100);
INSERT INTO service(hotel_id,service_name,category,unit_price) VALUES (3,'Bonfire Evening','OTHER',800);

-- 10 reservations built with the REAL booking function, then stays,
-- services and payments. Reservation N gets invoice N.
CREATE OR REPLACE FUNCTION tmp_pay(p_res INTEGER, p_amt NUMERIC, p_method VARCHAR,
                                   p_when TIMESTAMP DEFAULT localtimestamp) RETURNS VOID AS $$
DECLARE v_inv INTEGER;
BEGIN
  SELECT invoice_id INTO v_inv FROM invoice WHERE reservation_id = p_res;
  PERFORM sp_record_payment(v_inv, p_amt, 'PAYMENT', p_method, p_when);
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
  d DATE := CURRENT_DATE;
BEGIN
  -- Completed stays
  PERFORM sp_book_room(1,1,1,d-60,d-57,2);  PERFORM sp_add_service(1,1,2); PERFORM sp_add_service(1,2,5);
  PERFORM sp_check_in(1,d-60); PERFORM sp_check_out(1,d-57); PERFORM tmp_pay(1, fn_invoice_total(1),'CARD',d-57);

  PERFORM sp_book_room(2,1,3,d-45,d-42,2);  PERFORM sp_add_service(2,3,1);
  PERFORM sp_check_in(2,d-45); PERFORM sp_check_out(2,d-42); PERFORM tmp_pay(2, fn_invoice_total(2),'UPI',d-42);

  PERFORM sp_book_room(3,2,9,d-30,d-27,3);  PERFORM sp_add_service(3,4,3); PERFORM sp_add_service(3,6,2);
  PERFORM sp_check_in(3,d-30); PERFORM sp_check_out(3,d-27); PERFORM tmp_pay(3, fn_invoice_total(3),'CARD',d-27);

  PERFORM sp_book_room(4,2,7,d-20,d-18,2);  PERFORM sp_add_service(4,5,8);
  PERFORM sp_check_in(4,d-20); PERFORM sp_check_out(4,d-18); PERFORM tmp_pay(4, fn_invoice_total(4),'CASH',d-18);

  PERFORM sp_book_room(5,3,14,d-10,d-7,4);  PERFORM sp_add_service(5,7,6); PERFORM sp_add_service(5,9,1);
  PERFORM sp_check_in(5,d-10); PERFORM sp_check_out(5,d-7); PERFORM tmp_pay(5, fn_invoice_total(5),'ONLINE',d-7);

  -- In-house guests (rooms OCCUPIED), partial payments
  PERFORM sp_book_room(6,1,4,d-1,d+2,2);   PERFORM sp_check_in(6,d-1);  PERFORM sp_add_service(6,1,2);  PERFORM tmp_pay(6,5000,'CARD');
  PERFORM sp_book_room(7,2,8,d,d+3,2);     PERFORM sp_check_in(7,d);    PERFORM sp_add_service(7,6,1);  PERFORM tmp_pay(7,3000,'UPI');

  -- Future bookings
  PERFORM sp_book_room(8,3,12,d+5,d+8,2);  PERFORM tmp_pay(8,2000,'UPI');
  PERFORM sp_book_room(9,1,5,d+10,d+14,2);

  -- Cancelled booking with refund (more than 2 days ahead -> 100%)
  PERFORM sp_book_room(10,3,13,d+3,d+5,3); PERFORM tmp_pay(10,4000,'CARD');
  PERFORM sp_cancel_reservation(10,'CARD');

  -- Housekeeping: most post-checkout cleans done; assign the rest
  FOR t IN 1..4 LOOP PERFORM sp_complete_housekeeping(t); END LOOP;
  UPDATE housekeeping SET assigned_to = 'Sunita Devi', task_status = 'IN_PROGRESS' WHERE task_id = 5;
END;
$$;

DROP FUNCTION tmp_pay(INTEGER, NUMERIC, VARCHAR, TIMESTAMP);

-- Room 15 under maintenance (manual status)
UPDATE room SET status = 'MAINTENANCE' WHERE room_id = 15;
INSERT INTO housekeeping(room_id, assigned_to, task_status, notes) VALUES (15,'Ramesh Kumar','PENDING','AC repair and deep clean');
