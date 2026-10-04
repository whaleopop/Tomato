# Онлайн: бэкенд, подбор матчей, выделенный сервер

## Как это устроено

```
игра (Online.gd)  ──HTTP :8080──►  бэкенд royaltim_backend.py  ──►  SQLite (аккаунты, профили, награды)
       │                                   │ запускает по процессу на матч
       └──────────── UDP 7777-7786 ──────► игровой сервер (DedicatedServer.gd --match=…)
                                           └─ после матча: монеты и опыт каждого → бэкенд
```

- **Аккаунт**: ключ устройства в `user://account.cfg`. При первом входе сервер создаёт аккаунт, потом
  онбординг (ник и два стартовых героя). Профиль (монеты, покупки, что надето, мастерство) хранится
  в базе на сервере, игра держит его копию (`PlayerProfile.online`). Покупки и экипировка проверяются
  сервером по ценам из игры (`catalog.json`, выгружается `export_catalog.gd` при каждой выкладке).
- **Подбор**: ИГРАТЬ → режим → герой → «Поиск матча». Матч собирается, когда набралось максимум
  игроков режима или минимум уже ждёт `fill` секунд (`MODES` в бэкенде: br 2–12, survivors 1–4,
  ctf/koth 2–8). Бэкенд запускает игровой сервер на свободном порту и выдаёт каждому билет.
  Пускают только по билету, ник и герой берутся из билета.
- **Высадка**: 45 с на выбор точки. Кто не выбрал, высаживается в случайную свободную точку.
  Если готовы все, матч стартует раньше.
- **Награды** считает игровой сервер по тем же формулам, что и экран результатов
  (`PlayerProfile.match_reward`, `Mastery`), а бэкенд записывает их в базу один раз на игрока за матч.
  Без связи с сервером игра работает офлайн с локальным профилем: тренировка и «Своя игра» по LAN.
- Одновременно не больше 3 матчей (`--max-matches`, 2 ГБ RAM; матч занимает ~200–400 МБ).

## Сервер 159.194.255.184

Выкладка из корня проекта (сборка, каталог, загрузка, перезапуск):

```powershell
powershell -ExecutionPolicy Bypass -File tools\server\deploy.ps1 -Server 159.194.255.184
```

Клиент и сервер должны быть **одной версии** (`application/config/version` в project.godot):
бэкенд не пускает старую игру. После изменений поднимите версию, выложите сервер и раздайте новую сборку.

На сервере (`ssh root@159.194.255.184`):

```bash
curl -s localhost:8080/status                     # онлайн, очереди, матчи
journalctl -u royaltim-backend -f                 # лог бэкенда
ls /opt/royaltim/data/logs/                       # лог каждого матча
systemctl restart royaltim-backend                # перезапуск (идущие матчи прервутся)
cp /opt/royaltim/data/royaltim.db ~/backup.db     # резервная копия базы
```

Файлы: `/opt/royaltim/` (бэкенд, `catalog.json`, `royaltim_server`), база и ключ игровых серверов
в `/opt/royaltim/data/`. Открыты TCP 8080 и UDP 7777–7786.

## Без бэкенда (один сервер, лобби по кругу)

```powershell
powershell -ExecutionPolicy Bypass -File tools\server\deploy.ps1 -Server <IP> -Standalone [-Arch arm64]
```

Ставит `royaltim.service`: один игровой сервер на 7777, игроки заходят через «Подключиться».
Параметры после `--`: `--server`, `--port=N`, `--mode=br|survivors|ctf|koth`, `--min-players=N`.
Локальная проверка:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . -- --server --port=7777 --mode=br --min-players=1
```

Бэкенд локально: `python tools/server/backend/royaltim_backend.py --port 8099 --server-bin <скрипт, запускающий godot --path проекта>`,
клиент с `-- --backend=http://127.0.0.1:8099 --account=test1` (`--account` даёт второй аккаунт на том же ПК).

## Oracle Cloud Always Free (ARM)

Если регистрация доступна: https://signup.cloud.oracle.com/, образ Ubuntu (aarch64), VM.Standard.A1.Flex,
в Security List открыть TCP 8080 и UDP 7777–7786, выкладка с `-Arch arm64 -User ubuntu -Key <ключ>`.
