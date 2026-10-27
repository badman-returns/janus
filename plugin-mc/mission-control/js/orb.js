// orb.js — the Cloud: 700 points on a shell tied once to their two nearest neighbours; sparks hop
// along the ties while thinking; the lit face turns toward the operator when it listens or speaks
// and to the far side while it works; waiting holds the warm token. It draws nothing the loop is not
// doing: feed it the loop's events with on(). Expects window.THREE (vendor/three.min.js).
//
// Lifted from the presence mockup (a design file, not in this repo) — LOOKS.cloud, makeOrb,
// readTheme, groundOf, mulberry — with only what a module and the product need changed: no bus
// (on() takes the loop's events), no look table, dark unless the page is stamped light, and one
// requestAnimationFrame per orb that stops while the canvas is off screen.

const R = document.documentElement;
const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
function mulberry(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }

// ---- theme tokens → colours. The orb has no colours of its own. Mission control stamps
// data-theme="light"; dark is the default, so the stamp is the whole decision.
function readTheme() {
  const cs = getComputedStyle(R); const g = n => cs.getPropertyValue(n).trim();
  const col = h => new THREE.Color(h || "#888888");
  return { dark: R.dataset.theme !== "light", surface: col(g("--surface")), by: {
    idle: col(g("--rest")), listening: col(g("--acc")), thinking: col(g("--think")), speaking: col(g("--acc")),
    waiting: col(g("--warn")), muted: col(g("--rest")), offline: col(g("--mut2")) } };
}
let theme = null;
function groundOf(el) { let e = el.parentElement; while (e && e !== document.body) { const bg = getComputedStyle(e).backgroundColor; if (bg && bg !== "transparent" && !/rgba\(\s*\d+,\s*\d+,\s*\d+,\s*0\s*\)/.test(bg)) return new THREE.Color(bg); e = e.parentElement; } return theme.surface.clone(); }

// ---- the Cloud ----
function cloud(o) {
  const N = 700, rnd = mulberry(7);
  const dir = new Float32Array(N * 3), ph = new Float32Array(N), rj = new Float32Array(N);
  for (let i = 0; i < N; i++) { const z = 1 - 2 * rnd(), a = rnd() * Math.PI * 2, s = Math.sqrt(1 - z * z); dir[i * 3] = s * Math.cos(a); dir[i * 3 + 1] = s * Math.sin(a); dir[i * 3 + 2] = z; ph[i] = rnd() * Math.PI * 2; rj[i] = 0.84 + 0.3 * rnd(); }
  const seg = [];   // two nearest neighbours per point, found once
  for (let i = 0; i < N; i++) { let b1 = -1, b2 = -1, d1 = 9, d2 = 9; const ix = dir[i * 3], iy = dir[i * 3 + 1], iz = dir[i * 3 + 2];
    for (let j = 0; j < N; j++) { if (j === i) continue; const dx = ix - dir[j * 3], dy = iy - dir[j * 3 + 1], dz = iz - dir[j * 3 + 2]; const d = dx * dx + dy * dy + dz * dz; if (d < d1) { d2 = d1; b2 = b1; d1 = d; b1 = j; } else if (d < d2) { d2 = d; b2 = j; } }
    seg.push(i, b1, i, b2); }
  const S = seg.length / 2;
  const pos = new Float32Array(N * 3), col = new Float32Array(N * 3), lpos = new Float32Array(S * 6);
  const geo = new THREE.BufferGeometry(); geo.setAttribute("position", new THREE.BufferAttribute(pos, 3)); geo.setAttribute("color", new THREE.BufferAttribute(col, 3));
  const mat = new THREE.PointsMaterial({ size: 2.4, sizeAttenuation: false, vertexColors: true, transparent: true, opacity: 0.95, depthWrite: false });
  const pts = new THREE.Points(geo, mat);
  const lgeo = new THREE.BufferGeometry(); lgeo.setAttribute("position", new THREE.BufferAttribute(lpos, 3));
  const lmat = new THREE.LineBasicMaterial({ transparent: true, opacity: 0.1, depthWrite: false });
  const lines = new THREE.LineSegments(lgeo, lmat);
  const D = 3, dpos = new Float32Array(D * 3); const dgeo = new THREE.BufferGeometry(); dgeo.setAttribute("position", new THREE.BufferAttribute(dpos, 3)); dgeo.setDrawRange(0, 0);
  const dmat = new THREE.PointsMaterial({ size: 5, sizeAttenuation: false, transparent: true, opacity: 1, depthWrite: false });
  const sparks = new THREE.Points(dgeo, dmat); const live = []; let lastSpawn = 0;
  const group = new THREE.Group(); group.add(pts, lines, sparks);
  const T = {
    idle:      { r: 1.00, sp: 0.25, br: 0.42, sz: 2.2, ln: 0.15, dots: 0, face: 0.35 },
    listening: { r: 0.88, sp: 0.55, br: 0.90, sz: 2.6, ln: 0.40, dots: 0, face: 1.0 },
    thinking:  { r: 0.72, sp: 1.60, br: 0.85, sz: 2.0, ln: 1.00, dots: 1, face: -1.0 },
    speaking:  { r: 0.82, sp: 0.35, br: 1.00, sz: 2.6, ln: 0.70, dots: 0, face: 1.0 },
    waiting:   { r: 0.80, sp: 0.10, br: 0.80, sz: 2.4, ln: 0.45, dots: 0, face: 1.0 },
    muted:     { r: 0.60, sp: 0.05, br: 0.28, sz: 2.0, ln: 0.00, dots: 0, face: 0.0 },
    offline:   { r: 0.70, sp: 0.00, br: 0.20, sz: 2.0, ln: 0.00, dots: 0, face: 0.0 } };
  const cur = Object.assign({}, T.idle); let rot = 0; const white = new THREE.Color(1, 1, 1);
  return { group,
    theme(th) { const b = th.dark ? THREE.AdditiveBlending : THREE.NormalBlending; mat.blending = lmat.blending = dmat.blending = b; mat.needsUpdate = lmat.needsUpdate = dmat.needsUpdate = true; },
    dispose() { geo.dispose(); lgeo.dispose(); dgeo.dispose(); mat.dispose(); lmat.dispose(); dmat.dispose(); },
    tick(t, dt, k) {
      const tg = T[o.state]; for (const key in tg) cur[key] += (tg[key] - cur[key]) * k;
      const spd = reduced ? 0.35 : 1;
      rot += dt * spd * (0.10 + cur.sp * 0.10 + o.energy * 1.4);
      group.rotation.y = rot; group.rotation.x = Math.sin(t * 0.2) * 0.12 + o.energy * Math.sin(t * 4) * 0.25 * spd;
      const wait = o.state === "waiting" ? 0.035 * Math.sin(t * Math.PI) : 0;
      const Rr = cur.r * (1 + wait) + o.level * (o.state === "speaking" ? 0.20 : 0.12);
      const sr = Math.sin(rot), cr = Math.cos(rot), g = o.ground, dark = theme.dark;
      const hs = o.h / 220; mat.size = Math.max(1.2, cur.sz * hs); dmat.size = Math.max(2, 5 * hs);
      for (let i = 0; i < N; i++) { const i3 = i * 3; const w = 1 + 0.05 * Math.sin(t * (0.6 + cur.sp * 1.4) * spd + ph[i]); const r = Rr * rj[i] * w;
        pos[i3] = dir[i3] * r; pos[i3 + 1] = dir[i3 + 1] * r; pos[i3 + 2] = dir[i3 + 2] * r;
        const zc = -dir[i3] * sr + dir[i3 + 2] * cr;                 // which way this point faces after the spin
        const b = clamp(cur.br * (0.62 + 0.38 * zc * cur.face), 0.04, 1.1);
        if (dark) { col[i3] = o.col.r * b; col[i3 + 1] = o.col.g * b; col[i3 + 2] = o.col.b * b; }
        else { col[i3] = g.r + (o.col.r - g.r) * b; col[i3 + 1] = g.g + (o.col.g - g.g) * b; col[i3 + 2] = g.b + (o.col.b - g.b) * b; } }
      geo.attributes.position.needsUpdate = true; geo.attributes.color.needsUpdate = true;
      for (let s = 0; s < S; s++) { const a = seg[s * 2] * 3, b = seg[s * 2 + 1] * 3, q = s * 6; lpos[q] = pos[a]; lpos[q + 1] = pos[a + 1]; lpos[q + 2] = pos[a + 2]; lpos[q + 3] = pos[b]; lpos[q + 4] = pos[b + 1]; lpos[q + 5] = pos[b + 2]; }
      lgeo.attributes.position.needsUpdate = true;
      lmat.opacity = cur.ln * (dark ? 0.22 : 0.30); lmat.color.copy(o.col);
      if (cur.dots > 0.5 && live.length < D && t - lastSpawn > 0.4) { const at = Math.floor(Math.random() * N); live.push({ at, to: seg[at * 4 + 1], p: 0, v: 2.2 + Math.random() * 1.5, hops: 7 }); lastSpawn = t; }
      let n = 0;
      for (let i = live.length - 1; i >= 0; i--) { const e = live[i]; e.p += dt * e.v * spd;
        while (e.p >= 1) { e.p -= 1; e.at = e.to; e.to = seg[e.at * 4 + (Math.random() < 0.5 ? 1 : 3)]; e.hops--; }
        if (e.hops <= 0 || cur.dots < 0.5) { live.splice(i, 1); continue; }
        const a = e.at * 3, b = e.to * 3, q = n * 3; dpos[q] = pos[a] + (pos[b] - pos[a]) * e.p; dpos[q + 1] = pos[a + 1] + (pos[b + 1] - pos[a + 1]) * e.p; dpos[q + 2] = pos[a + 2] + (pos[b + 2] - pos[a + 2]) * e.p; n++; }
      dgeo.setDrawRange(0, n); dgeo.attributes.position.needsUpdate = true; dmat.color.copy(dark ? white : o.col);
    } };
}

// ---- an orb: one canvas, one renderer, one reader of the loop's events ----
// Without THREE or without WebGL the page must still work, so makeOrb answers with a stub that
// swallows every event: nothing else on the screen depends on the orb.
const STUB = { on() {}, setTheme() {}, dispose() {} };

export function makeOrb(canvas) {
  if (!canvas || typeof THREE === "undefined") { if (canvas) canvas.classList.add("nogl"); return STUB; }
  theme = theme || readTheme();
  let renderer;
  try { renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: "low-power" }); }
  catch { canvas.classList.add("nogl"); return STUB; }
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1)); renderer.setClearColor(0x000000, 0);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(30, 1, 0.1, 40); camera.position.set(0, 0, 4.8);
  const o = { state: "idle", level: 0, h: 220, col: theme.by.idle.clone(), lastState: "idle", energy: 0, ground: groundOf(canvas) };
  const impl = cloud(o); scene.add(impl.group); impl.theme(theme);

  const resize = () => { const r = canvas.getBoundingClientRect(); const w = Math.max(2, Math.round(r.width)), h = Math.max(2, Math.round(r.height)); o.h = h; renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix(); };
  const ro = new ResizeObserver(resize); ro.observe(canvas); resize();

  // its own frame loop, stopped while the canvas is off screen and restarted when it comes back
  let raf = 0, last = 0, visible = true;
  function frame(now) {
    raf = visible ? requestAnimationFrame(frame) : 0;
    if (!visible) return;
    const dt = last ? Math.min(0.05, (now - last) / 1000) : 1 / 60; last = now;
    const k = 1 - Math.pow(0.02, dt);
    if (o.state !== o.lastState) { o.energy = reduced ? 0 : 1; o.lastState = o.state; }
    o.energy *= Math.pow(0.2, dt);
    o.col.lerp(theme.by[o.state], k);
    impl.tick(now / 1000, dt, k);
    renderer.render(scene, camera);
  }
  const io = new IntersectionObserver(es => {
    visible = es[es.length - 1].isIntersecting;
    if (visible && !raf) { last = 0; raf = requestAnimationFrame(frame); }
  }, { rootMargin: "80px" });
  io.observe(canvas);
  raf = requestAnimationFrame(frame);

  const api = {
    // exactly the loop's events: {t:"state",state} and {t:"level",v}. Anything else is ignored.
    on(e) {
      if (!e) return;
      if (e.t === "state") o.state = theme.by[e.state] ? e.state : "idle";
      else if (e.t === "level") o.level += ((+e.v || 0) - o.level) * 0.45;
    },
    setTheme() { theme = readTheme(); o.ground = groundOf(canvas); o.col.copy(theme.by[o.state]); impl.theme(theme); },
    dispose() { mo.disconnect(); io.disconnect(); ro.disconnect(); cancelAnimationFrame(raf); raf = 0; visible = false; impl.dispose(); renderer.dispose(); }
  };
  // fleet.js stamps data-theme from localStorage; follow it whenever it changes
  const mo = new MutationObserver(() => api.setTheme());
  mo.observe(R, { attributes: true, attributeFilter: ["data-theme"] });
  return api;
}
