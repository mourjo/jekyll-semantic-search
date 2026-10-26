// JavaScript twin of test/support/hashing_embedder.rb.
export const DIMENSIONS = 64;

export function hashingVector(text) {
  const vector = new Float32Array(DIMENSIONS);
  for (const word of text.toLowerCase().match(/[a-z0-9]+/g) ?? []) {
    let hash = 0;
    for (const char of word) hash = (hash * 31 + char.codePointAt(0)) % 1_000_003;
    vector[hash % DIMENSIONS] += 1;
  }
  const norm = Math.hypot(...vector);
  return norm === 0 ? vector : vector.map((v) => v / norm);
}
