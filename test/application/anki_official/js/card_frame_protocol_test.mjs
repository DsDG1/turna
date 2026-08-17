#!/usr/bin/env node
/**
 * Executable host for the shipped reviewer scripts.
 * Loads assets/anki_reviewer/card-frame.js and reviewer.js into a
 * window/postMessage environment. Does not grep source strings.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../../../../");
const assets = path.join(repo, "assets/anki_reviewer");
const cardFrameSrc = fs.readFileSync(path.join(assets, "card-frame.js"), "utf8");
const reviewerSrc = fs.readFileSync(path.join(assets, "reviewer.js"), "utf8");

let failed = 0;
function assert(cond, message) {
  if (!cond) {
    failed += 1;
    console.error("FAIL:", message);
  } else {
    console.log("ok:", message);
  }
}

function el(overrides = {}) {
  return {
    id: "",
    className: "card",
    innerHTML: "",
    textContent: "",
    scrollHeight: 80,
    src: "",
    attributes: [],
    children: [],
    parentNode: null,
    style: {},
    tagName: "DIV",
    getElementsByTagName() {
      return [];
    },
    setAttribute(name, value) {
      this[name] = value;
      this.attributes.push({ name, value });
    },
    appendChild(child) {
      this.children.push(child);
      child.parentNode = this;
      return child;
    },
    removeChild(child) {
      this.children = this.children.filter((c) => c !== child);
      child.parentNode = null;
      return child;
    },
    addEventListener() {},
    replaceWith() {},
    pause() {},
    load() {},
    ...overrides,
  };
}

function makeDocument(ids) {
  const store = { ...ids };
  return {
    body: el({ className: "card", scrollHeight: 80 }),
    documentElement: el({ scrollHeight: 80 }),
    head: el(),
    getElementById(id) {
      if (store[id]) return store[id];
      if (id === "card-css") {
        const style = el({ id: "card-css" });
        store[id] = style;
        return style;
      }
      return null;
    },
    createElement(tag) {
      const created = el({ tagName: String(tag).toUpperCase() });
      if (tag === "style") {
        created.id = "card-css";
        store["card-css"] = created;
      }
      return created;
    },
    _store: store,
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function runScript(src, sandbox, filename) {
  const context = {
    ...sandbox,
    console,
    Date,
    Math,
    Promise,
    Array,
    Error,
    JSON,
    setTimeout,
    clearTimeout,
    queueMicrotask,
  };
  vm.createContext(context);
  vm.runInContext(src, context, { filename });
  return context;
}

function loadCardFrame() {
  const qa = el({ id: "qa", scrollHeight: 64 });
  const document = makeDocument({ qa });
  const inbox = [];
  const listeners = [];
  const parent = {
    inbox,
    postMessage(data) {
      inbox.push(data);
    },
    addEventListener() {},
  };
  const child = {
    parent,
    document,
    MathJax: undefined,
    scrollTo() {},
    addEventListener(type, fn) {
      if (type === "message") listeners.push(fn);
    },
  };
  runScript(cardFrameSrc, { window: child, document }, "card-frame.js");
  return {
    qa,
    inbox,
    post(data) {
      for (const fn of listeners) {
        fn({ data, source: parent, origin: "https://anki.local" });
      }
    },
  };
}

async function testSetCardGenerationProtocol() {
  const host = loadCardFrame();
  assert(host.inbox.some((m) => m && m.type === "frameReady"), "card-frame posts frameReady");

  host.post({
    v: 1,
    type: "setCard",
    nonce: "n1",
    generation: 1,
    cardId: 10,
    questionDisplayHtml: "<p>Q1</p>",
    answerDisplayHtml: "<p>A1</p>",
    templateOrdinal: 0,
  });
  host.post({
    v: 1,
    type: "showQuestion",
    nonce: "n1",
    generation: 1,
    cardId: 10,
  });
  await sleep(20);
  const q = host.inbox.filter((m) => m && m.type === "renderComplete" && m.generation === 1);
  assert(q.length === 1 && q[0].side === "question", "generation 1 question renderComplete");
  assert(host.qa.innerHTML.includes("Q1"), "question DOM is generation 1 HTML");

  host.post({
    v: 1,
    type: "setCard",
    nonce: "n1",
    generation: 2,
    cardId: 10,
    questionDisplayHtml: "<p>Q1</p>",
    answerDisplayHtml: "<p>A2-updated</p>",
    comparisonHtml: "<code>ok</code>",
    templateOrdinal: 0,
  });
  host.post({
    v: 1,
    type: "showAnswer",
    nonce: "n1",
    generation: 2,
    cardId: 10,
  });
  await sleep(20);
  const a = host.inbox.filter((m) => m && m.type === "renderComplete" && m.generation === 2);
  assert(a.length === 1 && a[0].side === "answer", "generation 2 answer renderComplete");
  assert(host.qa.innerHTML.includes("A2-updated"), "answer DOM is generation 2 HTML");
  assert(host.inbox.filter((m) => m && m.type === "cardAccepted").length >= 2, "both generations accepted");
}

async function testRejectStaleGeneration() {
  const host = loadCardFrame();
  host.post({
    v: 1,
    type: "setCard",
    nonce: "n1",
    generation: 1,
    cardId: 10,
    questionDisplayHtml: "<p>old</p>",
    answerDisplayHtml: "<p>old-a</p>",
  });
  host.post({
    v: 1,
    type: "setCard",
    nonce: "n1",
    generation: 2,
    cardId: 10,
    questionDisplayHtml: "<p>new</p>",
    answerDisplayHtml: "<p>new-a</p>",
  });
  const before = host.inbox.filter((m) => m && m.type === "renderComplete").length;
  host.post({
    v: 1,
    type: "showQuestion",
    nonce: "n1",
    generation: 1,
    cardId: 10,
  });
  host.post({
    v: 1,
    type: "showAnswer",
    nonce: "n1",
    generation: 1,
    cardId: 10,
  });
  await sleep(20);
  const afterStale = host.inbox.filter((m) => m && m.type === "renderComplete").length;
  assert(afterStale === before, "generation 1 show is rejected after generation 2");

  host.post({
    v: 1,
    type: "showAnswer",
    nonce: "n1",
    generation: 2,
    cardId: 10,
  });
  await sleep(20);
  const latest = host.inbox.filter((m) => m && m.type === "renderComplete");
  assert(
    latest.length === 1 && latest[0].generation === 2 && latest[0].side === "answer",
    "only generation 2 completion is posted"
  );
}

function loadReviewer({ silentFrame = false } = {}) {
  const hostEl = el({ id: "card-host" });
  const store = { "card-host": hostEl };
  const frames = [];
  const document = {
    body: el({ className: "card" }),
    documentElement: el(),
    head: el(),
    getElementById(id) {
      return store[id] || null;
    },
    createElement(tag) {
      if (tag !== "iframe") return el({ tagName: String(tag).toUpperCase() });
      const qa = el({ id: "qa", scrollHeight: 90 });
      const frameDoc = makeDocument({ qa });
      const childListeners = [];
      const child = {
        document: frameDoc,
        MathJax: undefined,
        scrollTo() {},
        addEventListener(type, fn) {
          if (type === "message") childListeners.push(fn);
        },
        postMessage(data) {
          for (const fn of childListeners) {
            fn({
              data,
              source: child.parent,
              origin: "https://anki.local",
            });
          }
        },
      };
      const iframe = el({ tagName: "IFRAME", contentWindow: child });
      child.parent = {
        postMessage(data) {
          shell._deliverFromFrame(data, child);
        },
      };
      iframe.setAttribute = function (name, value) {
        this[name] = value;
        if (name !== "src") return;
        queueMicrotask(() => {
          if (silentFrame) {
            shell._deliverFromFrame({ v: 1, type: "frameReady" }, child);
            return;
          }
          runScript(cardFrameSrc, { window: child, document: frameDoc }, "card-frame.js");
        });
      };
      frames.push(iframe);
      return iframe;
    },
  };

  const shellListeners = [];
  const shell = {
    document,
    OfficialReviewer: null,
    __turnaAckTimeoutMs: 40,
    addEventListener(type, fn) {
      if (type === "message") shellListeners.push(fn);
    },
    _deliverFromFrame(data, source) {
      for (const fn of shellListeners) {
        fn({ data, source, origin: "https://anki.local" });
      }
    },
  };

  runScript(reviewerSrc, { window: shell, document }, "reviewer.js");
  return { shell, frames, hostEl };
}

async function testCardIdRotatesFrame() {
  const host = loadReviewer();
  const reviewer = host.shell.OfficialReviewer;
  await reviewer.present(
    {
      cardId: 1,
      generation: 1,
      questionDisplayHtml: "<p>c1q</p>",
      answerDisplayHtml: "<p>c1a</p>",
    },
    "question"
  );
  await sleep(20);
  const firstSeq = host.shell.__turnaFrameSeq;
  const firstNonce = host.shell.__turnaNonce;
  assert(firstSeq >= 1, "first card created a frame");
  await reviewer.present(
    {
      cardId: 2,
      generation: 2,
      questionDisplayHtml: "<p>c2q</p>",
      answerDisplayHtml: "<p>c2a</p>",
    },
    "question"
  );
  await sleep(20);
  assert(host.shell.__turnaFrameSeq === firstSeq + 1, "new cardId rotates the frame");
  assert(host.shell.__turnaNonce !== firstNonce, "new cardId rotates the nonce");
}

async function testSameCardKeepsFrame() {
  const host = loadReviewer();
  const reviewer = host.shell.OfficialReviewer;
  await reviewer.present(
    {
      cardId: 7,
      generation: 1,
      questionDisplayHtml: "<p>q</p>",
      answerDisplayHtml: "<p>a</p>",
      theme: "day",
    },
    "question"
  );
  await sleep(20);
  const seq = host.shell.__turnaFrameSeq;
  const nonce = host.shell.__turnaNonce;
  const result = await reviewer.present(
    {
      cardId: 7,
      generation: 2,
      questionDisplayHtml: "<p>q</p>",
      answerDisplayHtml: "<p>a</p>",
      comparisonHtml: "<em>cmp</em>",
      theme: "night",
    },
    "answer"
  );
  await sleep(20);
  if (host.shell.__turnaFrameSeq !== seq) {
    console.error("debug same-card", {
      seq,
      next: host.shell.__turnaFrameSeq,
      nonce,
      nextNonce: host.shell.__turnaNonce,
      posted: host.shell.__turnaPostedTypes,
      last: host.shell.__turnaLastRender,
      result,
    });
  }
  assert(host.shell.__turnaFrameSeq === seq, "same cardId comparison/theme keeps the frame");
  assert(host.shell.__turnaNonce === nonce, "same cardId comparison/theme keeps the nonce");
}

async function testTimeoutDoesNotShowAnswer() {
  const host = loadReviewer({ silentFrame: true });
  const reviewer = host.shell.OfficialReviewer;
  const result = await reviewer.present(
    {
      cardId: 3,
      generation: 1,
      questionDisplayHtml: "<p>q</p>",
      answerDisplayHtml: "<p>a</p>",
    },
    "answer"
  );
  await sleep(120);
  const posted = host.shell.__turnaPostedTypes || [];
  assert(result && result.stableCode === "RENDER_TIMEOUT", "cardAccepted timeout returns RENDER_TIMEOUT");
  assert(!posted.includes("showAnswer"), "cardAccepted timeout does not send showAnswer");
  assert(!posted.includes("showQuestion"), "cardAccepted timeout does not send showQuestion");
  assert(posted.filter((t) => t === "setCard").length >= 1, "timeout path still attempted setCard");
}

async function main() {
  await testSetCardGenerationProtocol();
  await testRejectStaleGeneration();
  await testCardIdRotatesFrame();
  await testSameCardKeepsFrame();
  await testTimeoutDoesNotShowAnswer();
  if (failed) {
    console.error(`\n${failed} assertion(s) failed`);
    process.exit(1);
  }
  console.log("\nall five protocol cases passed against shipped assets");
}

await main();
