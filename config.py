import os

# Railway gives this value automatically (we connect it in Railway Variables).
# The default below is only for running on your own laptop.
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/hotel")
SECRET_KEY = os.getenv("SECRET_KEY", "dev-secret-change-me")

# Demo logins (development defaults)
USERS = {
    "admin": "admin123",
    "reception": "hotel123"
}
