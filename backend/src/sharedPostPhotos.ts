import { FriendRatingError } from "./friendRatings.js";

export const sharedPostBodyMaxBytes = 3 * 349528 + 8192;
const invalid = () => new FriendRatingError("Choose up to 3 JPEG photos, each at most 256 KiB and 1600 pixels per side", 400);

// Photos are normalized by iOS before publishing. Strip metadata again at the
// server boundary; never accept URLs, original HEIC files or arbitrary blobs.
export function sharedPostPhotos(value: unknown): Buffer[] | undefined {
  if (value === undefined) return undefined; // Older clients keep existing media.
  if (!Array.isArray(value) || value.length > 3) throw invalid();
  return value.map(value => {
    if (typeof value !== "string" || value.length > 349528 || !/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw invalid();
    const data = Buffer.from(value, "base64");
    if (data.length > 262144 || data.toString("base64") !== value) throw invalid();
    return sanitizedJPEG(data);
  });
}

export function sanitizedJPEG(data: Buffer): Buffer {
  if (data.length < 4 || data.readUInt16BE(0) !== 0xffd8) throw invalid();
  const parts = [data.subarray(0, 2)];
  let offset = 2, frame = false;
  while (offset + 4 <= data.length) {
    if (data[offset] !== 0xff) throw invalid();
    const marker = data[offset + 1], length = data.readUInt16BE(offset + 2);
    const end = offset + 2 + length;
    if (length < 2 || end > data.length) throw invalid();
    if (marker === 0xc0) {
      if (length < 8 || frame) throw invalid();
      const height = data.readUInt16BE(offset + 5), width = data.readUInt16BE(offset + 7);
      if (data[offset + 4] !== 8 || width < 1 || height < 1 || width > 1600 || height > 1600) throw invalid();
      frame = true;
    } else if (![0xc4, 0xdb, 0xdd, 0xda, 0xfe].includes(marker) && !(marker >= 0xe0 && marker <= 0xef)) {
      throw invalid(); // Baseline JPEG only, as emitted by the composer.
    }
    if (marker === 0xda) {
      if (!frame) throw invalid();
      // Single baseline scan: permit escaped FF and restart markers, require
      // the final EOI, and reject trailing payloads or additional metadata.
      for (let index = end; index < data.length - 1; index++) {
        if (data[index] !== 0xff) continue;
        const next = data[++index];
        if (next === 0 || (next >= 0xd0 && next <= 0xd7)) continue;
        if (next === 0xd9 && index === data.length - 1) {
          parts.push(data.subarray(offset));
          return Buffer.concat(parts);
        }
        throw invalid();
      }
      throw invalid();
    }
    if (marker !== 0xfe && !(marker >= 0xe0 && marker <= 0xef)) parts.push(data.subarray(offset, end));
    offset = end;
  }
  throw invalid();
}
