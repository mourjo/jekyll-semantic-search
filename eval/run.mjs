// Measures search quality on a built index against labelled queries.
//
//   node eval/run.mjs INDEX.sqlite3 QUERIES.json [--sweep] [--json]
//
// Queries are embedded once with the index's model through Transformers.js,
// the same code path as the browser, then scored under each configuration.
//
// A query's acceptable answers are the pages whose URL contains one of
// `expect`, plus, when `term` is given, every page whose text contains that
// word. For `unrelated` queries the right answer is no results at all.
//
// Metrics per kind of query:
//   top1    the first result is acceptable
//   top3    an acceptable page is in the first three
//   found   an acceptable page is returned at all (limit 10)
//   empty   (unrelated queries) share of queries returning nothing
//   noise   (unrelated queries) mean number of results returned
import { readFileSync } from "node:fs";
import initSqlJs from "sql.js";
import { pipeline } from "@huggingface/transformers";

import { createSearcher } from "../assets/semantic-search/search-core.js";

const [indexPath, queriesPath, ...flags] = process.argv.slice(2);
if (!indexPath || !queriesPath) {
  console.error("usage: node eval/run.mjs INDEX.sqlite3 QUERIES.json [--sweep] [--json]");
  process.exit(1);
}

const SQL = await initSqlJs();
const db = new SQL.Database(readFileSync(indexPath));
const { queries } = JSON.parse(readFileSync(queriesPath, "utf8"));

const meta = Object.fromEntries(
  db.exec("SELECT key, value FROM meta")[0].values.map(([k, v]) => [k, JSON.parse(v)])
);
const extractor = await pipeline("feature-extraction", meta.model, { dtype: meta.dtype });
const vectors = new Map();
const embed = async (text) => {
  if (!vectors.has(text)) {
    vectors.set(text, (await extractor(text, { pooling: meta.pooling, normalize: meta.normalize })).data);
  }
  return vectors.get(text);
};
const searcher = createSearcher({ db, embed });

// Page text for resolving `term`.
const pages = new Map();
for (const [url, title, content] of db.exec(
  "SELECT d.url, d.title, c.content FROM chunks c JOIN documents d ON d.id = c.document_id"
)[0].values) {
  pages.set(url, `${pages.get(url) ?? title ?? ""} ${content ?? ""}`.toLowerCase());
}
const acceptable = (query) => {
  const urls = new Set();
  for (const [url, text] of pages) {
    if ((query.expect ?? []).some((fragment) => url.toLowerCase().includes(fragment.toLowerCase()))) urls.add(url);
    if (query.term && new RegExp(`(^|[^\\p{L}\\p{N}])${query.term}($|[^\\p{L}\\p{N}])`, "u").test(text)) urls.add(url);
  }
  return urls;
};

for (const query of queries) {
  if (query.kind !== "unrelated" && acceptable(query).size === 0) {
    console.error(`No page matches the labels of "${query.q}"`);
    process.exit(1);
  }
}

const configurations = [
  ["semantic only", { keyword: { enabled: false } }],
  ["hybrid (defaults)", { keyword: { enabled: true } }],
];
if (flags.includes("--sweep")) {
  for (const weight of [0.2, 0.3, 0.5]) {
    for (const minScore of [0.4, 0.5, 0.6]) {
      configurations.push([`w=${weight} kmin=${minScore}`, { keyword: { enabled: true, weight, minScore } }]);
    }
  }
}

const KINDS = ["paraphrase", "exact", "inflection", "typo", "unrelated"];
const report = [];
for (const [name, options] of configurations) {
  const totals = Object.fromEntries(KINDS.map((k) => [k, { n: 0, top1: 0, top3: 0, found: 0, empty: 0, noise: 0 }]));
  const misses = [];
  for (const query of queries) {
    const results = await searcher.search(query.q, { limit: 10, ...options });
    const t = totals[query.kind];
    t.n++;
    if (query.kind === "unrelated") {
      if (results.length === 0) t.empty++;
      else misses.push(`${query.q} → ${results[0].title} (score ${results[0].score.toFixed(2)}, cosine ${results[0].semantic.toFixed(2)}, keyword ${results[0].keyword.toFixed(2)} on [${results[0].matches}])`);
      t.noise += results.length;
      continue;
    }
    const ok = acceptable(query);
    const rank = results.findIndex((r) => ok.has(r.url));
    if (rank === 0) t.top1++;
    if (rank >= 0 && rank < 3) t.top3++;
    if (rank >= 0) t.found++;
    else misses.push(`${query.q} → ${results[0] ? results[0].title : "(nothing)"}`);
  }
  report.push({ name, totals, misses });
}

if (flags.includes("--diff")) {
  // Queries whose first result differs between semantic-only and hybrid search.
  const fmt = (r) => (r ? `${r.title} (cos ${r.semantic.toFixed(3)}, kw ${r.keyword.toFixed(2)} [${r.matches}])` : "nothing");
  for (const query of queries) {
    const [a] = await searcher.search(query.q, { limit: 10, ...configurations[0][1] });
    const [b] = await searcher.search(query.q, { limit: 10, ...configurations[1][1] });
    if (a?.url !== b?.url) {
      const ok = acceptable(query);
      const mark = (r) => (query.kind === "unrelated" ? (r ? "✗" : "✓") : r && ok.has(r.url) ? "✓" : "✗");
      console.log(`[${query.kind}] ${query.q}\n   semantic ${mark(a)} ${fmt(a)}\n   hybrid   ${mark(b)} ${fmt(b)}`);
    }
  }
  process.exit(0);
}

if (flags.includes("--json")) {
  console.log(JSON.stringify({ index: indexPath, model: meta.model, min_score: meta.min_score, report }));
} else {
  const pct = (x, n) => (n ? `${Math.round((100 * x) / n)}%` : "–");
  console.log(`${queriesPath}: ${meta.model}, min_score ${meta.min_score}\n`);
  console.log("| configuration | paraphrase top1/top3/found | exact | inflection | typo | unrelated: empty / mean results |");
  console.log("| --- | --- | --- | --- | --- | --- |");
  for (const { name, totals: t } of report) {
    const cell = (k) => `${pct(t[k].top1, t[k].n)} / ${pct(t[k].top3, t[k].n)} / ${pct(t[k].found, t[k].n)}`;
    const u = t.unrelated;
    console.log(
      `| ${name} | ${cell("paraphrase")} | ${cell("exact")} | ${cell("inflection")} | ${cell("typo")} | ` +
        `${pct(u.empty, u.n)} / ${(u.noise / Math.max(u.n, 1)).toFixed(1)} |`
    );
  }
  if (flags.includes("--misses")) {
    for (const { name, misses } of report.slice(0, 2)) console.log(`\n${name} misses:\n  ${misses.join("\n  ")}`);
  }
}
