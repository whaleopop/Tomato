// ROYALTIM-3 website — hero grid, live leaderboard/status from the backend, nav + web account auth.

const BACKEND = "https://159-194-255-184.sslip.io";
const SESSION_KEY = "royaltim_web_session"; // localStorage key holding the session token
const DOWNLOAD_URL = "https://github.com/whaleopop/Tomato/releases/latest/download/Royaltim-windows.zip";

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

// ---------- web account auth (separate from the game's device-key accounts) ----------

function getSession() {
  try {
    return localStorage.getItem(SESSION_KEY) || "";
  } catch (e) {
    return "";
  }
}

function setSession(token) {
  try {
    if (token) localStorage.setItem(SESSION_KEY, token);
    else localStorage.removeItem(SESSION_KEY);
  } catch (e) {
    // private window / blocked storage — session just won't persist across reloads
  }
}

function setAuthNote(text, kind) {
  const note = document.getElementById("auth-note");
  if (!note) return;
  note.textContent = text;
  note.className = "signup-note" + (kind ? " " + kind : "");
}

function setupAuthTabs() {
  const tabs = document.querySelectorAll(".auth-tab");
  const loginForm = document.getElementById("login-form");
  const registerForm = document.getElementById("register-form");
  if (!tabs.length || !loginForm || !registerForm) return;
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      tabs.forEach((t) => t.classList.remove("active"));
      tab.classList.add("active");
      const isLogin = tab.dataset.tab === "login";
      loginForm.hidden = !isLogin;
      registerForm.hidden = isLogin;
      setAuthNote("", "");
    });
  });
}

// Server error `code` -> Russian message (server text itself stays English, per the API contract).
const AUTH_ERRORS = {
  bad_email: "Неверный email",
  bad_password: "Пароль: от 8 до 128 символов",
  email_taken: "Этот email уже зарегистрирован",
  bad_credentials: "Неверный email или пароль",
  busy: "Сервер занят, попробуй через минуту",
  not_logged_in: "Сессия истекла, войди снова",
};

function authErrorMessage(data, retryAfter) {
  if (data.code === "throttled") {
    const mins = retryAfter ? Math.ceil(retryAfter / 60) : null;
    return mins ? `Слишком много попыток, подожди ${mins} мин.` : "Слишком много попыток, попробуй позже";
  }
  return AUTH_ERRORS[data.code] || data.error || "Не получилось выполнить запрос";
}

async function webApi(path, body) {
  const res = await fetch(`${BACKEND}${path}`, {
    method: "POST",
    mode: "cors",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body || {}),
  });
  let data = {};
  try {
    data = await res.json();
  } catch (e) {
    throw new Error("Сервер не отвечает — попробуй позже");
  }
  if (!res.ok || data.ok === false) {
    throw new Error(authErrorMessage(data, data.retry_after));
  }
  return data;
}

async function fetchMe(token) {
  const res = await fetch(`${BACKEND}/web/me`, {
    mode: "cors",
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error("session invalid");
  return res.json();
}

function showDashboard(profile) {
  const authBlock = document.getElementById("auth-block");
  const dashBlock = document.getElementById("dashboard-block");
  const emailEl = document.getElementById("dash-email");
  const createdEl = document.getElementById("dash-created");
  const downloadEl = document.getElementById("dash-download");
  if (!authBlock || !dashBlock) return;
  authBlock.hidden = true;
  dashBlock.hidden = false;
  if (emailEl) emailEl.textContent = profile.email || "—";
  if (createdEl && profile.created) {
    const d = new Date(profile.created * 1000);
    createdEl.textContent = new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "long", year: "numeric" }).format(d);
  }
  if (downloadEl) downloadEl.href = DOWNLOAD_URL;
  const navCta = document.getElementById("nav-cta");
  if (navCta) navCta.textContent = "Кабинет";
}

function showAuthForms() {
  const authBlock = document.getElementById("auth-block");
  const dashBlock = document.getElementById("dashboard-block");
  if (!authBlock || !dashBlock) return;
  authBlock.hidden = false;
  dashBlock.hidden = true;
  const navCta = document.getElementById("nav-cta");
  if (navCta) navCta.textContent = "Играть";
}

async function restoreSession() {
  const token = getSession();
  if (!token) return;
  try {
    const data = await fetchMe(token);
    showDashboard(data);
  } catch (e) {
    setSession("");
  }
}

function setupAuthForms() {
  const loginForm = document.getElementById("login-form");
  const registerForm = document.getElementById("register-form");
  const logoutBtn = document.getElementById("dash-logout");

  if (loginForm) {
    loginForm.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const email = document.getElementById("login-email").value.trim();
      const password = document.getElementById("login-password").value;
      setAuthNote("Входим…", "");
      try {
        const data = await webApi("/web/login", { email, password });
        setSession(data.token);
        setAuthNote("", "");
        loginForm.reset();
        showDashboard(data);
      } catch (e) {
        setAuthNote(e.message, "err");
      }
    });
  }

  if (registerForm) {
    registerForm.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const email = document.getElementById("register-email").value.trim();
      const password = document.getElementById("register-password").value;
      setAuthNote("Создаём аккаунт…", "");
      try {
        const data = await webApi("/web/register", { email, password });
        setSession(data.token);
        setAuthNote("", "");
        registerForm.reset();
        showDashboard(data);
      } catch (e) {
        setAuthNote(e.message, "err");
      }
    });
  }

  if (logoutBtn) {
    logoutBtn.addEventListener("click", async () => {
      const token = getSession();
      setSession("");
      showAuthForms();
      if (token) {
        try {
          await fetch(`${BACKEND}/web/logout`, {
            method: "POST",
            mode: "cors",
            headers: { Authorization: `Bearer ${token}` },
          });
        } catch (e) {
          // already logged out locally, a failed server call doesn't matter here
        }
      }
    });
  }
}

renderHeroes();
loadStatus();
loadLeaderboard();
setupNav();
setupAuthTabs();
setupAuthForms();
restoreSession();
