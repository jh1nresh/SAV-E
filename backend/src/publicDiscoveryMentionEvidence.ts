const proximityBefore = /(?:靠近|鄰近|临近|接近|距離|距离|距|離|离|近|near|nearby|opposite|nextto|acrossfrom|around)[「『“"'（(【]*$/u;
const proximityAfter = /^[「」『』“”"'【】()[\]的]*(?:附近|旁|邊的|邊上|对面|正?對面|隔壁|周邊|週邊|周边|周圍|周围|一帶|nearby|opposite|nextto|acrossfrom)/u;
const conditionalArrival = /(?:可以?|便可|即可|就能|能夠|能够|能)(?:步行|走路)?(?:抵達|抵达|到達|到达|到|前往)[「『“"'（(【]*$/u;
const deniedVisit = /(?:未曾|沒(?:有)?|没(?:有)?|從未|从未|不曾)(?:走進|走进|前往|到訪|到访|造訪|造访|去過|去过|去|到過|到过|到)[「『“"'（(【]*$/u;

export function hasDirectPublicPlaceMention(normalizedText: string, normalizedNames: string[]): boolean {
  // A shorter alias inside the full name shares the full name's context.
  const aliases = [...normalizedNames].sort((a, b) => b.length - a.length)
    .map(name => name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  const pattern = new RegExp(aliases.join("|"), "gu");
  for (const match of normalizedText.matchAll(pattern)) {
    const before = normalizedText.slice(0, match.index);
    const after = normalizedText.slice(match.index + match[0].length);
    if (!proximityBefore.test(before) && !proximityAfter.test(after)
      && !conditionalArrival.test(before) && !deniedVisit.test(before)) return true;
  }
  return false;
}
