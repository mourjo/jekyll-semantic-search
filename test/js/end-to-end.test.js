// Searches a database produced by the Ruby IndexWriter, proving the two sides
// agree on schema, metadata and vector encoding.
import { before, test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import initSqlJs from "sql.js";

import { createSearcher } from "../../assets/semantic-search/search-core.js";
import { DIMENSIONS, hashingVector } from "./support/hashing-embedder.js";

let searcher;
const embedded = [];

before(async () => {
  const output = join(mkdtempSync(join(tmpdir(), "semantic-search-")), "index.sqlite3");
  execFileSync("bundle", ["exec", "ruby", "-Ilib", "-Itest", "test/support/build_index.rb", output], { stdio: "inherit" });

  const SQL = await initSqlJs();
  const db = new SQL.Database(readFileSync(output));
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
