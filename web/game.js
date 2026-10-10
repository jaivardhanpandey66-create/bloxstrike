/* BLOXSTRIKE: Neon Arena — browser edition
 * Top-down neon shooter with required login (localStorage demo auth).
 * No dependencies, no build step.
 */
(() => {
  "use strict";

  // ========================================================================
  // Config — tweak anything here
  // ========================================================================
  const CONFIG = {
    world: { w: 2000, h: 1500 },
    player: {
      radius: 16,
      speed: 260,          // px / sec
      maxHealth: 100,
      color: "#42e0ff",
    },
    weapon: {
      damage: 26,
      fireRate: 0.085,     // seconds between shots
      spread: 0.04,        // radians
      bulletSpeed: 1200,
      bulletLife: 0.9,
      magSize: 30,
      reserve: 180,
      reloadTime: 1.5,
      knockback: 40,
    },
    enemy: {
      baseHealth: 60,
      baseSpeed: 95,
      radius: 16,
      damage: 12,
      attackCooldown: 0.8,
      healthGrowth: 0.15,  // per wave
      speedGrowth: 0.05,
    },
    wave: {
      baseCount: 4,
      countGrowth: 1.6,
      breakTime: 2.2,
    },
    colors: {
      bg: "#05070d",
      grid: "rgba(66,224,255,0.06)",
      wall: "#141b2c",
      wallEdge: "#42e0ff",
      enemy: "#ff4d5e",
      enemyEye: "#ffd24d",
      bullet: "#8affc1",
      health: "#50e678",
      xp: "#42e0ff",
    },
  };

  // ========================================================================
  // Auth (localStorage demo — NOT server-side)
  // ========================================================================
  const Auth = (() => {
    const USERS_KEY = "bloxstrike_users";
    const SESSION_KEY = "bloxstrike_session";

    const hash = (str) => {
      let h = 5381;
      for (let i = 0; i < str.length; i++) h = ((h << 5) + h + str.charCodeAt(i)) | 0;
      return (h >>> 0).toString(16);
    };

    const loadUsers = () => {
      try {
        return JSON.parse(localStorage.getItem(USERS_KEY)) || {};
      } catch {
        return {};
      }
    };
    const saveUsers = (users) =>
      localStorage.setItem(USERS_KEY, JSON.stringify(users));

    return {
      register(username, password) {
        username = username.trim();
        if (username.length < 3) return { ok: false, msg: "Username must be at least 3 characters." };
        if (password.length < 4) return { ok: false, msg: "Password must be at least 4 characters." };
        const users = loadUsers();
        const key = username.toLowerCase();
        if (users[key]) return { ok: false, msg: "That username is already taken." };
        users[key] = { name: username, pass: hash(password), best: 0 };
        saveUsers(users);
        localStorage.setItem(SESSION_KEY, key);
        return { ok: true, user: users[key] };
      },

      login(username, password) {
        username = username.trim();
        const users = loadUsers();
        const key = username.toLowerCase();
        const user = users[key];
        if (!user) return { ok: false, msg: "No account with that username." };
        if (user.pass !== hash(password)) return { ok: false, msg: "Incorrect password." };
        localStorage.setItem(SESSION_KEY, key);
        return { ok: true, user };
      },

      session() {
        const key = localStorage.getItem(SESSION_KEY);
        if (!key) return null;
        return loadUsers()[key] || null;
      },

      logout() {
        localStorage.removeItem(SESSION_KEY);
      },

      setBest(username, score) {
        const users = loadUsers();
        const key = username.toLowerCase();
        if (!users[key]) return;
        users[key].best = Math.max(users[key].best || 0, score);
        saveUsers(users);
      },

      best(username) {
        const users = loadUsers();
        const u = users[username.toLowerCase()];
        return u ? u.best || 0 : 0;
      },
    };
  })();

  // ========================================================================
  // DOM
  // ========================================================================
  const $ = (id) => document.getElementById(id);
  const authScreen = $("auth-screen");
  const gameScreen = $("game-screen");
  const canvas = $("game");
  const ctx = canvas.getContext("2d");
  const crosshair = $("crosshair");

  let mode = "login";
  let currentUser = null;

  // --- auth UI ---
  const tabLogin = $("tab-login");
  const tabRegister = $("tab-register");
  const authSubmit = $("auth-submit");
  const authMsg = $("auth-msg");

  function setMode(m) {
    mode = m;
    tabLogin.classList.toggle("active", m === "login");
    tabRegister.classList.toggle("active", m === "register");
    authSubmit.textContent = m === "login" ? "Login" : "Create Account";
    authMsg.textContent = "";
    authMsg.className = "msg";
  }
  tabLogin.onclick = () => setMode("login");
  tabRegister.onclick = () => setMode("register");

  $("auth-form").addEventListener("submit", (e) => {
    e.preventDefault();
    const username = $("username").value;
    const password = $("password").value;
    const res =
      mode === "login"
        ? Auth.login(username, password)
        : Auth.register(username, password);

    if (!res.ok) {
      authMsg.textContent = res.msg;
      authMsg.className = "msg error";
      return;
    }
    authMsg.textContent = mode === "login" ? "Welcome back!" : "Account created!";
    authMsg.className = "msg ok";
    startSession(res.user);
  });

  // --- session ---
  function startSession(user) {
    currentUser = user;
    authScreen.classList.add("hidden");
    gameScreen.classList.remove("hidden");
    $("hud-user").textContent = user.name;
    $("hud-best").textContent = Auth.best(user.name);
    hideOverlays();
    resize();
    Game.start();
  }

  function endSession() {
    Game.stop();
    Auth.logout();
    currentUser = null;
    gameScreen.classList.add("hidden");
    authScreen.classList.remove("hidden");
    $("password").value = "";
    setMode("login");
  }

  $("logout-btn").onclick = endSession;
  $("quit-btn").onclick = endSession;
  $("menu-btn").onclick = endSession;

  // ========================================================================
  // Input
  // ========================================================================
  const keys = {};
  const mouse = { x: window.innerWidth / 2, y: window.innerHeight / 2, down: false };

  window.addEventListener("keydown", (e) => {
    keys[e.key.toLowerCase()] = true;
    if (e.key === "Escape" && Game.running) Game.togglePause();
    if (e.key.toLowerCase() === "r" && Game.running) Game.reload();
    if ([" ", "arrowup", "arrowdown", "arrowleft", "arrowright"].includes(e.key.toLowerCase()))
      e.preventDefault();
  });
  window.addEventListener("keyup", (e) => (keys[e.key.toLowerCase()] = false));

  canvas.addEventListener("mousemove", (e) => {
    mouse.x = e.clientX;
    mouse.y = e.clientY;
    crosshair.style.left = e.clientX + "px";
    crosshair.style.top = e.clientY + "px";
  });
  canvas.addEventListener("mousedown", (e) => {
    if (e.button === 0) mouse.down = true;
  });
  window.addEventListener("mouseup", (e) => {
    if (e.button === 0) mouse.down = false;
  });
  canvas.addEventListener("contextmenu", (e) => e.preventDefault());

  // ========================================================================
  // Canvas sizing
  // ========================================================================
  let view = { w: window.innerWidth, h: window.innerHeight };
  function resize() {
    const dpr = window.devicePixelRatio || 1;
    view.w = window.innerWidth;
    view.h = window.innerHeight;
    canvas.width = view.w * dpr;
    canvas.height = view.h * dpr;
    canvas.style.width = view.w + "px";
    canvas.style.height = view.h + "px";
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  window.addEventListener("resize", resize);

  // ========================================================================
  // Game
  // ========================================================================
  const Game = (() => {
    let raf = null;
    let last = 0;
    let accumulator = 0;
    const FIXED = 1 / 120; // fixed physics step

    const state = {
      running: false,
      paused: false,
      over: false,
      player: null,
      bullets: [],
      enemies: [],
      particles: [],
      pickups: [],
      damageTexts: [],
      score: 0,
      wave: 0,
      waveTimer: 0,
      spawning: false,
      shake: 0,
      time: 0,
    };

    // ---- helpers ----
    const rand = (a, b) => a + Math.random() * (b - a);
    const dist2 = (ax, ay, bx, by) => (ax - bx) ** 2 + (ay - by) ** 2;

    function newPlayer() {
      return {
        x: CONFIG.world.w / 2,
        y: CONFIG.world.h / 2,
        r: CONFIG.player.radius,
        health: CONFIG.player.maxHealth,
        maxHealth: CONFIG.player.maxHealth,
        ammo: CONFIG.weapon.magSize,
        reserve: CONFIG.weapon.reserve,
        reloading: false,
        reloadT: 0,
        fireT: 0,
        hitFlash: 0,
        recoil: 0,
        angle: 0,
      };
    }

    function reset() {
      state.player = newPlayer();
      state.bullets = [];
      state.enemies = [];
      state.particles = [];
      state.pickups = [];
      state.damageTexts = [];
      state.score = 0;
      state.wave = 0;
      state.waveTimer = 1.2;
      state.spawning = true;
      state.shake = 0;
      state.time = 0;
      state.over = false;
      state.paused = false;
      updateHud();
    }

    // ---- waves ----
    function startNextWave() {
      state.wave++;
      state.spawning = false;
      const count = Math.round(
        CONFIG.wave.baseCount + (state.wave - 1) * CONFIG.wave.countGrowth
      );
      for (let i = 0; i < count; i++) spawnEnemy(i * 0.12);
      updateHud();
    }

    function spawnEnemy(delay = 0) {
      const w = CONFIG.world.w;
      const h = CONFIG.world.h;
      let x, y;
      const side = Math.floor(rand(0, 4));
      const pad = 60;
      if (side === 0) { x = rand(pad, w - pad); y = pad; }
      else if (side === 1) { x = w - pad; y = rand(pad, h - pad); }
      else if (side === 2) { x = rand(pad, w - pad); y = h - pad; }
      else { x = pad; y = rand(pad, h - pad); }

      const hp = Math.round(
        CONFIG.enemy.baseHealth * (1 + (state.wave - 1) * CONFIG.enemy.healthGrowth)
      );
      const enemy = {
        x, y,
        r: CONFIG.enemy.radius,
        health: hp,
        maxHealth: hp,
        speed: CONFIG.enemy.baseSpeed * (1 + (state.wave - 1) * CONFIG.enemy.speedGrowth),
        attackT: 0,
        hitT: 0,
        spawn: delay,
        wobble: rand(0, Math.PI * 2),
      };
      state.enemies.push(enemy);
    }

    // ---- shooting ----
    function fire() {
      const p = state.player;
      if (p.reloading || p.fireT > 0) return;
      if (p.ammo <= 0) { reload(); return; }
      p.ammo--;
      p.fireT = CONFIG.weapon.fireRate;

      const spread = rand(-CONFIG.weapon.spread, CONFIG.weapon.spread);
      const a = p.angle + spread;
      const muzzle = p.r + 14;
      state.bullets.push({
        x: p.x + Math.cos(p.angle) * muzzle,
        y: p.y + Math.sin(p.angle) * muzzle,
        vx: Math.cos(a) * CONFIG.weapon.bulletSpeed,
        vy: Math.sin(a) * CONFIG.weapon.bulletSpeed,
        life: CONFIG.weapon.bulletLife,
      });

      // muzzle flash particles
      for (let i = 0; i < 3; i++)
        addParticle(
          p.x + Math.cos(p.angle) * muzzle,
          p.y + Math.sin(p.angle) * muzzle,
          Math.cos(a) * rand(40, 140) + rand(-40, 40),
          Math.sin(a) * rand(40, 140) + rand(-40, 40),
          rand(0.05, 0.14),
          CONFIG.colors.bullet,
          rand(1, 3)
        );

      p.recoil = 3;
      state.shake = Math.min(state.shake + 2, 6);
      updateHud();
    }

    function reload() {
      const p = state.player;
      if (p.reloading || p.ammo >= CONFIG.weapon.magSize || p.reserve <= 0) return;
      p.reloading = true;
      p.reloadT = CONFIG.weapon.reloadTime;
      $("reload-hint").classList.remove("hidden");
    }

    function finishReload() {
      const p = state.player;
      const need = CONFIG.weapon.magSize - p.ammo;
      const take = Math.min(need, p.reserve);
      p.ammo += take;
      p.reserve -= take;
      p.reloading = false;
      $("reload-hint").classList.add("hidden");
      updateHud();
    }

    // ---- particles / fx ----
    function addParticle(x, y, vx, vy, life, color, size) {
      state.particles.push({ x, y, vx, vy, life, maxLife: life, color, size });
    }

    function burst(x, y, color, n = 12, power = 260) {
      for (let i = 0; i < n; i++) {
        const a = rand(0, Math.PI * 2);
        const s = rand(power * 0.3, power);
        addParticle(x, y, Math.cos(a) * s, Math.sin(a) * s, rand(0.2, 0.5), color, rand(1.5, 3.5));
      }
    }

    function addDamageText(x, y, text, color) {
      state.damageTexts.push({ x, y, text, color, life: 0.8, maxLife: 0.8 });
    }

    // ---- update ----
    function update(dt) {
      if (state.paused || state.over) return;
      state.time += dt;
      const p = state.player;

      // aim
      const cam = camera();
      const wmx = mouse.x + cam.x;
      const wmy = mouse.y + cam.y;
      p.angle = Math.atan2(wmy - p.y, wmx - p.x);

      // movement
      let mx = 0, my = 0;
      if (keys["a"] || keys["arrowleft"]) mx -= 1;
      if (keys["d"] || keys["arrowright"]) mx += 1;
      if (keys["w"] || keys["arrowup"]) my -= 1;
      if (keys["s"] || keys["arrowdown"]) my += 1;
      if (mx || my) {
        const len = Math.hypot(mx, my);
        p.x += (mx / len) * CONFIG.player.speed * dt;
        p.y += (my / len) * CONFIG.player.speed * dt;
      }
      const wallPad = 40;
      p.x = Math.max(wallPad, Math.min(CONFIG.world.w - wallPad, p.x));
      p.y = Math.max(wallPad, Math.min(CONFIG.world.h - wallPad, p.y));

      // timers
      if (p.fireT > 0) p.fireT -= dt;
      if (p.recoil > 0) p.recoil = Math.max(0, p.recoil - dt * 40);
      if (p.hitFlash > 0) p.hitFlash -= dt;
      if (p.reloading) {
        p.reloadT -= dt;
        if (p.reloadT <= 0) finishReload();
      }
      if (mouse.down && !p.reloading) fire();

      if (state.spawning) {
        state.waveTimer -= dt;
        if (state.waveTimer <= 0) startNextWave();
      }

      // bullets
      for (let i = state.bullets.length - 1; i >= 0; i--) {
        const b = state.bullets[i];
        b.x += b.vx * dt;
        b.y += b.vy * dt;
        b.life -= dt;

        let dead = b.life <= 0 || b.x < 0 || b.y < 0 ||
          b.x > CONFIG.world.w || b.y > CONFIG.world.h;

        if (!dead) {
          for (const e of state.enemies) {
            if (e.spawn > 0) continue;
            if (dist2(b.x, b.y, e.x, e.y) < (e.r + 4) ** 2) {
              e.health -= CONFIG.weapon.damage;
              e.hitT = 0.12;
              addDamageText(e.x, e.y - e.r - 4, CONFIG.weapon.damage, "#ffd24d");
              burst(b.x, b.y, CONFIG.colors.enemy, 5, 160);
              // knockback
              const ka = Math.atan2(b.vy, b.vx);
              e.x += Math.cos(ka) * 6;
              e.y += Math.sin(ka) * 6;
              dead = true;
              if (e.health <= 0) killEnemy(e);
              break;
            }
          }
        }

        if (dead) {
          state.bullets.splice(i, 1);
        }
      }

      // enemies
      for (let i = state.enemies.length - 1; i >= 0; i--) {
        const e = state.enemies[i];
        if (e.spawn > 0) { e.spawn -= dt; continue; }
        if (e.hitT > 0) e.hitT -= dt;
        e.wobble += dt * 2;

        const ang = Math.atan2(p.y - e.y, p.x - e.x);
        const d = Math.hypot(p.x - e.x, p.y - e.y);
        const touch = e.r + p.r;
        if (d > touch - 2) {
          e.x += Math.cos(ang) * e.speed * dt;
          e.y += Math.sin(ang) * e.speed * dt;
        }
        if (e.attackT > 0) e.attackT -= dt;
        if (d <= touch + 4 && e.attackT <= 0) {
          e.attackT = CONFIG.enemy.attackCooldown;
          p.health -= CONFIG.enemy.damage;
          p.hitFlash = 0.25;
          state.shake = Math.min(state.shake + 5, 12);
          addDamageText(p.x, p.y - p.r - 8, "-" + CONFIG.enemy.damage, "#ff4d5e");
          burst(p.x, p.y, "#ff4d5e", 6, 180);
          updateHud();
          if (p.health <= 0) return gameOver();
        }
      }

      // pickups
      for (let i = state.pickups.length - 1; i >= 0; i--) {
        const pk = state.pickups[i];
        pk.life -= dt;
        pk.bob += dt * 4;
        if (pk.life <= 0) { state.pickups.splice(i, 1); continue; }
        if (dist2(pk.x, pk.y, p.x, p.y) < (p.r + pk.r) ** 2) {
          if (pk.type === "health") {
            p.health = Math.min(p.maxHealth, p.health + 25);
          } else {
            p.reserve += 60;
          }
          burst(pk.x, pk.y, pk.color, 8, 200);
          state.pickups.splice(i, 1);
          updateHud();
        }
      }

      // particles
      for (let i = state.particles.length - 1; i >= 0; i--) {
        const pt = state.particles[i];
        pt.x += pt.vx * dt;
        pt.y += pt.vy * dt;
        pt.vx *= 0.94;
        pt.vy *= 0.94;
        pt.life -= dt;
        if (pt.life <= 0) state.particles.splice(i, 1);
      }

      // damage texts
      for (let i = state.damageTexts.length - 1; i >= 0; i--) {
        const t = state.damageTexts[i];
        t.y -= 26 * dt;
        t.life -= dt;
        if (t.life <= 0) state.damageTexts.splice(i, 1);
      }

      if (state.shake > 0) state.shake = Math.max(0, state.shake - dt * 30);

      // wave cleared?
      if (!state.spawning && state.enemies.length === 0 && !state.over) {
        state.spawning = true;
        state.waveTimer = CONFIG.wave.breakTime;
        state.player.reserve += 30;
        updateHud();
      }
    }

    function killEnemy(e) {
      const idx = state.enemies.indexOf(e);
      if (idx >= 0) state.enemies.splice(idx, 1);
      state.score += 10 + state.wave * 2;
      burst(e.x, e.y, CONFIG.colors.enemy, 18, 320);
      // drop chance
      const roll = Math.random();
      if (roll < 0.14) {
        state.pickups.push({ x: e.x, y: e.y, r: 12, type: "health", color: CONFIG.colors.health, life: 12, bob: 0 });
      } else if (roll < 0.3) {
        state.pickups.push({ x: e.x, y: e.y, r: 12, type: "ammo", color: CONFIG.colors.xp, life: 12, bob: 0 });
      }
      updateHud();
    }

    function camera() {
      const p = state.player;
      let cx = p.x - view.w / 2;
      let cy = p.y - view.h / 2;
      cx = Math.max(0, Math.min(CONFIG.world.w - view.w, cx));
      cy = Math.max(0, Math.min(CONFIG.world.h - view.h, cy));
      if (CONFIG.world.w < view.w) cx = (CONFIG.world.w - view.w) / 2;
      if (CONFIG.world.h < view.h) cy = (CONFIG.world.h - view.h) / 2;
      return { x: cx, y: cy };
    }

    // ---- render ----
    function render() {
      const cam = camera();
      const sh = state.shake;
      const ox = sh ? rand(-sh, sh) : 0;
      const oy = sh ? rand(-sh, sh) : 0;

      ctx.save();
      ctx.fillStyle = CONFIG.colors.bg;
      ctx.fillRect(0, 0, view.w, view.h);
      ctx.translate(-cam.x + ox, -cam.y + oy);

      drawGrid(cam);
      drawWalls();

      // pickups
      for (const pk of state.pickups) {
        const pulse = 1 + Math.sin(pk.bob) * 0.12;
        ctx.save();
        ctx.globalAlpha = pk.life < 3 ? 0.4 + 0.6 * Math.abs(Math.sin(pk.life * 6)) : 1;
        ctx.fillStyle = pk.color;
        ctx.shadowColor = pk.color;
        ctx.shadowBlur = 18;
        ctx.beginPath();
        ctx.arc(pk.x, pk.y, pk.r * pulse, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
        ctx.fillStyle = "#04121a";
        ctx.font = "bold 13px system-ui";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(pk.type === "health" ? "+" : "A", pk.x, pk.y + 1);
      }

      // particles
      for (const pt of state.particles) {
        ctx.globalAlpha = Math.max(0, pt.life / pt.maxLife);
        ctx.fillStyle = pt.color;
        ctx.fillRect(pt.x - pt.size / 2, pt.y - pt.size / 2, pt.size, pt.size);
      }
      ctx.globalAlpha = 1;

      // bullets
      ctx.save();
      ctx.shadowColor = CONFIG.colors.bullet;
      ctx.shadowBlur = 12;
      ctx.strokeStyle = CONFIG.colors.bullet;
      ctx.lineWidth = 3;
      ctx.lineCap = "round";
      for (const b of state.bullets) {
        ctx.beginPath();
        ctx.moveTo(b.x, b.y);
        ctx.lineTo(b.x - b.vx * 0.012, b.y - b.vy * 0.012);
        ctx.stroke();
      }
      ctx.restore();

      // enemies
      for (const e of state.enemies) {
        if (e.spawn > 0) { drawSpawnWarn(e); continue; }
        drawEnemy(e);
      }

      drawPlayer();

      // damage texts
      for (const t of state.damageTexts) {
        ctx.globalAlpha = Math.max(0, t.life / t.maxLife);
        ctx.fillStyle = t.color;
        ctx.font = "bold 16px system-ui";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(t.text, t.x, t.y);
      }
      ctx.globalAlpha = 1;

      ctx.restore();
    }

    function drawGrid(cam) {
      const step = 64;
      ctx.strokeStyle = CONFIG.colors.grid;
      ctx.lineWidth = 1;
      const x0 = Math.floor(cam.x / step) * step;
      const y0 = Math.floor(cam.y / step) * step;
      ctx.beginPath();
      for (let x = x0; x < cam.x + view.w + step; x += step) {
        ctx.moveTo(x, cam.y);
        ctx.lineTo(x, cam.y + view.h);
      }
      for (let y = y0; y < cam.y + view.h + step; y += step) {
        ctx.moveTo(cam.x, y);
        ctx.lineTo(cam.x + view.w, y);
      }
      ctx.stroke();
    }

    function drawWalls() {
      ctx.strokeStyle = CONFIG.colors.wallEdge;
      ctx.lineWidth = 6;
      ctx.shadowColor = CONFIG.colors.wallEdge;
      ctx.shadowBlur = 20;
      ctx.strokeRect(3, 3, CONFIG.world.w - 6, CONFIG.world.h - 6);
      ctx.shadowBlur = 0;
    }

    function drawPlayer() {
      const p = state.player;
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.angle);
      // body
      ctx.shadowColor = CONFIG.colors.player.color;
      ctx.shadowBlur = 22;
      ctx.fillStyle = p.hitFlash > 0 ? "#ffffff" : CONFIG.colors.player.color;
      ctx.beginPath();
      ctx.arc(0, 0, p.r, 0, Math.PI * 2);
      ctx.fill();
      // barrel
      ctx.shadowBlur = 0;
      ctx.fillStyle = "#0b0f1a";
      ctx.fillRect(p.r - 4, -5, 20, 10);
      ctx.restore();

      // health ring
      const ratio = Math.max(0, p.health / p.maxHealth);
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.strokeStyle = "rgba(255,255,255,0.12)";
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(0, 0, p.r + 8, 0, Math.PI * 2);
      ctx.stroke();
      ctx.strokeStyle = ratio > 0.5 ? "#50e678" : ratio > 0.25 ? "#ffd24d" : "#ff4d5e";
      ctx.beginPath();
      ctx.arc(0, 0, p.r + 8, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * ratio);
      ctx.stroke();
      ctx.restore();
    }

    function drawEnemy(e) {
      ctx.save();
      ctx.translate(e.x, e.y);
      ctx.shadowColor = CONFIG.colors.enemy;
      ctx.shadowBlur = 16;
      ctx.fillStyle = e.hitT > 0 ? "#ffffff" : CONFIG.colors.enemy;
      ctx.beginPath();
      ctx.arc(0, 0, e.r, 0, Math.PI * 2);
      ctx.fill();
      // eye toward player
      const ang = Math.atan2(state.player.y - e.y, state.player.x - e.x);
      ctx.shadowBlur = 0;
      ctx.fillStyle = CONFIG.colors.enemyEye;
      ctx.beginPath();
      ctx.arc(Math.cos(ang) * 6, Math.sin(ang) * 6, 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();

      // health bar
      if (e.health < e.maxHealth) {
        const w = e.r * 2.4;
        const x = e.x - w / 2;
        const y = e.y - e.r - 12;
        ctx.fillStyle = "rgba(0,0,0,0.6)";
        ctx.fillRect(x - 1, y - 1, w + 2, 6);
        ctx.fillStyle = "#ff4d5e";
        ctx.fillRect(x, y, w * Math.max(0, e.health / e.maxHealth), 4);
      }
    }

    function drawSpawnWarn(e) {
      ctx.save();
      ctx.globalAlpha = 0.3 + 0.4 * Math.abs(Math.sin(e.spawn * 8));
      ctx.strokeStyle = CONFIG.colors.enemy;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(e.x, e.y, e.r + 6, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();
    }

    // ---- loop ----
    function frame(ts) {
      if (!state.running) return;
      if (!last) last = ts;
      let dt = (ts - last) / 1000;
      last = ts;
      if (dt > 0.1) dt = 0.1;

      if (!state.paused && !state.over) {
        accumulator += dt;
        while (accumulator >= FIXED) {
          update(FIXED);
          accumulator -= FIXED;
        }
      }
      render();
      raf = requestAnimationFrame(frame);
    }

    function updateHud() {
      const p = state.player;
      if (!p) return;
      const ratio = Math.max(0, p.health / p.maxHealth);
      $("health-fill").style.width = ratio * 100 + "%";
      $("health-fill").style.background =
        ratio > 0.5 ? "linear-gradient(90deg,#2fbf5f,#50e678)"
          : ratio > 0.25 ? "linear-gradient(90deg,#c79a2f,#ffd24d)"
            : "linear-gradient(90deg,#a32836,#ff4d5e)";
      $("health-text").textContent = Math.max(0, Math.ceil(p.health));
      $("ammo-text").textContent = p.ammo;
      $("ammo-reserve").textContent = "/ " + p.reserve;
      $("hud-wave").textContent = Math.max(1, state.wave);
      $("hud-score").textContent = state.score;
    }

    function gameOver() {
      state.over = true;
      state.running = true;
      const best = Auth.best(currentUser.name);
      const isRecord = state.score > best;
      if (isRecord) Auth.setBest(currentUser.name, state.score);
      $("hud-best").textContent = Auth.best(currentUser.name);
      $("final-score").textContent = state.score;
      $("final-wave").textContent = Math.max(1, state.wave);
      $("new-record").classList.toggle("hidden", !isRecord);
      $("gameover-overlay").classList.remove("hidden");
      if (raf) cancelAnimationFrame(raf);
      raf = null;
    }

    function hideOverlays() {
      $("gameover-overlay").classList.add("hidden");
      $("pause-overlay").classList.add("hidden");
    }

    return {
      get running() { return state.running; },
      start() {
        reset();
        hideOverlays();
        state.running = true;
        last = 0;
        accumulator = 0;
        if (raf) cancelAnimationFrame(raf);
        raf = requestAnimationFrame(frame);
      },
      stop() {
        state.running = false;
        if (raf) cancelAnimationFrame(raf);
        raf = null;
      },
      reload,
      togglePause() {
        if (state.over) return;
        state.paused = !state.paused;
        $("pause-overlay").classList.toggle("hidden", !state.paused);
        if (!state.paused) { last = 0; }
      },
    };
  })();

  // pause overlay buttons
  $("resume-btn").onclick = () => Game.togglePause();
  $("restart-btn").onclick = () => {
    $("gameover-overlay").classList.add("hidden");
    Game.start();
  };

  // ========================================================================
  // Boot — resume existing session or show login
  // ========================================================================
  setMode("login");
  const existing = Auth.session();
  if (existing) {
    startSession(existing);
  }
})();
