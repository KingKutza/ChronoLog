export const MINIMAP_GRID_ROWS = 11;
export const MINIMAP_DOTS_PER_MAGNITUDE = 2;

const IMPORTANCE_MULTIPLIER = Object.freeze({
  standard: 1,
  important: 1.6,
  landmark: 2.5
});

export function minimapEventMagnitude({ durationDays = 0, stapleCount = 0, importance = "standard" } = {}) {
  const duration = Math.max(0, Number(durationDays) || 0);
  const staples = Math.max(0, Math.floor(Number(stapleCount) || 0));
  const multiplier = IMPORTANCE_MULTIPLIER[importance] || IMPORTANCE_MULTIPLIER.standard;
  return (1 + staples + duration) * multiplier;
}

function verticalOrder(rows, center) {
  const order = [];
  for (let distance = 1; distance < rows; distance += 1) {
    if (center - distance >= 0) order.push(center - distance);
    if (center + distance < rows) order.push(center + distance);
  }
  return order;
}

// Every column owns an always-lit center dot. Activity first grows vertically
// around its date; only after that column fills does it spill into neighboring
// columns. The fixed dots-per-magnitude scale makes equal event sets look equal
// when the minimap window moves.
export function minimapDotGrid(magnitudes, options = {}) {
  const columns = magnitudes.length;
  const rows = Math.max(3, Math.floor(Number(options.rows) || MINIMAP_GRID_ROWS));
  const dotsPerMagnitude = Math.max(0.1, Number(options.dotsPerMagnitude) || MINIMAP_DOTS_PER_MAGNITUDE);
  const center = Math.floor(rows / 2);
  const cells = new Uint8Array(columns * rows);
  for (let column = 0; column < columns; column += 1) cells[center * columns + column] = 1;

  const rowOrder = verticalOrder(rows, center);
  const sources = Array.from(magnitudes, (magnitude, column) => ({
    column,
    magnitude: Math.max(0, Number(magnitude) || 0)
  })).filter((source) => source.magnitude > 0)
    .sort((left, right) => right.magnitude - left.magnitude || left.column - right.column);

  for (const source of sources) {
    let remaining = Math.ceil(source.magnitude * dotsPerMagnitude);
    for (let distance = 0; remaining > 0 && distance < columns; distance += 1) {
      const offsets = distance === 0 ? [0] : [-distance, distance];
      for (const offset of offsets) {
        const column = source.column + offset;
        if (column < 0 || column >= columns) continue;
        for (const row of rowOrder) {
          const index = row * columns + column;
          if (cells[index]) continue;
          cells[index] = 1;
          remaining -= 1;
          if (!remaining) break;
        }
        if (!remaining) break;
      }
    }
  }
  return { cells, columns, rows, center };
}
