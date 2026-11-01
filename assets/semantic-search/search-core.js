// Environment-independent search logic, shared by the browser runtime and tests.
// Works with any sql.js Database; `embed` turns a string into a vector.

export const SCHEMA_VERSION = 1;

// Each passage scores cosine similarity plus a weighted keyword score; a post
// takes its best passage. SQLite fills the bare columns (passage, semantic,
// keyword) from the row that produced MAX(). MATERIALIZED keeps SQLite from
// inlining the CTE and computing the similarity twice per passage.
export const SEARCH_SQL = `
  WITH scored AS MATERIALIZED (
    SELECT c.document_id, c.content,
           cosine_similarity(c.embedding, $query) AS semantic,
           keyword_score(c.id) AS keyword
    FROM chunks c
  )
  SELECT d.id, d.url, d.title, d.date, d.excerpt, d.data,
         s.content AS passage, s.semantic, s.keyword,
         MAX(s.semantic + $keywordWeight * s.keyword) AS score
  FROM scored s
  JOIN documents d ON d.id = s.document_id
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

// Lowercase words made of letters and digits, in any script.
export function words(text) {
  return String(text ?? "").toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];
}

// Case-insensitive whole-word matching between a query and each passage (plus
// its post's title). A passage scores the share of the query's words it
// contains, each word weighted by how rare it is across passages (BM25's idf),
// so matching "tokio" counts for far more than matching "how". Scores are in [0, 1].
export function createKeywordScorer(db) {
  const passages = new Map();
  const documentFrequency = new Map();
  const [result] = db.exec(
    "SELECT c.id, c.content, d.title FROM chunks c JOIN documents d ON d.id = c.document_id"
  );
  for (const [id, content, title] of result ? result.values : []) {
    const set = new Set([...words(content), ...words(title)]);
    passages.set(id, set);
    for (const word of set) documentFrequency.set(word, (documentFrequency.get(word) ?? 0) + 1);
  }
  const count = passages.size;
  const idf = (word) => {
    const df = documentFrequency.get(word) ?? 0;
    return Math.log(1 + (count - df + 0.5) / (df + 0.5));
  };

  // Returns a function from passage id to score for one query.
  return (query) => {
    const weighted = [...new Set(words(query))].map((word) => [word, idf(word)]);
    const total = weighted.reduce((sum, [, weight]) => sum + weight, 0);
    if (total === 0) return () => 0;
    return (id) => {
      const set = passages.get(id);
      if (!set) return 0;
      let matched = 0;
      for (const [word, weight] of weighted) if (set.has(word)) matched += weight;
      return matched / total;
    };
  };
}

export function readMeta(db) {
  const meta = {};
  const [result] = db.exec("SELECT key, value FROM meta");
  for (const [key, value] of result ? result.values : []) {
    meta[key] = JSON.parse(value);
  }
  return meta;
}

function registerFunctions(db, keywordScore) {
  db.create_function("cosine_similarity", (a, b) => cosineSimilarity(toFloat32(a), toFloat32(b)));
  db.create_function("keyword_score", (id) => keywordScore(id));
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
  // Scores keyword matches for the query being run; built on first use.
  let keywordScorer;
  let keywordScore = () => 0;
  registerFunctions(db, (id) => keywordScore(id));

  // minScore and keywordWeight default to the values chosen at build time
  // (`min_score` and `keyword_weight` in _config.yml); minScore -1 shows every result.
  async function search(
    query,
    { limit = 10, minScore = meta.min_score ?? -1, keywordWeight = meta.keyword_weight ?? 0 } = {}
  ) {
    const text = String(query ?? "").trim();
    if (!text) return [];

    const vector = await embed(`${meta.query_prefix ?? ""}${text}`);
    if (vector.length !== meta.dimensions) {
      throw new Error(`Query embedding has ${vector.length} dimensions; index has ${meta.dimensions}`);
    }

    if (keywordWeight) {
      keywordScorer ??= createKeywordScorer(db);
      keywordScore = keywordScorer(text);
    }
    const statement = db.prepare(SEARCH_SQL);
    try {
      statement.bind({
        $query: toBlob(vector),
        $limit: limit,
        $minScore: minScore,
        $keywordWeight: keywordWeight,
      });
      return rows(statement);
    } finally {
      statement.free();
      keywordScore = () => 0;
    }
  }

  return { meta, search };
}
