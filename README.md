# Laptops API

REST API для керування таблицею ноутбуків (застосунок з курсу «Бази даних і знань»),
запакований у Docker і розгорнутий в AWS за допомогою Terraform.

**Публічна адреса:** http://laptops-alb-165695740.eu-north-1.elb.amazonaws.com
(Swagger UI: `/docs`, перевірка стану: `/health`).
Адреса працює, поки інфраструктура піднята. Після `terraform destroy` вона перестає існувати.

## Застосунок

- Мова і фреймворк: Python 3.12, FastAPI, сервер Uvicorn.
- База даних: MySQL 8.4 (локально в контейнері, в AWS це RDS), драйвер PyMySQL.
- Весь код застосунку в одному файлі `app.py`.
- Модель даних: ноутбук з полями `code`, `model`, `speed`, `ram`, `hd`, `price`, `screen`.

| Метод | Шлях | Опис |
|---|---|---|
| GET | `/health` | Перевірка, що сервіс живий (її використовує балансувальник) |
| GET | `/laptops` | Список усіх ноутбуків |
| POST | `/laptops` | Створення ноутбука |
| GET | `/laptops/{code}` | Один ноутбук за кодом |
| DELETE | `/laptops/{code}` | Видалення ноутбука |

## Структура репозиторію

```
.
├── app.py                  # код застосунку
├── requirements.txt        # залежності із зафіксованими версіями
├── Dockerfile              # збірка образу
├── compose.yaml            # локальний запуск: застосунок + MySQL
├── .env.example            # приклад змінних для compose (справжній .env у .gitignore)
├── .dockerignore
├── .gitignore
└── terraform/
    ├── main.tf             # провайдер AWS
    ├── variables.tf        # змінні проєкту
    ├── network.tf          # VPC, публічні та приватні підмережі, інтернет-шлюз
    ├── security.tf         # security groups: alb -> app -> db
    ├── alb.tf              # балансувальник, target group, listener
    ├── ecr.tf              # приватний реєстр образів
    ├── database.tf         # керована база RDS MySQL
    ├── secrets.tf          # пароль БД у SSM Parameter Store (SecureString)
    ├── ecs.tf              # ECS Fargate: кластер, task definition, сервіс
    ├── outputs.tf
    ├── terraform.tfvars.example   # приклад змінних (справжній terraform.tfvars у .gitignore)
    └── github_oidc.tf.disabled    # конфігурація OIDC для GitHub Actions, вимкнена (див. нижче)
```

## Локальний запуск (завдання 1)

1. Скопіювати `.env.example` у `.env` і задати значення (пароль, ім'я бази, користувача).
2. Виконати:

```
docker compose up --build
```

3. Застосунок: http://localhost:8000/docs

Особливості:

- Dockerfile: базовий образ `python:3.12-slim-bookworm` (версія зафіксована, не `latest`);
  спершу копіюється `requirements.txt` і встановлюються залежності, потім копіюється код
  (так шар із залежностями кешується); процес працює від звичайного користувача `appuser`, не від root.
- `compose.yaml` піднімає застосунок разом із MySQL 8.4. Дані бази лежать у volume `db_data`
  і переживають `docker compose down`. Застосунок стартує лише після того, як база пройшла healthcheck.
- Параметри підключення до бази передаються через змінні середовища, у коді їх немає.

## Інфраструктура в AWS (завдання 2, 3, 4)

Регіон: `eu-north-1` (Стокгольм). Усе описано в Terraform.

```
Інтернет
   |
   v
Application Load Balancer (порт 80, публічні підмережі)
   |   health check: GET /health
   v
ECS Fargate (порт 8000, security group app)
   |
   v
RDS MySQL 8.4 (порт 3306, приватні підмережі, без публічної адреси)
```

- **Мережа:** власна VPC, дві публічні підмережі (балансувальник і контейнери) і дві приватні (база).
  Маршрут в інтернет-шлюз є лише у публічних підмережах.
- **Security groups** ланцюжком, без IP-діапазонів усередині: інтернет пускається лише на порт 80
  балансувальника; на порт 8000 застосунку пускається лише група балансувальника;
  на порт 3306 бази пускається лише група застосунку.
- **База:** RDS MySQL 8.4, `publicly_accessible = false`, шифрування сховища, резервні копії на 1 день.
  Multi-AZ вимкнено, щоб заощадити кредит.
- **Секрети:** пароль бази лежить у SSM Parameter Store як `SecureString` і передається контейнеру через
  блок `secrets` у task definition, а не відкритим текстом у змінних середовища.
  Значення береться з `terraform.tfvars`, який у `.gitignore`.
- **Балансувальник:** ALB, target group з health check на `/health` (інтервал 30 с, здоровим вважається
  після двох успішних перевірок).
- **Реєстр:** ECR `laptops-api` зі скануванням образів при завантаженні; `force_delete = true`,
  щоб `terraform destroy` видаляв реєстр разом з образами.
- **Логи:** CloudWatch, група `/ecs/laptops-api`, зберігаються 7 днів.

### Компроміс: публічна адреса контейнерів

Контейнери Fargate стоять у публічних підмережах і мають публічну IP. Це свідоме рішення:
приватна підмережа вимагала б NAT-шлюзу, який коштує окремо, інакше контейнер не зміг би завантажити
образ з ECR. На практиці напряму до контейнера не достукатись: його security group приймає порт 8000
лише від групи балансувальника.

## Розгортання

Потрібні: AWS CLI, Terraform, Docker, вхід в AWS (`aws login`).

1. Створити файл `terraform/terraform.tfvars` за зразком `terraform.tfvars.example` і задати пароль бази.
2. Із папки `terraform`:

```
terraform init
terraform apply -target=aws_ecr_repository.app
```

3. Зібрати образ і залити його в реєстр з тегом `v1`
   (вхід у реєстр: `aws ecr get-login-password ... | docker login ...`):

```
docker build -t <ID_акаунта>.dkr.ecr.eu-north-1.amazonaws.com/laptops-api:v1 .
docker push <ID_акаунта>.dkr.ecr.eu-north-1.amazonaws.com/laptops-api:v1
```

4. Створити решту інфраструктури:

```
terraform apply
terraform output app_url
```

Образ потрібно залити до основного `apply`, бо сервіс ECS стартує з образом `v1`: у порожньому реєстрі
контейнер не запуститься.

Видалення всього:

```
terraform destroy
```

## Автоматичний деплой (завдання 5): не реалізовано

Файл `terraform/github_oidc.tf.disabled` містить конфігурацію OIDC-провайдера GitHub і ролі для
GitHub Actions. Він вимкнений, бо створення OIDC-провайдера в цьому акаунті неможливе: AWS повертає
`AccessDenied ... with an explicit deny in a service control policy` на дію `iam:CreateOpenIDConnectProvider`.
Акаунт створено через спрощену реєстрацію AWS («Sign up for AWS (new)»), де політики організації
(SCP) керує AWS, і власні змінити не можна. Використання довговічних ключів доступу замість OIDC
суперечить умовам лабораторної, тому workflow не додано.
