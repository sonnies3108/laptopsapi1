// Навантажувальний сценарій: профіль "мало записів, багато читань" (1 запис : 9 читань).
//
// Запуск однією командою (з кореня репозиторію):
//   k6 run -e BASE_URL=http://<адреса-ALB> --summary-export=loadtest/results/summary.json loadtest/laptops.js
//
// Параметри (змінні середовища, -e ІМ'Я=значення):
//   BASE_URL   адреса сервісу (обов'язково), напр. http://laptops-alb-123.eu-north-1.elb.amazonaws.com
//   PEAK_VUS   кількість віртуальних користувачів на сталому навантаженні (за замовчуванням 30; підбери під свій сервіс)
//   RAMP_UP    тривалість наростання      (за замовчуванням 150s = 2,5 хв)
//   HOLD       тривалість сталого етапу   (за замовчуванням 5m)
//   RAMP_DOWN  тривалість спаду           (за замовчуванням 2m)
//   THINK      пауза між запитами, с      (за замовчуванням 0.2)
//   NO_CACHE   1 -> додає Cache-Control: no-cache, сервіс пропускає кеш (для порівняння)

import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL;
const PEAK_VUS = parseInt(__ENV.PEAK_VUS || '30');
const RAMP_UP = __ENV.RAMP_UP || '150s';
const HOLD = __ENV.HOLD || '5m';
const RAMP_DOWN = __ENV.RAMP_DOWN || '2m';
const THINK = parseFloat(__ENV.THINK || '0.2');
const NO_CACHE = __ENV.NO_CACHE === '1';

export const options = {
  stages: [
    { duration: RAMP_UP, target: PEAK_VUS },   // 1) наростання від 0 до N
    { duration: HOLD, target: PEAK_VUS },      // 2) стале навантаження
    { duration: RAMP_DOWN, target: 0 },        // 3) спад до 0
  ],
  // p50 = med; додаємо p99, якого немає у звіті за замовчуванням
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  thresholds: {
    http_req_failed: ['rate<0.01'],      // помилок менше 1%
    http_req_duration: ['p(95)<1000'],   // p95 менше 1 с
  },
};

const HEADERS = { 'Content-Type': 'application/json' };
if (NO_CACHE) HEADERS['Cache-Control'] = 'no-cache';

// Для відомих 404 (випадковий старий id) не рахувати як помилку
const okOr404 = http.expectedStatuses(200, 404);

export function setup() {
  if (!BASE_URL) throw new Error('Задай BASE_URL: -e BASE_URL=http://...');
  const r = http.get(`${BASE_URL}/health`);
  if (r.status !== 200) throw new Error(`/health повернув ${r.status}`);
}

function randInt(a, b) {
  return Math.floor(Math.random() * (b - a + 1)) + a;
}

export default function () {
  // ---- 1 запис: створюємо ноутбук ----
  const payload = JSON.stringify({
    model: `Model-${__VU}-${__ITER}`,
    speed: randInt(1500, 4500),
    ram: [8, 16, 32][randInt(0, 2)],
    hd: randInt(256, 2000) / 1.0,
    price: randInt(500, 3000),
    screen: randInt(13, 17),
  });
  const created = http.post(`${BASE_URL}/laptops`, payload, {
    headers: HEADERS,
    tags: { name: 'POST /laptops' },
  });
  const ok = check(created, { 'створено (201)': (r) => r.status === 201 });
  if (!ok) { sleep(THINK); return; }
  const code = created.json('code');
  sleep(THINK);

  // ---- 9 читань ----
  // 4 x список (найнавантаженіша операція читання, саме її кешуємо)
  for (let i = 0; i < 4; i++) {
    const r = http.get(`${BASE_URL}/laptops`, { headers: HEADERS, tags: { name: 'GET /laptops' } });
    check(r, { 'список (200)': (x) => x.status === 200 });
    sleep(THINK);
  }
  // 3 x щойно створений ноутбук за id
  for (let i = 0; i < 3; i++) {
    const r = http.get(`${BASE_URL}/laptops/${code}`, { headers: HEADERS, tags: { name: 'GET /laptops/{code}' } });
    check(r, { 'щойно створений (200)': (x) => x.status === 200 });
    sleep(THINK);
  }
  // 2 x випадковий із недавніх (імітація перегляду чужих записів)
  for (let i = 0; i < 2; i++) {
    const id = Math.max(1, code - randInt(0, 50));
    const r = http.get(`${BASE_URL}/laptops/${id}`, {
      headers: HEADERS,
      tags: { name: 'GET /laptops/{code}' },
      responseCallback: okOr404,
    });
    check(r, { 'випадковий (200/404)': (x) => x.status === 200 || x.status === 404 });
    sleep(THINK);
  }
}
