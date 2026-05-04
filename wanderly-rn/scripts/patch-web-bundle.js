const fs = require("node:fs");
const path = require("node:path");

const distDir = path.join(__dirname, "..", "dist", "_expo", "static", "js", "web");
const importMetaReplacement = '({ env: { MODE: "production" } })';
const replacementValues = {
  "__WANDERLY_API_URL__": process.env.EXPO_PUBLIC_WANDERLY_API_URL ?? "",
  "__WANDERLY_PRIVY_APP_ID__": process.env.EXPO_PUBLIC_PRIVY_APP_ID ?? "",
  "__WANDERLY_PRIVY_APP_CLIENT_ID__": process.env.EXPO_PUBLIC_PRIVY_APP_CLIENT_ID ?? "",
};
const publicEnvKeys = [
  "EXPO_PUBLIC_WANDERLY_API_URL",
  "EXPO_PUBLIC_PRIVY_APP_ID",
  "EXPO_PUBLIC_PRIVY_APP_CLIENT_ID",
];

if (!fs.existsSync(distDir)) {
  process.exit(0);
}

for (const fileName of fs.readdirSync(distDir)) {
  if (!fileName.endsWith(".js")) continue;

  const filePath = path.join(distDir, fileName);
  let source = fs.readFileSync(filePath, "utf8");
  let changed = false;

  for (const [placeholder, value] of Object.entries(replacementValues)) {
    if (!source.includes(placeholder)) continue;
    source = source.replaceAll(placeholder, value);
    changed = true;
  }

  for (const key of publicEnvKeys) {
    if (!source.includes(`process.env.${key}`)) continue;
    source = source.replaceAll(`process.env.${key}`, JSON.stringify(process.env[key] ?? ""));
    changed = true;
  }

  if (source.includes("import.meta")) {
    source = source.replaceAll("import.meta", importMetaReplacement);
    changed = true;
  }

  if (changed) {
    fs.writeFileSync(filePath, source);
    console.log(`Patched web bundle ${fileName}`);
  }
}
