#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const specDir = path.dirname(fileURLToPath(import.meta.url));
const boardPath = path.join(specDir, "app-store-screenshot-board-v5.html");
const chromePath = process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const outputDir = path.join(specDir, "app-store-screenshots", "v5");
const iphone69OutputDir = path.join(specDir, "app-store-screenshots", "v5-iphone-69");
const ipadOutputDir = path.join(specDir, "app-store-screenshots", "v5-ipad-13");
const contactOnly = process.argv.includes("--contact-only");

const shots = [
  ["shot-01-home", "01-stop-losing-places.png"],
  ["shot-02-capture", "02-paste-a-link.png"],
  ["shot-03-review", "03-confirm-before-map.png"],
  ["shot-04-map", "04-private-map-stamps.png"],
  ["shot-05-passport", "05-place-passport.png"],
];

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error([`${command} failed`, result.stdout, result.stderr].filter(Boolean).join("\n"));
  }
  return result.stdout.trim();
}

function screenshot(url, outputPath, width, height, userDataDir) {
  const result = spawnSync(chromePath, [
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    "--disable-background-networking",
    "--no-first-run",
    "--no-default-browser-check",
    "--allow-file-access-from-files",
    "--run-all-compositor-stages-before-draw",
    "--virtual-time-budget=1600",
    "--force-device-scale-factor=1",
    `--user-data-dir=${userDataDir}`,
    `--window-size=${width},${height}`,
    `--screenshot=${outputPath}`,
    url,
  ], { encoding: "utf8", timeout: 15000, killSignal: "SIGKILL" });

  if (result.status !== 0 && !fs.existsSync(outputPath)) {
    throw new Error(["Chrome screenshot failed", result.stdout, result.stderr].filter(Boolean).join("\n"));
  }
}

function dimensions(filePath) {
  const output = run("sips", ["-g", "pixelWidth", "-g", "pixelHeight", filePath]);
  return {
    width: Number(output.match(/pixelWidth:\s*(\d+)/)?.[1]),
    height: Number(output.match(/pixelHeight:\s*(\d+)/)?.[1]),
  };
}

function assertDimensions(filePath, width, height) {
  const actual = dimensions(filePath);
  if (actual.width !== width || actual.height !== height) {
    throw new Error(`${path.basename(filePath)} is ${actual.width}x${actual.height}; expected ${width}x${height}`);
  }
}

function writeContactSheet(outputPath, imageDir, userDataDir, imageWidth, imageHeight, sheetHeight) {
  const htmlPath = path.join(userDataDir, `${path.basename(imageDir)}-contact-sheet.html`);
  const cards = shots.map(([id, fileName], index) => {
    const source = pathToFileURL(path.join(imageDir, fileName)).href;
    const label = `${String(index + 1).padStart(2, "0")} ${id.replace(/^shot-\d+-/, "")}`;
    return `<figure><img src="${source}"><figcaption>${label}</figcaption></figure>`;
  }).join("");
  fs.writeFileSync(htmlPath, `<!doctype html><meta charset="utf-8"><style>
    *{box-sizing:border-box}html,body{margin:0;width:1500px;height:${sheetHeight}px;overflow:hidden}body{padding:42px;background:#fff9ef;color:#3a2415;font-family:system-ui,-apple-system,sans-serif}main{display:grid;grid-template-columns:repeat(3,1fr);gap:28px}figure{margin:0}img{display:block;width:100%;aspect-ratio:${imageWidth}/${imageHeight};object-fit:contain;border-radius:22px;box-shadow:0 14px 30px rgba(58,36,21,.18)}figcaption{padding-top:12px;font-size:21px;font-weight:800;text-transform:capitalize}
  </style><main>${cards}</main>`);
  screenshot(pathToFileURL(htmlPath).href, outputPath, 1500, sheetHeight, userDataDir);
}

if (!fs.existsSync(chromePath)) throw new Error(`Chrome not found at ${chromePath}`);
if (!fs.existsSync(boardPath)) throw new Error(`Board not found at ${boardPath}`);

fs.mkdirSync(outputDir, { recursive: true });
fs.mkdirSync(iphone69OutputDir, { recursive: true });
fs.mkdirSync(ipadOutputDir, { recursive: true });
const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "save-app-store-v5-"));
const boardUrl = pathToFileURL(boardPath).href;

try {
  if (!contactOnly) {
    for (const [id, fileName] of shots) {
      const iphonePath = path.join(outputDir, fileName);
      screenshot(`${boardUrl}?shot=${id}`, iphonePath, 1242, 2688, userDataDir);
      assertDimensions(iphonePath, 1242, 2688);
      console.log(`wrote ${path.relative(process.cwd(), iphonePath)}`);

      const iphone69Path = path.join(iphone69OutputDir, fileName);
      screenshot(`${boardUrl}?shot=${id}&platform=iphone69`, iphone69Path, 1260, 2736, userDataDir);
      assertDimensions(iphone69Path, 1260, 2736);
      console.log(`wrote ${path.relative(process.cwd(), iphone69Path)}`);

      const ipadPath = path.join(ipadOutputDir, fileName);
      screenshot(`${boardUrl}?shot=${id}&platform=ipad`, ipadPath, 2048, 2732, userDataDir);
      assertDimensions(ipadPath, 2048, 2732);
      console.log(`wrote ${path.relative(process.cwd(), ipadPath)}`);
    }
  }

  writeContactSheet(path.join(outputDir, "contact-sheet.png"), outputDir, userDataDir, 1242, 2688, 2200);
  console.log(`wrote ${path.relative(process.cwd(), path.join(outputDir, "contact-sheet.png"))}`);
  writeContactSheet(path.join(iphone69OutputDir, "contact-sheet.png"), iphone69OutputDir, userDataDir, 1260, 2736, 2200);
  console.log(`wrote ${path.relative(process.cwd(), path.join(iphone69OutputDir, "contact-sheet.png"))}`);
  writeContactSheet(path.join(ipadOutputDir, "contact-sheet.png"), ipadOutputDir, userDataDir, 2048, 2732, 1550);
  console.log(`wrote ${path.relative(process.cwd(), path.join(ipadOutputDir, "contact-sheet.png"))}`);
} finally {
  fs.rmSync(userDataDir, { recursive: true, force: true });
}
