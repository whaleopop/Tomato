// ROYALTIM-3 website — hero grid, live leaderboard/status from the backend, nav + signup form.

const BACKEND = "http://159.194.255.184:8080";

const HEROES = [
  { id: "tomato", name: "Томат", desc: "Мощный боец ближнего боя с сокрушительными ударами." },
  { id: "carrot", name: "Морковь", desc: "Быстрый оранжевый боец с точными атаками." },
  { id: "pumpkin", name: "Тыква", desc: "Массивный танк с толстой защитной коркой." },
  { id: "corn", name: "Кукуруза", desc: "Специалист дальнего боя — стреляет зёрнами." },
  { id: "broccoli", name: "Брокколи", desc: "Саппорт с лечением и защитой союзников." },
  { id: "beet", name: "Свёкла", desc: "Отважный красный воин с сочной живучестью." },
  { id: "pepper", name: "Перец", desc: "Вспыльчивый болгарский перец с острыми атаками." },
  { id: "apple", name: "Яблоко", desc: "Яростный боец, который держит всех на расстоянии." },
  { id: "lemon", name: "Лимон", desc: "Маленький, быстрый и очень кислый — оставляет ожог." },
  { id: "grape", name: "Виноград", desc: "Целая гроздь проблем: стреляет виноградинами." },
  { id: "watermelon", name: "Арбуз", desc: "Медленный тяжеловес с самой толстой коркой на острове." },
  { id: "pineapple", name: "Ананас", desc: "Угрюмый бугай в колючей броне. Приземляется короной вперёд." },
  { id: "banana", name: "Банан", desc: "Шустрый, скользкий и всегда готов подкинуть кожуру под ноги." },
];

function el(tag, cls, html) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html !== undefined) e.innerHTML = html;
  return e;
}

function renderHeroes() {
  const grid = document.getElementById("hero-grid");
  if (!grid) return;
  const frag = document.createDocumentFragment();
  for (const h of HEROES) {
    const card = el("div", "hero-card");
    const imgWrap = el("div", "hero-card-img-wrap");
    const img = document.createElement("img");
    img.src = `assets/heroes/${h.id}.jpg`;
    img.alt = h.name;
    img.loading = "lazy";
    imgWrap.appendChild(img);
    const body = el("div", "hero-card-body");
    body.appendChild(el("div", "hero-card-name", h.name));
    body.appendChild(el("div", "hero-card-desc", h.desc));
    card.appendChild(imgWrap);
    card.appendChild(body);
    frag.appendChild(card);
  }
  grid.appendChild(frag);
}

function heroNameRu(id) {
  const h = HEROES.find((x) => x.id === id);
  return h ? h.name : id || "—";
}

async function loadStatus() {
  const onlineEl = document.getElementById("stat-online");
  const regEl = document.getElementById("stat-registered");
  try {
    const res = await fetch(`${BACKEND}/status`, { mode: "cors" });
    if (!res.ok) throw new Error("bad status");
    const data = await res.json();
    if (onlineEl) onlineEl.textContent = data.online ?? "—";
    if (regEl) regEl.textContent = data.registered ?? "—";
  } catch (e) {
    if (onlineEl) onlineEl.textContent = "?";
    if (regEl) regEl.textContent = "?";
  }
}

async function loadLeaderboard() {
  const body = document.getElementById("board-body");
  if (!body) return;
  try {
    const res = await fetch(`${BACKEND}/leaderboard?limit=20`, { mode: "cors" });
    if (!res.ok) throw new Error("bad response");
    const data = await res.json();
    const players = data.players || [];
    if (!players.length) {
      body.innerHTML = '<div class="board-empty">Пока никто не попал в рейтинг — будь первым!</div>';
      return;
    }
    body.innerHTML = "";
    const frag = document.createDocumentFragment();
    players.forEach((pl, i) => {
      const row = el("div", "board-row");

      const rank = el("span", `col-rank${i < 3 ? " rank-" + (i + 1) : ""}`, String(i + 1));

      const playerCol = el("span", "col-player");
      const avatar = document.createElement("img");
      avatar.className = "player-avatar";
      avatar.loading = "lazy";
      avatar.alt = "";
      avatar.src = `assets/heroes/${pl.hero}.jpg`;
      avatar.onerror = () => { avatar.style.visibility = "hidden"; };
      const name = el("span", "player-name", escapeHtml(pl.nickname || "Игрок"));
      playerCol.appendChild(avatar);
      playerCol.appendChild(name);

      const heroCol = el("span", "col-hero", heroNameRu(pl.hero));
      const levelCol = el("span", "col-level", "ур. " + (pl.level ?? 1));
      const coinsCol = el("span", "col-coins", `🪙 ${formatNum(pl.coins ?? 0)}`);

      row.appendChild(rank);
      row.appendChild(playerCol);
      row.appendChild(heroCol);
      row.appendChild(levelCol);
      row.appendChild(coinsCol);
      frag.appendChild(row);
    });
    body.appendChild(frag);
  } catch (e) {
    body.innerHTML = '<div class="board-error">Не удалось загрузить рейтинг — сервер недоступен.</div>';
  }
}

function formatNum(n) {
  return new Intl.NumberFormat("ru-RU").format(n);
}

function escapeHtml(s) {
  const d = document.createElement("div");
  d.textContent = s;
  return d.innerHTML;
}

function setupNav() {
  const burger = document.getElementById("burger");
  const nav = document.querySelector(".nav");
  if (!burger || !nav) return;
  burger.addEventListener("click", () => nav.classList.toggle("open"));
  nav.querySelectorAll("a").forEach((a) => a.addEventListener("click", () => nav.classList.remove("open")));
}

function setupSignupForm() {
  const form = document.getElementById("signup-form");
  const note = document.getElementById("signup-note");
  if (!form || !note) return;
  const placeholderAction = form.getAttribute("action") || "";
  form.addEventListener("submit", async (ev) => {
    if (placeholderAction.includes("YOUR_FORM_ID")) {
      ev.preventDefault();
      note.textContent = "Форма ещё не подключена — впишите свой Formspree ID в action формы.";
      note.className = "signup-note err";
      return;
    }
    ev.preventDefault();
    note.textContent = "Отправляем…";
    note.className = "signup-note";
    try {
      const res = await fetch(form.action, {
        method: "POST",
        body: new FormData(form),
        headers: { Accept: "application/json" },
      });
      if (res.ok) {
        note.textContent = "Готово! Мы пришлём ссылку на игру на твою почту.";
        note.className = "signup-note ok";
        form.reset();
      } else {
        note.textContent = "Не получилось отправить — попробуй ещё раз чуть позже.";
        note.className = "signup-note err";
      }
    } catch (e) {
      note.textContent = "Не получилось отправить — проверь соединение.";
      note.className = "signup-note err";
    }
  });
}

renderHeroes();
loadStatus();
loadLeaderboard();
setupNav();
setupSignupForm();
