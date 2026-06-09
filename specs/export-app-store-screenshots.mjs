#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const boardPath = path.join(__dirname, "app-store-screenshot-board.html");
const outputDir = path.join(__dirname, "app-store-screenshots");
const chromePath =
  process.env.CHROME_PATH ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const width = 1242;
const height = 2688;
const contactOnly = process.argv.includes("--contact-only");

const shots = [
  ["shot-01-save-any-clue", "01-save-every-place.png"],
  ["shot-02-review-before-map", "02-review-before-map.png"],
  ["shot-03-ask-private-memory", "03-ask-saved-map-first.png"],
  ["shot-04-trust-states", "04-know-what-you-can-trust.png"],
  ["shot-05-keep-clues-waiting", "05-keep-uncertain-clues-off-map.png"],
  ["shot-06-save-why-it-mattered", "06-save-why-it-mattered.png"],
  ["shot-07-plan-from-trusted-places", "07-find-dinner-from-trusted-places.png"],
  ["shot-08-private-memory", "08-private-place-memory.png"],
];

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8" });
  if (result.status !== 0) {
    const details = [result.stdout, result.stderr].filter(Boolean).join("\n");
    throw new Error(`${command} failed\n${details}`);
  }
  return result.stdout.trim();
}

function chromeScreenshot(url, outputPath, viewportHeight = height) {
  const args = [
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    "--disable-background-networking",
    "--no-first-run",
    "--no-default-browser-check",
    "--allow-file-access-from-files",
    "--run-all-compositor-stages-before-draw",
    "--virtual-time-budget=1200",
    "--force-device-scale-factor=1",
    `--user-data-dir=${userDataDir}`,
    `--window-size=${width},${viewportHeight}`,
    `--screenshot=${outputPath}`,
    url,
  ];
  const result = spawnSync(chromePath, args, {
    encoding: "utf8",
    timeout: 12000,
    killSignal: "SIGKILL",
  });
  if (result.status !== 0 && !fs.existsSync(outputPath)) {
    const details = [result.stdout, result.stderr].filter(Boolean).join("\n");
    throw new Error(`${chromePath} failed\n${details}`);
  }
}

function dimensions(filePath) {
  const output = run("sips", ["-g", "pixelWidth", "-g", "pixelHeight", filePath]);
  const widthMatch = output.match(/pixelWidth:\s*(\d+)/);
  const heightMatch = output.match(/pixelHeight:\s*(\d+)/);
  if (!widthMatch || !heightMatch) {
    throw new Error(`Failed to parse dimensions for ${filePath} from sips output:\n${output}`);
  }
  const pixelWidth = Number(widthMatch[1]);
  const pixelHeight = Number(heightMatch[1]);
  return { pixelWidth, pixelHeight };
}

function assertDimensions(filePath, expectedWidth, expectedHeight) {
  const actual = dimensions(filePath);
  if (actual.pixelWidth !== expectedWidth || actual.pixelHeight !== expectedHeight) {
    throw new Error(
      `${path.basename(filePath)} is ${actual.pixelWidth}x${actual.pixelHeight}, expected ${expectedWidth}x${expectedHeight}`,
    );
  }
}

if (!fs.existsSync(chromePath)) {
  throw new Error(`Chrome not found at ${chromePath}. Set CHROME_PATH to override.`);
}

fs.mkdirSync(outputDir, { recursive: true });

const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "save-app-store-shots-"));
const boardUrl = pathToFileURL(boardPath).href;
// Keep Chrome profile data and generated contact sheet temp files in the same per-run directory.
process.env.TMPDIR = userDataDir;

if (!contactOnly) {
  for (const [id, fileName] of shots) {
    const outputPath = path.join(outputDir, fileName);
    chromeScreenshot(`${boardUrl}?shot=${id}`, outputPath);
    assertDimensions(outputPath, width, height);
    console.log(`wrote ${path.relative(process.cwd(), outputPath)}`);
  }
}

const contactSheetPath = path.join(userDataDir, "contact-sheet.html");
const contactSheetPng = path.join(outputDir, "contact-sheet.png");
const imageTags = shots
  .map(([id, fileName], index) => {
    const src = pathToFileURL(path.join(outputDir, fileName)).href;
    const label = `${String(index + 1).padStart(2, "0")} ${id.replace(/^shot-\d+-/, "").replaceAll("-", " ")}`;
    return `<figure><img src="${src}" alt=""><figcaption>${label}</figcaption></figure>`;
  })
  .join("");

fs.writeFileSync(
  contactSheetPath,
  `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    * { box-sizing: border-box; }
    body {
      width: ${width}px;
      margin: 0;
      padding: 28px;
      background: #fff8ef;
      color: #3a2415;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
    }
    main { display: grid; grid-template-columns: repeat(4, 1fr); gap: 18px; }
    figure { margin: 0; }
    img {
      display: block;
      width: 100%;
      aspect-ratio: ${width} / ${height};
      object-fit: cover;
      border-radius: 18px;
      box-shadow: 0 10px 24px rgba(58, 36, 21, .14);
    }
    figcaption {
      margin-top: 10px;
      font-size: 17px;
      line-height: 1.12;
      font-weight: 760;
      letter-spacing: 0;
      text-transform: capitalize;
    }
  </style>
</head>
<body><main>${imageTags}</main></body>
</html>
`,
);

chromeScreenshot(pathToFileURL(contactSheetPath).href, contactSheetPng, 1500);
console.log(`wrote ${path.relative(process.cwd(), contactSheetPng)}`);
