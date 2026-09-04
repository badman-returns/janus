// auto / light / dark, remembered in localStorage. The base stylesheet IS the dark skin;
// light is the [data-theme=light] override server.js prepends from theme.json.
import { $ } from "./util.js";
import { ICON } from "./icons.js";
import { app } from "./state.js";

// ttyd bakes its palette in at launch, but its client also reads terminal options off the
// query string — so a light terminal costs a URL, not a second ttyd or a restart. theme.json
// is served beside this module; the page reads the same file the orchestrator hands ttyd.
export let XTERM_LIGHT = null;
try { const t = await (await fetch("/theme.json")).json(); XTERM_LIGHT = t.xterm_light || t.xterm || null; } catch {}

let isLight = false;
export const termURL = (win, port) => `http://127.0.0.1:${port}/?arg=${encodeURIComponent(win)}`
  + (isLight && XTERM_LIGHT ? `&theme=${encodeURIComponent(JSON.stringify(XTERM_LIGHT))}` : "");

// only touch an iframe whose src actually changed: re-assigning it reconnects the terminal
export function repaintTerminals(){
  document.querySelectorAll("iframe[data-termf]").forEach(f => {
    const want = termURL(f.dataset.termf, (app.S && app.S.ttyd_port) || 0);
    if (f.getAttribute("src") !== want) f.setAttribute("src", want);
  });
}

const THEMES = ["auto","light","dark"];
let theme = "auto"; try { theme = localStorage.getItem("dm2-theme")||"auto"; } catch {}
export function applyTheme(){
  const wantLight = theme==="light" || (theme==="auto" && !matchMedia("(prefers-color-scheme: dark)").matches);
  isLight = wantLight;
  document.documentElement.toggleAttribute("data-theme", false);
  if (wantLight) document.documentElement.setAttribute("data-theme","light");
  else document.documentElement.removeAttribute("data-theme");
  $("themeBtn").innerHTML = ICON[theme==="auto" ? "auto" : theme==="light" ? "sun" : "moon"];
  $("themeBtn").dataset.tip = "Theme: " + theme + " — click to cycle";
  repaintTerminals();
}
matchMedia("(prefers-color-scheme: dark)").addEventListener?.("change", () => { if (theme==="auto") applyTheme(); });
$("themeBtn").onclick = () => { theme = THEMES[(THEMES.indexOf(theme)+1)%3];
  try{ localStorage.setItem("dm2-theme",theme); }catch{}; applyTheme(); };
applyTheme();
