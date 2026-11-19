import json
import os
import time
from contextlib import asynccontextmanager

import pymysql
import redis
from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.encoders import jsonable_encoder
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


# ---------- 1б. Кеш (Redis), схема cache-aside ----------
# REDIS_HOST не заданий -> кешу немає, застосунок працює як раніше.
# CACHE_ENABLED=false -> кеш вимкнено глобально.
# CACHE_TTL_SECONDS -> скільки секунд запис живе в кеші.
CACHE_ENABLED = os.environ.get("CACHE_ENABLED", "true").lower() == "true"
CACHE_TTL = int(os.environ.get("CACHE_TTL_SECONDS", "45"))
REDIS_HOST = os.environ.get("REDIS_HOST")
_redis = None


def get_redis():
    """Один клієнт на процес. Короткі таймаути: якщо Redis недоступний,
    застосунок не зависає, а просто читає з бази."""
    global _redis
    if not REDIS_HOST:
        return None
    if _redis is None:
        _redis = redis.Redis(
            host=REDIS_HOST,
            port=int(os.environ.get("REDIS_PORT", "6379")),
            socket_connect_timeout=0.5,
            socket_timeout=0.5,
            decode_responses=True,
        )
    return _redis


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


# Показати ноутбуки: найновіші першими, не більше `limit` (за замовчуванням 100).
# Це найнавантаженіша операція читання, тому вона кешується (cache-aside):
#   1) дивимось у Redis; є запис і TTL не сплив -> віддаємо його (X-Cache: HIT)
#   2) немає -> читаємо з бази, кладемо в Redis на CACHE_TTL секунд (X-Cache: MISS)
# Заголовок запиту `Cache-Control: no-cache` пропускає кеш (потрібен для порівняльних тестів).
@app.get("/laptops")
def list_laptops(
    request: Request,
    response: Response,
    limit: int = Query(100, ge=1, le=1000),
):
    wants_cache = (
        CACHE_ENABLED
        and request.headers.get("cache-control", "").lower() != "no-cache"
    )
    r = get_redis() if wants_cache else None
    key = f"laptops:list:{limit}"

    if r is not None:
        try:
            cached = r.get(key)
            if cached is not None:
                response.headers["X-Cache"] = "HIT"
                return json.loads(cached)
        except redis.RedisError:
            r = None  # Redis недоступний: працюємо без кешу

    with get_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT * FROM laptop ORDER BY code DESC LIMIT %s", (limit,))
        rows = jsonable_encoder(cur.fetchall())  # Decimal -> число, щоб HIT і MISS були однакові

    if r is not None:
        try:
            r.setex(key, CACHE_TTL, json.dumps(rows))
        except redis.RedisError:
            pass
        response.headers["X-Cache"] = "MISS"
    else:
        response.headers["X-Cache"] = "BYPASS"
    return rows


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
