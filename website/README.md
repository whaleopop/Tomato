# Сайт ROYALTIM (GitHub Pages)

Статический сайт в `website/` — не часть игры, собирается и деплоится отдельно.

## Что внутри

- `index.html` / `style.css` / `script.js` — одностраничный сайт: hero-секция, карточки 13 героев,
  живой топ игроков, блок "об игре", аккаунт сайта (регистрация / вход / личный кабинет).
- `assets/heroes/*.jpg` — уменьшенные (640×640, ~30 КБ) версии концепт-артов героев из `art/concepts/`.
- `assets/favicon-32.png`, `assets/apple-touch-icon.png` — иконки, сделаны из концепта томата.

## Как это работает

- **Топ игроков** и счётчики "онлайн сейчас / зарегистрировано" тянутся живьём через `fetch()`
  с бэкенда игры: `GET http://159.194.255.184:8080/leaderboard?limit=20` и `GET /status`.
  Эти два эндпоинта публичные (без Bearer-токена) и отдают `Access-Control-Allow-Origin: *`,
  так что сайт может их вызывать из браузера с любого домена (в т.ч. `*.github.io`).
  Адрес бэкенда задан в `script.js` в константе `BACKEND` — поменяйте, если сервер переедет.
- **Аккаунт сайта** (регистрация / вход / личный кабинет) — отдельная система от игровых
  device-key аккаунтов (намеренно не связаны пока). Сайт зовёт `POST /web/register`,
  `POST /web/login`, `GET /web/me`, `POST /web/logout` на том же бэкенде; сессионный токен
  передаётся в заголовке `X-Web-Session` и хранится в `localStorage` браузера.
  После входа личный кабинет показывает email, дату регистрации и прямую ссылку на скачивание
  последнего релиза с GitHub (`.../releases/latest/download/Royaltim-windows.zip` — этот алиас
  GitHub всегда указывает на файл из самого свежего релиза, менять ничего не нужно при выходе
  новых версий).

## Перед первым деплоем

1. Включите GitHub Pages: Settings → Pages → Source → **GitHub Actions**
   (workflow уже лежит в `.github/workflows/deploy-website.yml`, деплоит папку `website/`
   при пуше в `master`; отдельно настраивать Pages на ветку/папку не нужно).
2. Запушьте в `master` — сайт соберётся и опубликуется автоматически.
   Адрес будет вида `https://<username>.github.io/<repo>/`.
3. На бэкенде (VPS) должны быть задеплоены эндпоинты `/web/register`, `/web/login`, `/web/me`,
   `/web/logout` — без них формы входа/регистрации будут показывать ошибку сети.

## Обновление героев/контента

- Список героев и их описания — в начале `script.js`, массив `HEROES`.
- Если добавляется новый герой в игру — положите его `art/concepts/<id>.png`,
  пересожмите в `website/assets/heroes/<id>.jpg` (640×640, JPEG q82 — см. команду ниже)
  и добавьте запись в `HEROES`.

```python
from PIL import Image
im = Image.open("art/concepts/<id>.png").convert("RGB").resize((640, 640), Image.LANCZOS)
im.save("website/assets/heroes/<id>.jpg", "JPEG", quality=82, optimize=True)
```
