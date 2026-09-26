// Contours dessines a main levee, partages par les ecrans WebUI (vestiaire,
// duel). Chaque bloc .sk recoit un SVG : ombre pleine, fond papier, deux
// passages d'encre. Graine (data-graine) et rayon (data-rayon) par bloc.

// ---------------------------------------------------------------- contours
// Rectangle arrondi dont le bord ondule un peu, comme trace a main levee.
// Frequences entieres : le trace se referme sans cassure.
function hasard(graine) {
  let s = (graine * 2654435761) >>> 0 || 1;
  return () => (s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296;
}
function contourTrace(w, h, r, graine, ampleur) {
  r = Math.min(r, w / 2, h / 2);
  const R = hasard(graine);
  const ph = [R() * 6.283, R() * 6.283, R() * 6.283];
  const segs = [
    ["l", r, 0, w - r, 0], ["a", w - r, r, -90], ["l", w, r, w, h - r], ["a", w - r, h - r, 0],
    ["l", w - r, h, r, h], ["a", r, h - r, 90], ["l", 0, h - r, 0, r], ["a", r, r, 180],
  ];
  const long = (s) => s[0] === "l" ? Math.hypot(s[3] - s[1], s[4] - s[2]) : r * Math.PI / 2;
  const total = segs.reduce((n, s) => n + long(s), 0);
  const n = Math.max(28, Math.round(total / 8));
  const pts = [];
  for (let i = 0; i < n; i++) {
    const t = i / n;
    let d = t * total, x, y, nx, ny;
    for (const s of segs) {
      const L = long(s);
      if (d > L) { d -= L; continue; }
      const f = L ? d / L : 0;
      if (s[0] === "l") {
        x = s[1] + (s[3] - s[1]) * f; y = s[2] + (s[4] - s[2]) * f;
        const dx = s[3] - s[1], dy = s[4] - s[2], m = Math.hypot(dx, dy) || 1;
        nx = dy / m; ny = -dx / m;
      } else {
        const ang = (s[3] + 90 * f) * Math.PI / 180;
        nx = Math.cos(ang); ny = Math.sin(ang);
        x = s[1] + r * nx; y = s[2] + r * ny;
      }
      break;
    }
    const b = ampleur * (0.6 * Math.sin(6.283 * 3 * t + ph[0]) + 0.3 * Math.sin(6.283 * 7 * t + ph[1]) + 0.15 * Math.sin(6.283 * 13 * t + ph[2]));
    pts.push([x + nx * b, y + ny * b]);
  }
  // Catmull-Rom ferme vers des courbes de Bezier : aucun angle entre deux points.
  let dstr = `M${pts[0][0].toFixed(2)},${pts[0][1].toFixed(2)}`;
  for (let i = 0; i < n; i++) {
    const p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
    dstr += `C${c1[0].toFixed(2)},${c1[1].toFixed(2)} ${c2[0].toFixed(2)},${c2[1].toFixed(2)} ${p2[0].toFixed(2)},${p2[1].toFixed(2)}`;
  }
  return dstr + "Z";
}
// Pose le SVG de chaque bloc .sk, une fois sa taille connue (0 tant que
// l'ecran est ferme : on repassera a l'ouverture).
function habiller() {
  document.querySelectorAll(".sk").forEach((el) => {
    const w = el.offsetWidth, h = el.offsetHeight;
    if (!w || !h || el.dataset.trace === `${w}x${h}`) return;
    el.dataset.trace = `${w}x${h}`;
    const g = Number(el.dataset.graine || 1);
    const r = Math.min(Number(el.dataset.rayon || 12), w / 2, h / 2);
    const m = 8;
    const svg = el.querySelector(":scope > .sk-svg") || document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", "sk-svg");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("width", w + 2 * m); svg.setAttribute("height", h + 2 * m);
    svg.setAttribute("viewBox", `${-m} ${-m} ${w + 2 * m} ${h + 2 * m}`);
    svg.style.left = svg.style.top = `${-m}px`;
    svg.innerHTML =
      `<path class="ombre" transform="translate(4 5)" d="${contourTrace(w, h, r, g, 0.9)}"/>` +
      `<path class="fond" d="${contourTrace(w, h, r, g, 0.9)}"/>` +
      `<path class="trait2" transform="translate(1.2 0.8)" d="${contourTrace(w, h, r, g + 5, 1.4)}"/>` +
      `<path class="trait" d="${contourTrace(w, h, r, g, 0.9)}"/>`;
    if (!svg.parentNode) el.prepend(svg);
  });
}
