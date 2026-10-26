// Environment-independent search logic, shared by the browser runtime and tests.
// Works with any sql.js Database; `embed` turns a string into a vector.

export const SCHEMA_VERSION = 1;

export const SEARCH_SQL = `
  SELECT d.id, d.url, d.title, d.date, d.excerpt, d.data,
         c.content AS passage,
         MAX(cosine_similarity(c.embedding, $query)) AS score
  FROM chunks c
  JOIN documents d ON d.id = c.document_id
  GROUP BY d.id
  HAVING score >= $minScore
  ORDER BY score DESC
  LIMIT $limit
`;

// Embeddings are little-endian float32 blobs. sql.js hands blobs over as
// Uint8Array views that may not be 4-byte aligned, in which case we copy.
export function toFloat32(blob) {
  if (blob.byteOffset % 4 === 0) {
    return new Float32Array(blob.buffer, blob.byteOffset, blob.byteLength / 4);
  }
  return new Float32Array(blob.slice().buffer);
}

export function toBlob(vector) {
  const floats = vector instanceof Float32Array ? vector : Float32Array.from(vector);
  return new Uint8Array(floats.buffer, floats.byteOffset, floats.byteLength);
}

export function cosineSimilarity(a, b) {
  if (a.length !== b.length) {
    throw new Error(`Dimension mismatch: ${a.length} vs ${b.length}`);
  }
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return normA === 0 || normB === 0 ? 0 : dot / Math.sqrt(normA * normB);
}

export function readMeta(db) {
  const meta = {};
  const [result] = db.exec("SELECT key, value FROM meta");
  for (const [key, value] of result ? result.values : []) {
    meta[key] = JSON.parse(value);
  }
  return meta;
}

function registerFunctions(db) {
  db.create_function("cosine_similarity", (a, b) => cosineSimilarity(toFloat32(a), toFloat32(b)));
}

function rows(statement) {
  const out = [];
  while (statement.step()) {
    const row = statement.getAsObject();
    row.data = row.data ? JSON.parse(row.data) : {};
    out.push(row);
  }
  return out;
}

export function createSearcher({ db, embed }) {
  const meta = readMeta(db);
  if (meta.schema_version !== SCHEMA_VERSION) {
    throw new Error(`Unsupported search index schema ${meta.schema_version}; expected ${SCHEMA_VERSION}`);
  }
  registerFunctions(db);

  async function search(query, { limit = 10, minScore = -1 } = {}) {
    const text = String(query ?? "").trim();
    if (!text) return [];

    const vector = await embed(`${meta.query_prefix ?? ""}${text}`);
    if (vector.length !== meta.dimensions) {
      throw new Error(`Query embedding has ${vector.length} dimensions; index has ${meta.dimensions}`);
    }

    const statement = db.prepare(SEARCH_SQL);
    try {
      statement.bind({ $query: toBlob(vector), $limit: limit, $minScore: minScore });
      return rows(statement);
    } finally {
      statement.free();
    }
  }

  return { meta, search };
}
