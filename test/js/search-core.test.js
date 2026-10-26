import { test } from "node:test";
import assert from "node:assert/strict";
import initSqlJs from "sql.js";

import { cosineSimilarity, createSearcher, readMeta, toBlob, toFloat32 } from "../../assets/semantic-search/search-core.js";

const SQL = await initSqlJs();

test("cosineSimilarity of identical, orthogonal and opposite vectors", () => {
  assert.equal(cosineSimilarity([1, 2], [1, 2]).toFixed(6), "1.000000");
  assert.equal(cosineSimilarity([1, 0], [0, 1]), 0);
  assert.equal(cosineSimilarity([1, 0], [-1, 0]), -1);
});

test("cosineSimilarity treats zero vectors as dissimilar", () => {
  assert.equal(cosineSimilarity([0, 0], [1, 0]), 0);
});

test("cosineSimilarity rejects mismatched dimensions", () => {
  assert.throws(() => cosineSimilarity([1], [1, 2]), /Dimension mismatch/);
});

test("toBlob and toFloat32 round-trip little-endian float32", () => {
  const blob = toBlob([0.5, -0.25]);
  assert.deepEqual([...blob], [0, 0, 0, 63, 0, 0, 128, 190]);
  assert.deepEqual([...toFloat32(blob)], [0.5, -0.25]);
});

test("toFloat32 copies unaligned views", () => {
  const bytes = new Uint8Array(9);
  bytes.set(toBlob([1.5, 2]), 1);
  assert.deepEqual([...toFloat32(bytes.subarray(1))], [1.5, 2]);
});

test("readMeta parses JSON values", () => {
  const db = new SQL.Database();
  db.run("CREATE TABLE meta (key TEXT, value TEXT)");
  db.run(`INSERT INTO meta VALUES ('model', '"m"'), ('dimensions', '3'), ('normalize', 'true')`);
  assert.deepEqual(readMeta(db), { model: "m", dimensions: 3, normalize: true });
});

test("createSearcher rejects unknown schema versions", () => {
  const db = new SQL.Database();
  db.run("CREATE TABLE meta (key TEXT, value TEXT)");
  db.run(`INSERT INTO meta VALUES ('schema_version', '99')`);
  assert.throws(() => createSearcher({ db, embed: async () => [] }), /Unsupported search index schema 99/);
});
