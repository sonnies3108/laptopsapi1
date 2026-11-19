# Навантажувальне тестування (k6)

Встановлення: `winget install k6` (Windows) або `brew install k6` (macOS).

## Запуск однією командою (з кореня репозиторію)

Linux / macOS / Git Bash:
```
k6 run -e BASE_URL=$(terraform -chdir=terraform output -raw app_url) --summary-export=loadtest/results/summary.json loadtest/laptops.js
```

PowerShell:
```
k6 run -e BASE_URL=$(terraform -chdir=terraform output -raw app_url) --summary-export=loadtest/results/summary.json loadtest/laptops.js
```

Параметри див. на початку `laptops.js` (`PEAK_VUS`, `RAMP_UP`, `HOLD`, `RAMP_DOWN`, `THINK`, `NO_CACHE`).
Короткий пробний прогін: `-e PEAK_VUS=10 -e RAMP_UP=20s -e HOLD=30s -e RAMP_DOWN=10s`.
Прогін без кешу: додати `-e NO_CACHE=1`.
