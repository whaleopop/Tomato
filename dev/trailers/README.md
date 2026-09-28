# Трейлеры

Ролики для будущих игроков: герои и их способности, оружие, контейнеры и дроп, зона, ивенты на карте.
Это настоящая игра (те же персонажи, способности, лут и зона), только поставленная
сценарием `TrailerDirector.gd`: камера, титры на русском (из `ui/i18n/LocaleRu.gd`), всё в офлайне.

## Перезаписать

```powershell
powershell -ExecutionPolicy Bypass -File dev\trailers\record_all.ps1
powershell -ExecutionPolicy Bypass -File dev\trailers\record_all.ps1 -Reels zone        # один ролик
powershell -ExecutionPolicy Bypass -File dev\trailers\record_all.ps1 -Width 1280 -Height 720 -Fps 30   # быстрый черновик
```

Готовые файлы: `trailers\<ролик>.mp4` (H.264, папка не в git). Запись идёт через Movie Maker
Godot (`--write-movie`, фиксированный FPS, поэтому видео плавное, даже если рендер медленнее),
потом `ffmpeg` жмёт MJPEG в MP4. ffmpeg берётся из PATH или из `imageio-ffmpeg` в
`D:\royaltim-ai\venv` (`pip install imageio-ffmpeg`).

| Ролик | Что в нём |
|---|---|
| `heroes` | каждый герой: крупный план, способность на спарринг-партнёре, пассивка; общий строй |
| `weapons` | 5 стволов по мишеням, урон, скорострельность, дальность, обзор |
| `loot` | ящик, бочка, сундук, сбор предметов, сброс припасов с парашютом |
| `zone` | остров в горах, раскалённый край, огонь, поднимающиеся горы, горящий центр |
| `events` | метеоритный дождь, землетрясение, ночь и туман, разлив, раскол, грядка урожая, сброс в зону, сдвиг центра |

Новый герой, оружие или контейнер попадают в ролики сами (берутся из `CharacterRegistry`,
`RangedWeapon`, `LootContainer`). Язык титров - текущий язык игры (`GameSettings.language`).

## Общий трейлер

```powershell
D:\royaltim-ai\venv\Scripts\python.exe dev\trailers\highlights.py
```

Нарезает `trailers\trailer.mp4` (~55 с) из готовых роликов: лучшие моменты каждого, с переходами.
Шоты ищутся по меткам `MARK <имя> <секунда>`, которые `TrailerDirector.mark` пишет в
`trailers\<ролик>.log`, так что после перезаписи роликов нарезка сама попадает в нужные места.
Список шотов - `SHOTS` в начале скрипта.
