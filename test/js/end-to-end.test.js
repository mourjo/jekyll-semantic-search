// Searches a database produced by the Ruby IndexWriter, proving the two sides
// agree on schema, metadata and vector encoding.
import { before, test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import initSqlJs from "sql.js";

import { createKeywordScorer, createSearcher, words } from "../../assets/semantic-search/search-core.js";
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
  assert.equal(searcher.meta.keyword_weight, 0);
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

test("words are lowercased letters and digits in any script", () => {
  assert.deepEqual(words("Rust's Borrow-Checker, 2024! Ünïcode"), ["rust", "s", "borrow", "checker", "2024", "ünïcode"]);
});

function passageId(db, content) {
  return db.exec("SELECT id FROM chunks WHERE content = ?", [content])[0].values[0][0];
}

test("keyword scores match whole words case-insensitively, including titles", () => {
  const db = new SQL.Database(databaseBytes);
  const score = createKeywordScorer(db);
  const rust = passageId(db, "The borrow checker enforces ownership at compile time");
  const garden = passageId(db, "Tomatoes need sun water and support stakes");

  assert.equal(score("BORROW Checker")(rust), 1);
  assert.equal(score("borrow")(garden), 0);
  assert.equal(score("tomato")(garden), 0, "whole words only");
  assert.equal(score("growing")(garden), 1, "title words count");
});

test("rare words outweigh common ones", () => {
  const db = new SQL.Database(databaseBytes);
  const score = createKeywordScorer(db)("flour water");
  const bread = passageId(db, "Feed the sourdough starter with flour and water");
  const garden = passageId(db, "Tomatoes need sun water and support stakes");

  assert.equal(score(bread), 1);
  assert.ok(score(garden) > 0 && score(garden) < 0.5, `garden ${score(garden)}`);
});

test("keyword matching is off unless a weight is set", async () => {
  const results = await searcher.search("borrow checker", { minScore: -1 });
  for (const r of results) {
    assert.equal(r.keyword, 0);
    assert.equal(r.score, r.semantic);
  }
});

test("keywordWeight adds the weighted keyword score", async () => {
  const [top] = await searcher.search("Borrow checker", { keywordWeight: 0.5 });
  assert.equal(top.url, "/rust/");
  assert.equal(top.keyword, 1);
  assert.ok(Math.abs(top.score - (top.semantic + 0.5)) < 1e-9, `score ${top.score}`);
});

test("keyword_weight in the index is the default, and exact matches can clear minScore", async () => {
  const rust = (await searcher.search("borrow")).find((r) => r.url === "/rust/");
  const db = new SQL.Database(databaseBytes);
  db.run("UPDATE meta SET value = '0.3' WHERE key = 'keyword_weight'");
  const weighted = createSearcher({ db, embed: async (text) => hashingVector(text) });
  const minScore = rust.semantic + 0.1;

  assert.ok(!(await searcher.search("borrow", { minScore })).some((r) => r.url === "/rust/"));
  assert.equal((await weighted.search("borrow", { minScore }))[0].url, "/rust/");
});
