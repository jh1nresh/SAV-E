const fs = require("node:fs");
const path = require("node:path");

const appBundleId = "com.wanderly.app";
const appClipBundleId = "com.wanderly.app.Clip";
const associatedDomain = "wanderly.app";
const distRoot = path.join(__dirname, "..", "dist");
const distDir = path.join(__dirname, "..", "dist", "_expo", "static", "js", "web");
const publicDir = path.join(__dirname, "..", "public");
const importMetaReplacement = '({ env: { MODE: "production" } })';
const replacementValues = {
  "__SAVE_API_URL__": process.env.EXPO_PUBLIC_SAVE_API_URL ?? "",
  "__SAVE_PRIVY_APP_ID__": process.env.EXPO_PUBLIC_PRIVY_APP_ID ?? "",
  "__SAVE_PRIVY_APP_CLIENT_ID__": process.env.EXPO_PUBLIC_PRIVY_APP_CLIENT_ID ?? "",
};
const publicEnvKeys = [
  "EXPO_PUBLIC_SAVE_API_URL",
  "EXPO_PUBLIC_PRIVY_APP_ID",
  "EXPO_PUBLIC_PRIVY_APP_CLIENT_ID",
];

if (!fs.existsSync(distDir)) {
  process.exit(0);
}

copyPublicAssets();
writeTripRouteFallback();
writeAppleAppSiteAssociation();

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

function copyPublicAssets() {
  if (!fs.existsSync(publicDir) || !fs.existsSync(distRoot)) return;
  fs.cpSync(publicDir, distRoot, { recursive: true });
}

function writeTripRouteFallback() {
  const indexPath = path.join(distRoot, "index.html");
  if (!fs.existsSync(indexPath)) return;

  const tripDir = path.join(distRoot, "trip");
  fs.mkdirSync(tripDir, { recursive: true });
  fs.copyFileSync(indexPath, path.join(tripDir, "index.html"));
}

function writeAppleAppSiteAssociation() {
  const rawTeamId = process.env.APPLE_TEAM_ID;
  const teamId = normalizedAppleTeamId(rawTeamId);
  if (!fs.existsSync(distRoot)) return;

  const wellKnownDir = path.join(distRoot, ".well-known");
  fs.mkdirSync(wellKnownDir, { recursive: true });

  const association = teamId
    ? buildEnabledAssociation(teamId)
    : {
        applinks: { details: [] },
        appclips: { apps: [] },
      };

  fs.writeFileSync(
    path.join(wellKnownDir, "apple-app-site-association"),
    JSON.stringify(association, null, 2),
  );
  if (teamId) {
    console.log(`Wrote apple-app-site-association for ${associatedDomain}`);
  } else if (!rawTeamId) {
    console.warn("APPLE_TEAM_ID is not set; wrote disabled apple-app-site-association placeholder");
  }
}

function normalizedAppleTeamId(value) {
  if (!value) return "";

  const teamId = value.trim().toUpperCase();
  if (/^[A-Z0-9]{10}$/.test(teamId)) {
    return teamId;
  }

  console.warn("APPLE_TEAM_ID is invalid; wrote disabled apple-app-site-association placeholder");
  return "";
}

function buildEnabledAssociation(teamId) {
  const appId = `${teamId}.${appBundleId}`;
  const appClipId = `${teamId}.${appClipBundleId}`;
  return {
    applinks: {
      details: [
        {
          appIDs: [appId],
          components: [
            {
              "/": "/trip",
              comment: "SAV-E shared trip preview links",
            },
          ],
        },
      ],
    },
    appclips: {
      apps: [appClipId],
    },
  };
}
