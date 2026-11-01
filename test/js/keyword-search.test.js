import { test } from "node:test";
import assert from "node:assert/strict";

import {
  KEYWORD_DEFAULTS,
  TYPO_FACTOR,
  createKeywordIndex,
  porterStem,
  tokenize,
  withinOneEdit,
} from "../../assets/semantic-search/keyword-search.js";

const close = (actual, expected, message) =>
  assert.ok(Math.abs(actual - expected) < 1e-9, `${message ?? ""} expected ${expected}, got ${actual}`);

const index = (texts, options) => createKeywordIndex(texts.map((text, i) => ({ id: i + 1, text })), options);
const scores = (results) => Object.fromEntries([...results].map(([id, r]) => [id, r.score]));

test("tokenize lowercases, splits on punctuation and keeps digits", () => {
  assert.deepEqual(tokenize("Rust's Borrow-Checker, 2024!"), ["rust", "s", "borrow", "checker", "2024"]);
  assert.deepEqual(tokenize(""), []);
  assert.deepEqual(tokenize(null), []);
});

test("tokenize folds accents in Latin script only", () => {
  assert.deepEqual(tokenize("Café NAÏVE Ångström"), ["cafe", "naive", "angstrom"]);
  // Bengali and Devanagari vowel signs are combining marks that belong to the word.
  assert.deepEqual(tokenize("বাংলা কম্পিউটার"), ["বাংলা", "কম্পিউটার"]);
  assert.deepEqual(tokenize("हिन्दी भाषा"), ["हिन्दी", "भाषा"]);
});

test("porterStem matches the reference vocabulary", () => {
  const cases = {
    caresses: "caress", ponies: "poni", ties: "ti", caress: "caress", cats: "cat",
    feed: "feed", agreed: "agre", plastered: "plaster", bled: "bled", motoring: "motor", sing: "sing",
    conflated: "conflat", troubled: "troubl", sized: "size", hopping: "hop", tanned: "tan",
    falling: "fall", hissing: "hiss", fizzed: "fizz", failing: "fail", filing: "file",
    happy: "happi", sky: "sky", relational: "relat", conditional: "condit", rational: "ration",
    valenci: "valenc", digitizer: "digit", conformabli: "conform", radicalli: "radic",
    differentli: "differ", vileli: "vile", analogousli: "analog", vietnamization: "vietnam",
    predication: "predic", operator: "oper", feudalism: "feudal", decisiveness: "decis",
    hopefulness: "hope", callousness: "callous", formaliti: "formal", sensitiviti: "sensit",
    sensibiliti: "sensibl", triplicate: "triplic", formative: "form", formalize: "formal",
    electriciti: "electr", electrical: "electr", hopeful: "hope", goodness: "good",
    revival: "reviv", allowance: "allow", inference: "infer", airliner: "airlin",
    gyroscopic: "gyroscop", adjustable: "adjust", defensible: "defens", irritant: "irrit",
    replacement: "replac", adjustment: "adjust", dependent: "depend", adoption: "adopt",
    homologou: "homolog", communism: "commun", activate: "activ", angulariti: "angular",
    homologous: "homolog", effective: "effect", bowdlerize: "bowdler", probate: "probat",
    rate: "rate", cease: "ceas", controll: "control", roll: "roll", generalizations: "gener",
  };
  for (const [word, stem] of Object.entries(cases)) assert.equal(porterStem(word), stem, word);
});

test("porterStem conflates everyday inflections", () => {
  const groups = [
    ["tomato", "tomatoes"], ["run", "running", "runs"], ["test", "tests", "testing", "tested"],
    ["connect", "connected", "connection", "connections", "connecting"], ["habit", "habits"],
  ];
  for (const group of groups) assert.equal(new Set(group.map(porterStem)).size, 1, group.join(", "));
});

test("porterStem leaves short, non-ASCII and mixed words alone", () => {
  for (const word of ["is", "a", "বাংলা", "s3", "x86", "naïve"]) assert.equal(porterStem(word), word);
});

test("withinOneEdit accepts one substitution, insertion, deletion or adjacent swap", () => {
  const near = [
    ["oven", "oven"], ["oven", "oxen"], ["oven", "even"], ["oven", "ovens"], ["oven", "ove"],
    ["oven", "voen"], ["oven", "ovne"], ["oven", "xoven"],
  ];
  const far = [["oven", "vone"], ["oven", "ov"], ["oven", "oxens"], ["oven", "open!"], ["abcd", "badc"]];
  for (const [a, b] of near) {
    assert.ok(withinOneEdit(a, b), `${a} ~ ${b}`);
    assert.ok(withinOneEdit(b, a), `${b} ~ ${a}`);
  }
  for (const [a, b] of far) {
    assert.ok(!withinOneEdit(a, b), `${a} !~ ${b}`);
    assert.ok(!withinOneEdit(b, a), `${b} !~ ${a}`);
  }
});

test("withinOneEdit rejects swaps that are not adjacent", () => {
  assert.ok(!withinOneEdit("abcde", "ebcda"));
  assert.ok(withinOneEdit("abcde", "abced"));
});

// Three passages: N = 3, average length 2.
//   1: "apple banana"        (length 2)
//   2: "apple apple cherry"  (length 3)
//   3: "durian"              (length 1)
// idf(df) = ln(1 + (N - df + 0.5) / (df + 0.5)); unit = idf(1).
// term score = idf · tf(k1+1) / (tf + k1(1 - b + b·len/avg)), scaled by unit and capped at 1.
const FRUIT = ["apple banana", "apple apple cherry", "durian"];
const idf = (df) => Math.log(1 + (3 - df + 0.5) / (df + 0.5));
const unit = idf(1);
const termScore = (df, tf, length, k1 = 1.2, b = 0.75) =>
  Math.min(1, (idf(df) * tf * (k1 + 1)) / (tf + k1 * (1 - b + (b * length) / 2)) / unit);

test("BM25 scores match the formula", () => {
  const fruit = index(FRUIT, { stemming: false });

  close(scores(fruit.search("cherry"))[2], termScore(1, 1, 3), "cherry in 2");
  const apple = scores(fruit.search("apple"));
  close(apple[1], termScore(2, 1, 2), "apple in 1");
  close(apple[2], termScore(2, 2, 3), "apple twice in 2");
  assert.ok(apple[2] > apple[1], "more occurrences score higher");
  assert.equal(apple[3], undefined);
});

test("scores average over query words, so missing words count as 0", () => {
  const fruit = index(FRUIT, { stemming: false });
  const both = scores(fruit.search("apple durian"));

  close(both[3], termScore(1, 1, 1) / 2, "durian alone");
  close(both[1], termScore(2, 1, 2) / 2, "apple alone");
  assert.equal(termScore(1, 1, 1), 1, "a short passage hits the cap");
  close(scores(fruit.search("cherry xylophone"))[2], termScore(1, 1, 3) / 2);
});

test("repeated query words count once", () => {
  const fruit = index(FRUIT, { stemming: false });
  assert.deepEqual(scores(fruit.search("cherry cherry CHERRY")), scores(fruit.search("cherry")));
});

test("k1 and b change term-frequency saturation and length normalisation", () => {
  const texts = ["apple apple apple apple filler filler filler filler", "apple"];
  const flat = scores(index(texts, { stemming: false, b: 0 }).search("apple"));
  const lengthy = scores(index(texts, { stemming: false, b: 1 }).search("apple"));
  assert.ok(lengthy[1] < flat[1], "b penalises the long passage");
  const saturated = scores(index(["apple apple apple", "apple"], { stemming: false, k1: 0.01 }).search("apple"));
  assert.ok(Math.abs(saturated[1] - saturated[2]) < 0.01, "k1 → 0 all but ignores term frequency");
});

test("common words score lower than rare ones", () => {
  const texts = ["the oven", "the bread", "the dough", "the crust"];
  const results = scores(index(texts).search("the oven"));
  const common = scores(index(texts).search("the"));
  assert.ok(common[1] < 0.2, `"the" scores ${common[1]}`);
  assert.ok(results[1] > 0.5 && results[2] < 0.2, JSON.stringify(results));
});

test("stemming matches inflected forms, and can be turned off", () => {
  const texts = ["Growing tomatoes in containers", "Running a marathon"];
  assert.deepEqual([...index(texts).search("tomato").keys()], [1]);
  assert.deepEqual([...index(texts).search("run").keys()], [2]);
  assert.deepEqual([...index(texts, { stemming: false }).search("tomato").keys()], []);
});

test("typo tolerance matches words one edit away, at a discount", () => {
  const passages = index(["Long bulk fermentation develops flavour"], { stemming: false });
  const exact = passages.search("fermentation").get(1);
  const typo = passages.search("fermantation").get(1);
  close(typo.score, exact.score * TYPO_FACTOR);
  assert.deepEqual(typo.matches, ["fermantation"]);
  assert.equal(passages.search("fermantation", { typoTolerance: false }).size, 0);
});

test("typo tolerance works on stems", () => {
  assert.ok(index(["Long bulk fermentation"]).search("fermantations").get(1)?.score > 0);
});

test("typo tolerance skips short words and words found as typed", () => {
  const passages = index(["Fill in the form", "Rust and trust"], { stemming: false });
  assert.equal(passages.search("from").size, 0, "4-letter words need an exact match");
  assert.deepEqual([...passages.search("trust").keys()], [2]);
  assert.deepEqual(passages.search("trust").get(2).matches, ["trust"]);
});

test("matches lists the query words as typed", () => {
  const results = index(["Bake in a dutch oven"]).search("Dutch OVENS please");
  assert.deepEqual(results.get(1).matches, ["dutch", "ovens"]);
});

test("empty queries and empty indexes return nothing", () => {
  assert.equal(index(FRUIT).search("").size, 0);
  assert.equal(index(FRUIT).search("!!!").size, 0);
  assert.equal(index([]).search("apple").size, 0);
});

test("scores stay within [0, 1]", () => {
  const passages = index(["apple apple apple apple apple", "apple", "banana"]);
  for (const query of ["apple", "apple banana", "apple apple", "applle", "banana cherry"]) {
    for (const { score } of passages.search(query).values()) assert.ok(score >= 0 && score <= 1, `${query}: ${score}`);
  }
});

test("defaults are the documented ones", () => {
  assert.deepEqual(KEYWORD_DEFAULTS, {
    enabled: false, weight: 0.3, min_score: 0.5, stemming: true, typo_tolerance: true, k1: 1.2, b: 0.75,
  });
});
