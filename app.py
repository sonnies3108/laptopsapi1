import os
import time
from contextlib import asynccontextmanager

import pymysql
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel


# ---------- 1. Підключення до бази ----------
# Адреса, логін і пароль беремо зі ЗМІННИХ СЕРЕДОВИЩА, а не пишемо в коді.
# Так пароль не потрапить на GitHub (цього вимагає лаба).
def get_connection():
    return pymysql.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", "3306")),
        user=os.environ.get("DB_USER", "root"),
        password=os.environ.get("DB_PASSWORD", ""),
        database=os.environ.get("DB_NAME", "labor_sql"),
        cursorclass=pymysql.cursors.DictCursor,  # рядки повертаються як словники
        autocommit=True,  # зміни зберігаються одразу
    )


# ---------- 2. Дії при запуску програми ----------
# Створюємо таблицю, якщо її ще немає. База може запускатися повільніше
# за програму, тому пробуємо підключитись до 30 разів з паузою 2 секунди.
@asynccontextmanager
async def lifespan(app: FastAPI):
    for attempt in range(30):
        try:
            with get_connection() as conn, conn.cursor() as cur:
                cur.execute(
                    """
                    CREATE TABLE IF NOT EXISTS laptop (
                        code   INT AUTO_INCREMENT PRIMARY KEY,
                        model  VARCHAR(50) NOT NULL,
                        speed  SMALLINT NOT NULL,
                        ram    SMALLINT NOT NULL,
                        hd     REAL NOT NULL,
                        price  DECIMAL(8,2) NULL,
                        screen TINYINT NOT NULL
                    )
                    """
                )
            break
        except pymysql.err.OperationalError:
            print(f"База ще не готова, спроба {attempt + 1}/30...")
            time.sleep(2)
    yield


app = FastAPI(title="Laptops API", lifespan=lifespan)


# ---------- 3. Опис даних, які приймаємо від клієнта ----------
class LaptopIn(BaseModel):
    model: str
    speed: int
    ram: int
    hd: float
    price: float | None = None
    screen: int


# ---------- 4. Адреси (ендпоінти) ----------

# Перевірка "я живий". Не чіпає базу. Знадобиться балансувальнику.
@app.get("/health")
def health():
    return {"status": "ok"}


# Показати всі ноутбуки (як SELECT * FROM laptop)
@app.get("/laptops")
def list_laptops():
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM laptop")
        return cur.fetchall()


# Показати один ноутбук за кодом
@app.get("/laptops/{code}")
def get_laptop(code: int):
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM laptop WHERE code = %s", (code,))
        row = cur.fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="Ноутбук не знайдено")
    return row


# Додати ноутбук (як INSERT INTO)
@app.post("/laptops", status_code=201)
def create_laptop(item: LaptopIn):
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO laptop (model, speed, ram, hd, price, screen) "
            "VALUES (%s, %s, %s, %s, %s, %s)",
            (item.model, item.speed, item.ram, item.hd, item.price, item.screen),
        )
        new_code = cur.lastrowid
    return {"code": new_code, **item.model_dump()}


# Видалити ноутбук (як DELETE FROM)
@app.delete("/laptops/{code}")
def delete_laptop(code: int):
    with get_connection() as conn, conn.cursor() as cur:
        cur.execute("DELETE FROM laptop WHERE code = %s", (code,))
        deleted = cur.rowcount
    if deleted == 0:
        raise HTTPException(status_code=404, detail="Ноутбук не знайдено")
    return {"deleted": code}
