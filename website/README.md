# Сайт ROYALTIM (GitHub Pages)

Статический сайт в `website/` — не часть игры, собирается и деплоится отдельно.

## Что внутри

- `index.html` / `style.css` / `script.js` — одностраничный сайт: hero-секция, карточки 13 героев,
  живой топ игроков, блок "об игре", форма регистрации (email).
- `assets/heroes/*.jpg` — уменьшенные (640×640, ~30 КБ) версии концепт-артов героев из `art/concepts/`.
- `assets/favicon-32.png`, `assets/apple-touch-icon.png` — иконки, сделаны из концепта томата.

## Как это работает

- **Топ игроков** и счётчики "онлайн сейчас / зарегистрировано" тянутся живьём через `fetch()`
  с бэкенда игры: `GET http://159.194.255.184:8080/leaderboard?limit=20` и `GET /status`.
  Эти два эндпоинта публичные (без Bearer-токена) и отдают `Access-Control-Allow-Origin: *`,
  так что сайт может их вызывать из браузера с любого домена (в т.ч. `*.github.io`).
  Адрес бэкенда задан в `script.js` в константе `BACKEND` — поменяйте, если сервер переедет.
- **Форма регистрации** собирает email через [Formspree](https://formspree.io/) — у игры нет
  логина/пароля (аккаунт создаётся автоматически по device-key при первом запуске клиента),
  так что это лид-форма "пришлём ссылку на скачивание", а не настоящая регистрация в бэкенде игры.

## Перед первым деплоем

1. Зарегистрируйтесь на [formspree.io](https://formspree.io/), создайте форму, скопируйте её ID
   (вида `xyzabcde`).
2. В `index.html` замените `action="https://formspree.io/f/YOUR_FORM_ID"` на свой адрес формы.
3. Включите GitHub Pages: Settings → Pages → Source → **GitHub Actions**
   (workflow уже лежит в `.github/workflows/deploy-website.yml`, деплоит папку `website/`
   при пуше в `master`; отдельно настраивать Pages на ветку/папку не нужно).
4. Запушьте в `master` — сайт соберётся и опубликуется автоматически.
   Адрес будет вида `https://<username>.github.io/<repo>/`.

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
