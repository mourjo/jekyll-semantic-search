// Checks that real Hugging Face models embed identically at build time (the
// Ruby InformersEmbedder) and in the browser (Transformers.js), and that they
// rank an obvious match first. Downloads every model, so it only runs when
// SEMANTIC_SEARCH_MODELS is set: "all", or a comma-separated list of model ids.
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";

const MODELS = [
  { model: "Xenova/all-MiniLM-L6-v2" },
  { model: "Xenova/all-MiniLM-L12-v2" },
  // Its q8 build and browser vectors agree to only ≈0.92; fp32 matches exactly.
  { model: "Xenova/all-mpnet-base-v2", dtype: "fp32" },
  { model: "Xenova/paraphrase-multilingual-MiniLM-L12-v2" },
  { model: "Xenova/bge-small-en-v1.5", pooling: "cls" },
  { model: "Xenova/bge-base-en-v1.5", pooling: "cls" },
  { model: "Xenova/gte-small" },
  { model: "Xenova/e5-small-v2", document_prefix: "passage: ", query_prefix: "query: " },
  { model: "Xenova/multilingual-e5-small", document_prefix: "passage: ", query_prefix: "query: " },
  {
    model: "nomic-ai/nomic-embed-text-v1.5",
    document_prefix: "search_document: ",
    query_prefix: "search_query: ",
  },
  {
    model: "Snowflake/snowflake-arctic-embed-xs",
    pooling: "cls",
    query_prefix: "Represent this sentence for searching relevant passages: ",
  },
  {
    model: "mixedbread-ai/mxbai-embed-large-v1",
    pooling: "cls",
    query_prefix: "Represent this sentence for searching relevant passages: ",
  },
  { model: "Xenova/jina-embeddings-v2-small-en" },
  {
    model: "onnx-community/embeddinggemma-300m-ONNX",
    document_prefix: "title: none | text: ",
    query_prefix: "task: search result | query: ",
  },
];

const QUERY = "Which planet is known as the Red Planet?";
const DOCUMENTS = [
  "Venus is often called Earth's twin because of its similar size and proximity.",
  "Mars, known for its reddish appearance, is often referred to as the Red Planet.",
  "Jupiter, the largest planet in our solar system, has a prominent red spot.",
  "Saturn, famous for its rings, is sometimes mistaken for the Red Planet.",
];
const EXPECTED = 1;

// Quantized kernels differ slightly between ONNX Runtime builds (see README).
const MIN_AGREEMENT = 0.98;

const selected = (process.env.SEMANTIC_SEARCH_MODELS ?? "").split(",").map((s) => s.trim()).filter(Boolean);
const enabled = (model) => selected.includes("all") || selected.includes(model);

const dot = (a, b) => a.reduce((sum, v, i) => sum + v * b[i], 0);

function rubyVectors(settings, texts) {
  const output = execFileSync("bundle", ["exec", "ruby", "-Ilib", "test/support/embed.rb"], {
    input: JSON.stringify({ settings, texts }),
    maxBuffer: 64 * 1024 * 1024,
    stdio: ["pipe", "pipe", "ignore"],
  });
  return JSON.parse(output);
}

for (const entry of MODELS) {
  const settings = { dtype: "q8", pooling: "mean", normalize: true, document_prefix: "", query_prefix: "", ...entry };

  test(entry.model, { skip: !enabled(entry.model) && "set SEMANTIC_SEARCH_MODELS to run" }, async () => {
    const { pipeline } = await import("@huggingface/transformers");
    const texts = [settings.query_prefix + QUERY, ...DOCUMENTS.map((d) => settings.document_prefix + d)];

    const extractor = await pipeline("feature-extraction", settings.model, { dtype: settings.dtype });
    const browser = (await extractor(texts, { pooling: settings.pooling, normalize: settings.normalize })).tolist();
    await extractor.dispose();
    const build = rubyVectors(settings, texts);

    assert.equal(build.length, texts.length);
    build.forEach((vector, i) => {
      assert.equal(vector.length, browser[i].length, "dimensions differ");
      const agreement = dot(vector, browser[i]);
      assert.ok(agreement >= MIN_AGREEMENT, `text ${i}: build and browser vectors agree to only ${agreement}`);
    });

    const scores = build.slice(1).map((doc) => dot(build[0], doc));
    assert.equal(scores.indexOf(Math.max(...scores)), EXPECTED, `scores: ${scores}`);
  });
}
