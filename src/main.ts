import { invoke } from "@tauri-apps/api/core";
import { save } from "@tauri-apps/plugin-dialog";

type Tool = "rect" | "number" | "blur";
type Rect = { kind: "rect"; x: number; y: number; w: number; h: number; color: string; widthPx: number };
type Blur = { kind: "blur"; x: number; y: number; w: number; h: number };
type Num = { kind: "number"; x: number; y: number; n: number; color: string; radius: number };
type Shape = Rect | Blur | Num;

const COLORS = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#000000"];
const WIDTHS = [2, 4, 8]; // points
const TOOLS: [Tool, string][] = [["rect", "Box"], ["number", "Number"], ["blur", "Blur"]];

let color = COLORS[0];
let widthPt = 4;
let tool: Tool = "rect";
const shapes: Shape[] = [];
let drag: { x0: number; y0: number; x1: number; y1: number } | null = null;
let image: ImageBitmap | null = null;

const canvas = document.querySelector<HTMLCanvasElement>("#canvas")!;
const ctx = canvas.getContext("2d")!;
const area = document.querySelector<HTMLElement>("#area")!;
const undoBtn = document.querySelector<HTMLButtonElement>("#undo")!;
const toastEl = document.querySelector<HTMLElement>("#toast")!;

// --- toolbar ---------------------------------------------------------------

function buildToolbar() {
  const toolsEl = document.querySelector("#tools")!;
  for (const [t, label] of TOOLS) {
    const b = document.createElement("button");
    b.className = "tool";
    b.textContent = label;
    b.dataset.tool = t;
    b.onclick = () => {
      tool = t;
      updateToolbar();
    };
    toolsEl.append(b);
  }
  const colorsEl = document.querySelector("#colors")!;
  for (const c of COLORS) {
    const b = document.createElement("button");
    b.className = "swatch";
    b.style.background = c;
    b.title = c;
    b.onclick = () => {
      color = c;
      updateToolbar();
    };
    b.dataset.color = c;
    colorsEl.append(b);
  }
  const widthsEl = document.querySelector("#widths")!;
  for (const w of WIDTHS) {
    const b = document.createElement("button");
    b.className = "width";
    b.title = `${w} pt`;
    b.dataset.width = String(w);
    const line = document.createElement("span");
    line.style.height = `${w}px`;
    b.append(line);
    b.onclick = () => {
      widthPt = w;
      updateToolbar();
    };
    widthsEl.append(b);
  }
  undoBtn.onclick = undo;
  document.querySelector<HTMLButtonElement>("#copy")!.onclick = copy;
  document.querySelector<HTMLButtonElement>("#save")!.onclick = saveImage;
  updateToolbar();
}

function updateToolbar() {
  document.querySelectorAll<HTMLElement>(".tool").forEach((b) =>
    b.classList.toggle("selected", b.dataset.tool === tool),
  );
  document.querySelectorAll<HTMLElement>(".swatch").forEach((b) =>
    b.classList.toggle("selected", b.dataset.color === color),
  );
  document.querySelectorAll<HTMLElement>(".width").forEach((b) =>
    b.classList.toggle("selected", b.dataset.width === String(widthPt)),
  );
  undoBtn.disabled = shapes.length === 0;
}

// --- drawing ---------------------------------------------------------------

function strokeRect(r: Rect) {
  ctx.strokeStyle = r.color;
  ctx.lineWidth = r.widthPx;
  ctx.lineJoin = "round";
  // Slightly rounded corners, scaled with the stroke so thick lines don't look square.
  const radius = Math.min(r.widthPx * 1.5, Math.abs(r.w) / 2, Math.abs(r.h) / 2);
  ctx.beginPath();
  ctx.roundRect(r.x, r.y, r.w, r.h, radius);
  ctx.stroke();
}

/** Blur by downscaling the original image region, then smoothly upscaling it back. */
const blurCanvas = document.createElement("canvas");
function drawBlur(b: Blur) {
  if (!image || b.w < 1 || b.h < 1) return;
  const k = 10 * window.devicePixelRatio; // blur strength (image px per sample)
  const sw = Math.max(1, Math.round(b.w / k));
  const sh = Math.max(1, Math.round(b.h / k));
  blurCanvas.width = sw;
  blurCanvas.height = sh;
  const bctx = blurCanvas.getContext("2d")!;
  bctx.imageSmoothingQuality = "high";
  bctx.drawImage(image, b.x, b.y, b.w, b.h, 0, 0, sw, sh);
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(blurCanvas, 0, 0, sw, sh, b.x, b.y, b.w, b.h);
}

function drawNumber(m: Num) {
  ctx.beginPath();
  ctx.arc(m.x, m.y, m.radius, 0, Math.PI * 2);
  ctx.fillStyle = m.color;
  ctx.fill();
  ctx.lineWidth = m.radius * 0.15;
  ctx.strokeStyle = "#fff";
  ctx.stroke();
  ctx.fillStyle = m.color === "#FFCC00" ? "#000" : "#fff";
  ctx.font = `bold ${m.radius * (m.n > 9 ? 1.0 : 1.2)}px -apple-system, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(String(m.n), m.x, m.y + m.radius * 0.05);
}

function drawShape(s: Shape) {
  if (s.kind === "rect") strokeRect(s);
  else if (s.kind === "blur") drawBlur(s);
  else drawNumber(s);
}

function normalized(): Rect | Blur | null {
  if (!drag) return null;
  const box = {
    x: Math.min(drag.x0, drag.x1),
    y: Math.min(drag.y0, drag.y1),
    w: Math.abs(drag.x1 - drag.x0),
    h: Math.abs(drag.y1 - drag.y0),
  };
  if (tool === "blur") return { kind: "blur", ...box };
  return { kind: "rect", ...box, color, widthPx: widthPt * window.devicePixelRatio };
}

function redraw() {
  if (!image) return;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(image, 0, 0);
  shapes.forEach(drawShape);
  const live = normalized();
  if (live) drawShape(live);
}

/** Scale the canvas (CSS) to fit the area, never above 1 CSS px per image px / DPR. */
function layout() {
  if (!image) return;
  const maxW = image.width / window.devicePixelRatio;
  const maxH = image.height / window.devicePixelRatio;
  const scale = Math.min(1, area.clientWidth / maxW, area.clientHeight / maxH);
  canvas.style.width = `${maxW * scale}px`;
  canvas.style.height = `${maxH * scale}px`;
}

function toImageCoords(e: PointerEvent) {
  const r = canvas.getBoundingClientRect();
  const x = ((e.clientX - r.left) * canvas.width) / r.width;
  const y = ((e.clientY - r.top) * canvas.height) / r.height;
  return {
    x: Math.max(0, Math.min(canvas.width, x)),
    y: Math.max(0, Math.min(canvas.height, y)),
  };
}

canvas.addEventListener("pointerdown", (e) => {
  if (e.button !== 0 || !image) return;
  const p = toImageCoords(e);
  if (tool === "number") {
    const n = shapes.filter((s) => s.kind === "number").length + 1;
    const radius = (8 + widthPt * 2) * window.devicePixelRatio; // 12/16/24 pt
    shapes.push({ kind: "number", x: p.x, y: p.y, n, color, radius });
    updateToolbar();
    redraw();
    return;
  }
  canvas.setPointerCapture(e.pointerId);
  drag = { x0: p.x, y0: p.y, x1: p.x, y1: p.y };
});

canvas.addEventListener("pointermove", (e) => {
  if (!drag) return;
  const p = toImageCoords(e);
  drag.x1 = p.x;
  drag.y1 = p.y;
  redraw();
});

function endDrag() {
  const r = normalized();
  drag = null;
  if (r && r.w >= 3 && r.h >= 3) shapes.push(r);
  updateToolbar();
  redraw();
}
canvas.addEventListener("pointerup", endDrag);
canvas.addEventListener("pointercancel", () => {
  drag = null;
  redraw();
});

function undo() {
  if (drag) return;
  shapes.pop();
  updateToolbar();
  redraw();
}

// --- actions ---------------------------------------------------------------

let toastTimer: number | undefined;
function toast(msg: string, error = false) {
  toastEl.textContent = msg;
  toastEl.classList.toggle("error", error);
  toastEl.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => (toastEl.hidden = true), error ? 4000 : 1000);
}

async function pngBytes(): Promise<Uint8Array> {
  const blob = await new Promise<Blob | null>((res) => canvas.toBlob(res, "image/png"));
  if (!blob) throw new Error("could not encode PNG");
  return new Uint8Array(await blob.arrayBuffer());
}

async function copy() {
  if (!image) return;
  try {
    await invoke("copy_png", await pngBytes());
    toast("Copied");
  } catch (e) {
    toast(`Copy failed: ${e}`, true);
  }
}

function defaultName() {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return (
    `Screenshot ${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}` +
    ` at ${p(d.getHours())}.${p(d.getMinutes())}.${p(d.getSeconds())}.png`
  );
}

async function saveImage() {
  if (!image) return;
  try {
    const path = await save({
      defaultPath: defaultName(),
      filters: [{ name: "PNG Image", extensions: ["png"] }],
    });
    if (!path) return;
    await invoke("save_png", await pngBytes(), {
      headers: { path: encodeURIComponent(path) },
    });
    toast("Saved");
  } catch (e) {
    toast(`Save failed: ${e}`, true);
  }
}

window.addEventListener("keydown", (e) => {
  if (!e.metaKey || e.shiftKey || e.altKey || e.ctrlKey) return;
  const key = e.key.toLowerCase();
  if (key === "z") undo();
  else if (key === "c") copy();
  else if (key === "s") saveImage();
  else return;
  e.preventDefault();
});

// --- init ------------------------------------------------------------------

async function init() {
  buildToolbar();
  try {
    const buf = await invoke<ArrayBuffer>("get_capture");
    image = await createImageBitmap(new Blob([buf], { type: "image/png" }));
  } catch (e) {
    toast(`Could not load screenshot: ${e}`, true);
    return;
  }
  canvas.width = image.width;
  canvas.height = image.height;
  layout();
  redraw();
  new ResizeObserver(layout).observe(area);
}

init();
