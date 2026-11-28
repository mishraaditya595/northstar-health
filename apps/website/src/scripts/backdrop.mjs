// One low-resolution WebGL canvas behind the page: a soft, slowly flowing glow
// whose colour follows the section on screen. Everything here is optional
// decoration: without it the page shows a static CSS gradient instead.
import { MOTION_QUERY } from './home-motion.mjs';

const clamp = (n, a = 0, b = 1) => Math.max(a, Math.min(b, n));
const smooth = t => t * t * (3 - 2 * t);

// Weak or data-saving devices and anything without WebGL keep the gradient.
// Values a browser does not expose count as "not weak" (iPhones expose no
// deviceMemory).
export function backdropAllowed({ motionOk, webgl, saveData, deviceMemory, hardwareConcurrency }) {
  if (!motionOk || !webgl || saveData === true) return false;
  if (deviceMemory !== undefined && deviceMemory < 4) return false;
  if (hardwareConcurrency !== undefined && hardwareConcurrency <= 2) return false;
  return true;
}

// Colour for page position y. Each stop holds its exact colour until the last
// 30% of the gap before the next stop, then blends with a smoothstep.
export function paletteAt(stops, y) {
  if (y <= stops[0].y) return stops[0].color;
  const last = stops[stops.length - 1];
  if (y >= last.y) return last.color;
  let i = 0;
  while (y >= stops[i + 1].y) i++;
  const a = stops[i], b = stops[i + 1];
  const start = b.y - (b.y - a.y) * 0.3;
  if (y <= start) return a.color;
  const t = smooth(clamp((y - start) / (b.y - start)));
  return a.color.map((c, k) => c + (b.color[k] - c) * t);
}

// Backing size: DPR capped at 1 and half the viewport's CSS pixels per axis.
export function renderSize(cssW, cssH, dpr) {
  const s = Math.min(dpr, 1) * 0.5;
  return { w: Math.max(1, Math.round(cssW * s)), h: Math.max(1, Math.round(cssH * s)) };
}

// True while the viewport's bottom edge is still inside the intro, which is
// opaque and so hides the whole backdrop.
export function introCovers(scrollY, viewportH, introBottom) {
  return introBottom > 0 && scrollY + viewportH <= introBottom;
}

const VERT = 'attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}';
// Soft aurora: two warped noise layers give a few separate glows over a
// mostly empty canvas. In dark mode the canvas is also deepened a little
// (alpha floor b), so the glows read as light rather than haze.
const FRAG = `precision mediump float;
uniform vec2 r,m;uniform vec3 c;uniform float t,s,k,b;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
float fbm(vec2 p){float v=0.,a=.5;for(int i=0;i<4;i++){v+=a*n(p);p=p*2.03+vec2(7.1,3.7);a*=.5;}return v;}
void main(){
vec2 u=gl_FragCoord.xy/r;
vec2 p=u*vec2(r.x/r.y,1.)*1.1+vec2(0.,s*.00025)+m*.1;
float q=fbm(p*.7+vec2(t*.03,-t*.02));
float f=fbm(p+q*1.8+vec2(-t*.025,t*.018));
float g=smoothstep(.5,.9,f);
g*=g*(3.-2.*g);
float v=.35+.65*smoothstep(0.,1.,1.-abs(u.x-.5)*1.4);
float a=g*v*k;
vec3 col=c*(.75+.5*q);
float d=(h(gl_FragCoord.xy+t)-.5)/255.;
gl_FragColor=vec4(col*a+d,a+b*(1.-a));
}`;

function parseHex(v, fallback) {
  const m = /^#?([0-9a-f]{6})$/i.exec((v || '').trim());
  if (!m) return fallback;
  const n = parseInt(m[1], 16);
  return [(n >> 16) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

export function mountBackdrop(canvas, win) {
  const doc = win.document;
  const host = canvas.parentElement;
  const media = win.matchMedia(MOTION_QUERY);
  const scheme = win.matchMedia('(prefers-color-scheme: light)');
  const fine = win.matchMedia('(pointer: fine)');
  let gl = null, program = null, loc = {}, raf = 0, live = false, lost = false, torn = false;
  let stops = [{ y: 0, color: [0.8, 1, 0.4] }], introBottom = 0;
  let time = 0, last = 0, frame = 0, px = 0, py = 0, tx = 0, ty = 0;

  const setLive = on => {
    if (on === live) return;
    live = on;
    if (on) host.classList.add('is-live'); else host.classList.remove('is-live');
  };
  const env = () => {
    const nav = win.navigator || {};
    return {
      motionOk: media.matches, webgl: true,
      saveData: nav.connection?.saveData,
      deviceMemory: nav.deviceMemory,
      hardwareConcurrency: nav.hardwareConcurrency,
    };
  };

  function measure() {
    const light = scheme.matches;
    const css = win.getComputedStyle(doc.documentElement);
    const tok = (n, f) => parseHex(css.getPropertyValue(n), f);
    // Dark mode leans the lime toward green and saturates the violet: plain
    // lime at low alpha over the dark canvas reads as olive haze.
    const lime = light ? tok('--performance', [0.19, 0.41, 0.27])
      : tok('--lime', [0.84, 1, 0.38]).map((c, i) => c * 0.45 + [0.1, 0.95, 0.42][i] * 0.55);
    const sleep = tok('--sleep', [0.76, 0.66, 1]);
    const violet = light ? sleep : sleep.map((c, i) => c * 0.5 + [0.42, 0.22, 1][i] * 0.5);
    const heroTo = tok('--hero-to', [0.05, 0.13, 0.15]);
    const teal = light ? heroTo.map((c, i) => c * 0.4 + [0.1, 0.45, 0.45][i] * 0.6)
      : heroTo.map((c, i) => c * 0.2 + [0.05, 0.85, 0.8][i] * 0.8);
    const colors = { lime, violet, teal };
    const found = [];
    for (const el of doc.querySelectorAll('[data-backdrop]')) {
      const color = colors[el.dataset.backdrop];
      if (color) found.push({ y: el.getBoundingClientRect().top + win.scrollY, color });
    }
    found.sort((a, b) => a.y - b.y);
    if (found.length) stops = found;
    const intro = doc.querySelector('[data-cinematic]');
    introBottom = intro ? intro.getBoundingClientRect().bottom + win.scrollY : 0;
  }

  function compile(type, src) {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error('shader');
    return sh;
  }
  function setup() {
    gl = canvas.getContext('webgl', { alpha: true, antialias: false, depth: false, stencil: false, powerPreference: 'low-power' });
    if (!gl) return false;
    try {
      program = gl.createProgram();
      gl.attachShader(program, compile(gl.VERTEX_SHADER, VERT));
      gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FRAG));
      gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error('link');
      gl.useProgram(program);
      const buf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      const a = gl.getAttribLocation(program, 'p');
      gl.enableVertexAttribArray(a);
      gl.vertexAttribPointer(a, 2, gl.FLOAT, false, 0, 0);
      for (const n of ['r', 'm', 'c', 't', 's', 'k', 'b']) loc[n] = gl.getUniformLocation(program, n);
      return true;
    } catch {
      gl = null;
      return false;
    }
  }
  function resize() {
    const { w, h } = renderSize(win.innerWidth, win.innerHeight, win.devicePixelRatio || 1);
    if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
    gl.viewport(0, 0, w, h);
    gl.uniform2f(loc.r, w, h);
  }
  function runnable() {
    return !torn && !lost && gl && backdropAllowed(env()) && !doc.hidden &&
      !introCovers(win.scrollY, win.innerHeight, introBottom);
  }
  function schedule() { if (!raf && runnable()) raf = win.requestAnimationFrame(draw); }
  function draw(now) {
    raf = 0;
    if (!runnable()) {
      last = 0;
      // Motion or a guard turned off without its change event reaching us
      // (seen once in headless Chromium on this page): fall back to
      // the static glow here too.
      if (!torn && !backdropAllowed(env())) setLive(false);
      return;
    }
    // 30 fps is plenty for a slow glow and halves the battery cost.
    frame++;
    // Scenes and fonts change the page's height after mount; keep the
    // section positions current (one layout read about every two seconds).
    if (frame % 120 === 0) measure();
    if (frame % 2 === 0) { raf = win.requestAnimationFrame(draw); return; }
    time += last ? Math.min(0.1, (now - last) / 1000) * 2 : 0;
    last = now;
    px += (tx - px) * 0.05; py += (ty - py) * 0.05;
    const y = win.scrollY + win.innerHeight * 0.5;
    const light = scheme.matches;
    gl.uniform1f(loc.t, time);
    gl.uniform1f(loc.s, win.scrollY);
    gl.uniform1f(loc.k, light ? 0.18 : 0.48);
    gl.uniform1f(loc.b, light ? 0 : 0.3);
    gl.uniform2f(loc.m, px, py);
    gl.uniform3fv(loc.c, paletteAt(stops, y));
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    setLive(true);
    raf = win.requestAnimationFrame(draw);
  }
  function stop() {
    if (raf) win.cancelAnimationFrame(raf);
    raf = 0; last = 0;
    setLive(false);
  }
  function start() {
    if (torn || lost) return;
    if (!media.matches) { stop(); return; }
    if (!gl && !setup()) { stop(); return; }
    if (!backdropAllowed(env())) { stop(); return; }
    measure(); resize(); schedule();
  }

  const onLost = e => { e.preventDefault?.(); lost = true; gl = null; stop(); };
  const onRestored = () => { lost = false; gl = null; program = null; start(); };
  const onVisibility = () => { if (doc.hidden) { stop(); } else { schedule(); } };
  const onScroll = () => { schedule(); };
  let resizeRaf = 0;
  const onResize = () => {
    if (resizeRaf || torn) return;
    resizeRaf = win.requestAnimationFrame(() => { resizeRaf = 0; if (gl) { measure(); resize(); } schedule(); });
  };
  const onPointer = e => {
    tx = (e.clientX / (win.innerWidth || 1)) * 2 - 1;
    ty = 1 - (e.clientY / (win.innerHeight || 1)) * 2;
  };
  const onMotion = () => { if (media.matches) start(); else stop(); };
  const onScheme = () => { if (gl) measure(); };

  canvas.addEventListener('webglcontextlost', onLost);
  canvas.addEventListener('webglcontextrestored', onRestored);
  doc.addEventListener('visibilitychange', onVisibility);
  win.addEventListener('scroll', onScroll, { passive: true });
  win.addEventListener('resize', onResize);
  if (fine.matches) win.addEventListener('pointermove', onPointer, { passive: true });
  media.addEventListener?.('change', onMotion);
  scheme.addEventListener?.('change', onScheme);
  start();

  return function teardown() {
    torn = true;
    stop();
    canvas.removeEventListener('webglcontextlost', onLost);
    canvas.removeEventListener('webglcontextrestored', onRestored);
    doc.removeEventListener('visibilitychange', onVisibility);
    win.removeEventListener('scroll', onScroll);
    win.removeEventListener('resize', onResize);
    win.removeEventListener('pointermove', onPointer);
    media.removeEventListener?.('change', onMotion);
    scheme.removeEventListener?.('change', onScheme);
  };
}
