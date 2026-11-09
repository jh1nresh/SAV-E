import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export type SourceRecoveryConfigStatus = {
  ready: boolean;
  keyframeExtractionEnabled: boolean;
  videoVenueAnalysis: { enabled: boolean; ready: boolean };
  ocr: {
    enabled: boolean;
    command: string;
    ready: boolean;
  };
  asr: {
    enabled: boolean;
    command: string;
    model: string;
    ready: boolean;
  };
  externalRubric: {
    configured: boolean;
    tokenConfigured: boolean;
    ready: boolean;
  };
  errors: string[];
  warnings: string[];
};

export async function readSourceRecoveryConfigStatus(
  env: NodeJS.ProcessEnv = process.env,
): Promise<SourceRecoveryConfigStatus> {
  const keyframeExtractionEnabled = env.SAVE_ENABLE_SERVER_KEYFRAME_EXTRACTION === "true";
  const ocrEnabled = env.SAVE_ENABLE_SERVER_OCR === "true";
  const asrEnabled = env.SAVE_ENABLE_SERVER_ASR === "true";
  const ocrCommand = env.SAVE_SERVER_OCR_COMMAND?.trim() || "tesseract";
  const asrCommand = env.SAVE_SERVER_ASR_COMMAND?.trim() || "whisper";
  const asrModel = env.SAVE_SERVER_ASR_MODEL?.trim() || "base";
  const rubricURL = env.SAVE_EVIDENCE_RUBRIC_URL?.trim();
  const errors: string[] = [];
  const warnings: string[] = [];

  const videoEnabled = env.SAVE_ENABLE_VIDEO_VENUE_ANALYSIS === "true";
  let videoReady = true;
  if (videoEnabled) {
    if (!(env.GEMINI_API_KEY?.trim() || env.GOOGLE_GEMINI_API_KEY?.trim())) {
      errors.push("Video venue analysis requires the existing Gemini key");
      videoReady = false;
    }
    for (const command of [env.SAVE_VIDEO_YTDLP_COMMAND ?? "yt-dlp", env.SAVE_VIDEO_FFMPEG_COMMAND ?? "ffmpeg", env.SAVE_VIDEO_FFPROBE_COMMAND ?? "ffprobe"]) {
      if (!await executableExists(command)) {
        errors.push("Video venue analysis is missing a required executable");
        videoReady = false;
      }
    }
  }

  const ocrReady = !ocrEnabled || await executableExists(ocrCommand);
  if (ocrEnabled && !ocrReady) errors.push(`SAVE_ENABLE_SERVER_OCR=true but ${ocrCommand} is not executable`);

  const asrReady = !asrEnabled || await executableExists(asrCommand);
  if (asrEnabled && !asrReady) errors.push(`SAVE_ENABLE_SERVER_ASR=true but ${asrCommand} is not executable`);

  const rubricReady = !rubricURL || isSafeHTTPSRubricURL(rubricURL);
  if (rubricURL && !rubricReady) {
    errors.push("SAVE_EVIDENCE_RUBRIC_URL must be an https public URL");
  }
  if (rubricURL && !env.SAVE_EVIDENCE_RUBRIC_TOKEN) {
    warnings.push("SAVE_EVIDENCE_RUBRIC_URL is configured without SAVE_EVIDENCE_RUBRIC_TOKEN");
  }
  if ((ocrEnabled || asrEnabled) && !keyframeExtractionEnabled) {
    errors.push("OCR/ASR requires SAVE_ENABLE_SERVER_KEYFRAME_EXTRACTION=true");
  }

  return {
    ready: errors.length === 0,
    keyframeExtractionEnabled,
    videoVenueAnalysis: { enabled: videoEnabled, ready: videoReady },
    ocr: {
      enabled: ocrEnabled,
      command: ocrCommand,
      ready: ocrReady,
    },
    asr: {
      enabled: asrEnabled,
      command: asrCommand,
      model: asrModel,
      ready: asrReady,
    },
    externalRubric: {
      configured: Boolean(rubricURL),
      tokenConfigured: Boolean(env.SAVE_EVIDENCE_RUBRIC_TOKEN),
      ready: rubricReady,
    },
    errors,
    warnings,
  };
}

async function executableExists(command: string): Promise<boolean> {
  if (!command.trim()) return false;
  if (command.includes("/")) {
    try {
      await access(command, constants.X_OK);
      return true;
    } catch {
      return false;
    }
  }
  try {
    await execFileAsync("which", [command], { timeout: 2_000, maxBuffer: 20_000 });
    return true;
  } catch {
    return false;
  }
}

function isSafeHTTPSRubricURL(value: string): boolean {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return false;
  }
  if (url.protocol !== "https:") return false;
  const host = url.hostname.toLowerCase();
  if (!host || host === "localhost" || host.endsWith(".localhost")) return false;
  if (isPrivateIPv4(host)) return false;
  return true;
}

function isPrivateIPv4(host: string): boolean {
  return [
    /^0\./,
    /^10\./,
    /^127\./,
    /^169\.254\./,
    /^172\.(1[6-9]|2[0-9]|3[0-1])\./,
    /^192\.168\./,
  ].some((pattern) => pattern.test(host));
}
