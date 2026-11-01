// Searches a database produced by the Ruby IndexWriter, proving the two sides
// agree on schema, metadata and vector encoding.
import { before, test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import initSqlJs from "sql.js";

import { createSearcher, semanticScale } from "../../assets/semantic-search/search-core.js";
import { DIMENSIONS, hashingVector } from "./support/hashing-embedder.js";

let searcher;
let databaseBytes;
let SQL;
const embedded = [];

before(async () => {
  const output = join(mkdtempSync(join(tmpdir(), "semantic-search-")), "index.sqlite3");
  execFileSync("bundle", ["exec", "ruby", "-Ilib", "-Itest", "test/support/build_index.rb", output], { stdio: "inherit" });

  SQL = await initSqlJs();
  databaseBytes = readFileSync(output);
  const db = new SQL.Database(databaseBytes);
  searcher = createSearcher({
    db,
    embed: async (text) => {
      embedded.push(text);
      return hashingVector(text);
    },
  });
});

test("exposes the metadata written at build time", () => {
  assert.equal(searcher.meta.model, "Xenova/all-MiniLM-L6-v2");
  assert.equal(searcher.meta.dimensions, DIMENSIONS);
  assert.equal(searcher.meta.query_prefix, "query: ");
  assert.equal(searcher.meta.min_score, null);
  assert.equal(searcher.meta.keyword_search.enabled, false);
});

test("ranks the most similar post first and returns its best passage", async () => {
  const [top] = await searcher.search("hot dutch oven loaf");
  assert.equal(top.url, "/bread/");
  assert.equal(top.title, "Baking sourdough bread");
  assert.equal(top.passage, "Bake the loaf in a hot dutch oven");
  assert.deepEqual(top.data, { tags: ["baking"] });
  assert.ok(top.score > 0.5, `score ${top.score}`);
});

test("returns one result per post, ordered by score", async () => {
  const results = await searcher.search("sourdough starter flour water");
  assert.equal(new Set(results.map((r) => r.url)).size, results.length);
  const scores = results.map((r) => r.score);
  assert.deepEqual(scores, [...scores].sort((a, b) => b - a));
});

test("applies the query prefix before embedding", async () => {
  await searcher.search("borrow checker");
  assert.equal(embedded.at(-1), "query: borrow checker");
});

test("honours limit and minScore", async () => {
  assert.equal((await searcher.search("tomatoes", { limit: 1 })).length, 1);
  const [first, second] = await searcher.search("tomatoes");
  assert.equal(first.url, "/garden/");
  const filtered = await searcher.search("tomatoes", { minScore: (first.score + second.score) / 2 });
  assert.deepEqual(filtered.map((r) => r.url), ["/garden/"]);
});

test("blank queries return nothing without embedding", async () => {
  const before = embedded.length;
  assert.deepEqual(await searcher.search("   "), []);
  assert.equal(embedded.length, before);
});

test("defaults minScore to the threshold stored in the index", async () => {
  const [first, second] = await searcher.search("tomatoes");
  const threshold = (first.score + second.score) / 2;
  const db = new SQL.Database(databaseBytes);
  db.run("UPDATE meta SET value = ? WHERE key = 'min_score'", [JSON.stringify(threshold)]);
  const strict = createSearcher({ db, embed: async (text) => hashingVector(text) });

  assert.equal(strict.meta.min_score, threshold);
  assert.deepEqual((await strict.search("tomatoes")).map((r) => r.url), ["/garden/"]);
  assert.equal((await strict.search("tomatoes", { minScore: -1 })).length, 3);
});

function searcherWithMeta(updates) {
  const db = new SQL.Database(databaseBytes);
  for (const [key, value] of Object.entries(updates)) {
    db.run("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", [key, JSON.stringify(value)]);
  }
  return createSearcher({ db, embed: async (text) => hashingVector(text) });
}

test("semanticScale maps the calibrated levels to 0 and 1", () => {
  const scale = semanticScale({ noise: 0.2, relevance: 0.8 });
  close(scale(0.2), 0);
  close(scale(0.5), 0.5);
  close(scale(0.8), 1);
  close(scale(0.95), 1.25, "not capped, so strong matches keep their order");
  close(scale(-0.3), 0);
  close(semanticScale({ noise: 0.2, relevance: null })(0.6), 0.5, "without titles, 1 is the top");
  close(semanticScale(undefined)(0.42), 0.42, "uncalibrated indexes keep the cosine");
});

function close(actual, expected, message = "") {
  assert.ok(Math.abs(actual - expected) < 1e-9, `${message} expected ${expected}, got ${actual}`);
}

test("without keyword search, scores are cosine similarities", async () => {
  for (const r of await searcher.search("borrow checker")) {
    assert.equal(r.score, r.semantic);
    assert.equal(r.keyword, 0);
    assert.deepEqual(r.matches, []);
  }
});

test("keyword search combines both scores and reports matches", async () => {
  const results = await searcher.search("Borrow checker", { keyword: { enabled: true, weight: 0.4 } });
  const rust = results.find((r) => r.url === "/rust/");
  assert.equal(results[0].url, "/rust/");
  assert.deepEqual(rust.matches, ["borrow", "checker"]);
  assert.ok(rust.keyword > 0 && rust.keyword <= 1, `keyword ${rust.keyword}`);
  // The fixture index is not calibrated, so the semantic part is the cosine itself.
  assert.ok(rust.keyword >= 0.5);
  close(rust.score, 0.6 * rust.semantic + 0.4 * rust.keyword);
  for (const r of results.filter((r) => r.url !== "/rust/")) assert.equal(r.keyword, 0);
});

test("a keyword match returns a post the semantic threshold filters out", async () => {
  const minScore = 0.99;
  assert.deepEqual(await searcher.search("borrow", { minScore }), []);

  const hits = await searcher.search("borrow", { minScore, keyword: { enabled: true } });
  assert.deepEqual(hits.map((r) => r.url), ["/rust/"]);
  assert.ok(hits[0].semantic < minScore && hits[0].keyword >= 0.5);
});

test("keyword matches below keyword.minScore neither return a post nor change its score", async () => {
  const strict = await searcher.search("borrow", { minScore: 0.99, keyword: { enabled: true, minScore: 1.01 } });
  assert.deepEqual(strict, []);

  const results = await searcher.search("borrow checker", { minScore: -1, keyword: { enabled: true, minScore: 1.01 } });
  const rust = results.find((r) => r.url === "/rust/");
  assert.ok(rust.keyword > 0, "the keyword score is still reported");
  close(rust.score, 0.7 * rust.semantic);
});

test("near matches: stems and typos", async () => {
  const keyword = { enabled: true };
  const [stem] = await searcher.search("tomato stake", { minScore: 0.99, keyword });
  assert.equal(stem.url, "/garden/");
  assert.deepEqual(stem.matches, ["tomato", "stake"]);

  const [typo] = await searcher.search("sourdouhg", { minScore: 0.99, keyword: { ...keyword, minScore: 0.1 } });
  assert.equal(typo.url, "/bread/");
  const none = await searcher.search("sourdouhg", { minScore: 0.99, keyword: { ...keyword, typoTolerance: false } });
  assert.deepEqual(none, []);
});

test("keyword settings and calibration stored in the index are the defaults", async () => {
  const configured = searcherWithMeta({
    keyword_search: { enabled: true, weight: 0.5, min_score: 0.5, stemming: true, typo_tolerance: true, k1: 1.2, b: 0.75 },
    calibration: { noise: 0.1, relevance: 0.6 },
    min_score: 0.99,
  });
  const [rust] = await configured.search("borrow");
  assert.equal(rust.url, "/rust/");
  assert.ok(rust.keyword >= 0.5);
  close(rust.score, 0.5 * Math.max(0, (rust.semantic - 0.1) / 0.5) + 0.5 * rust.keyword);

  const disabled = await configured.search("borrow", { keyword: { enabled: false } });
  assert.deepEqual(disabled, [], "options override the stored settings");
});

test("keyword search without stemming needs the exact word", async () => {
  const unstemmed = searcherWithMeta({ keyword_search: { enabled: true, stemming: false }, min_score: 0.99 });
  assert.deepEqual(await unstemmed.search("tomato"), []);
  assert.equal((await unstemmed.search("tomatoes"))[0].url, "/garden/");
});

test("each post appears once, with its best passage", async () => {
  const results = await searcher.search("loaf oven sourdough", { minScore: -1, keyword: { enabled: true } });
  assert.equal(new Set(results.map((r) => r.url)).size, results.length);
  const bread = results.find((r) => r.url === "/bread/");
  assert.equal(bread.passage, "Bake the loaf in a hot dutch oven");
});
