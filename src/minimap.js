// Select a bounded, deterministic cross-section without materializing every
// entry in every indexed range. Each range is already chronological; sampling
// the combined index space therefore preserves early and late activity in
// every substantial source instead of truncating the future.
export function sampleIndexedRanges(ranges, limit) {
  const available = ranges.map((range) => ({
    ...range,
    count: Math.max(0, range.end - range.start)
  })).filter((range) => range.count);
  const total = available.reduce((sum, range) => sum + range.count, 0);
  const count = Math.max(0, Math.min(total, Math.floor(Number(limit) || 0)));
  if (!count) return [];

  if (total <= count) {
    return available.flatMap((range) => range.entries.slice(range.start, range.end));
  }

  const offsets = count === 1
    ? [total - 1]
    : Array.from({ length: count }, (_, index) => Math.floor(index * (total - 1) / (count - 1)));
  const selected = [];
  let rangeIndex = 0;
  let rangeStart = 0;
  let rangeEnd = available[0].count;
  for (const offset of offsets) {
    while (offset >= rangeEnd && rangeIndex < available.length - 1) {
      rangeStart = rangeEnd;
      rangeIndex += 1;
      rangeEnd += available[rangeIndex].count;
    }
    const range = available[rangeIndex];
    selected.push(range.entries[range.start + offset - rangeStart]);
  }
  return selected;
}
