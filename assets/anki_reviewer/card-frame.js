(function () {
  var qa = document.getElementById("qa");
  var nonce = null;
  var generation = 0;
  var cardId = 0;
  var questionHtml = "";
  var answerHtml = "";
  var mathjaxLoading = null;
  var mathjaxRegex = /\\\[(.*?)\\\]|\\\((.*?)\\\)/su;
  var updateSeq = 0;
  var lastSide = "question";

  function post(message) {
    if (!window.parent || window.parent === window) return;
    window.parent.postMessage(message, "https://anki.local");
  }

  function fromParent(event) {
    if (event.source !== window.parent) return false;
    var data = event.data || {};
    if (data.v !== 1) return false;
    return true;
  }

  function nonceMatches(data) {
    if (nonce && data.nonce !== nonce) return false;
    return true;
  }

  function containsMathjax(html) {
    return mathjaxRegex.test(html);
  }

  function replaceScript(oldScript) {
    return new Promise(function (resolve, reject) {
      var newScript = document.createElement("script");
      var wait = false;
      if (oldScript.src) {
        wait = true;
        newScript.addEventListener("load", function () { resolve(); });
        newScript.addEventListener("error", function () {
          if ((oldScript.src || "").indexOf("mathjax") >= 0) {
            reject(new Error("MATHJAX_ASSET_MISSING"));
          } else {
            resolve();
          }
        });
      }
      for (var i = 0; i < oldScript.attributes.length; i++) {
        var attr = oldScript.attributes[i];
        newScript.setAttribute(attr.name, attr.value);
      }
      newScript.appendChild(document.createTextNode(oldScript.innerHTML));
      oldScript.replaceWith(newScript);
      if (!wait) resolve();
    });
  }

  async function setInnerHTML(element, html) {
    var videos = element.getElementsByTagName("video");
    for (var i = 0; i < videos.length; i++) {
      videos[i].pause();
      while (videos[i].firstChild) videos[i].removeChild(videos[i].firstChild);
      videos[i].load();
    }
    element.innerHTML = html;
    var scripts = Array.prototype.slice.call(element.getElementsByTagName("script"));
    for (var s = 0; s < scripts.length; s++) {
      await replaceScript(scripts[s]);
    }
  }

  function applyTyped(html, comparison) {
    if (comparison) {
      return html.replace(/\[\[type:[^\]]+\]\]/g, comparison);
    }
    return html.replace(
      /\[\[type:[^\]]+\]\]/g,
      '<span id="typeans-placeholder" class="typeans-ph"></span>'
    );
  }

  function applyBodyClass(ordinal, theme) {
    var keep = [];
    var existing = document.body.className.split(/\s+/);
    for (var i = 0; i < existing.length; i++) {
      var cls = existing[i];
      if (!cls || cls === "card" || /^card\d+$/.test(cls)) continue;
      if (cls === "nightMode" || cls === "night_mode") continue;
      if (cls === "isWin" || cls === "isMac" || cls === "isLin") continue;
      keep.push(cls);
    }
    var next = ["card", "card" + ((ordinal || 0) + 1)];
    if (theme === "night") {
      next.push("nightMode");
      next.push("night_mode");
    }
    document.body.className = next.concat(keep).join(" ");
  }

  function lazyLoadMathJax() {
    if (window.MathJax && MathJax.typesetPromise) {
      return Promise.resolve();
    }
    if (mathjaxLoading) return mathjaxLoading;
    mathjaxLoading = new Promise(function (resolve, reject) {
      var script = document.createElement("script");
      script.src = "https://anki.local/assets/mathjax/tex-svg-full.js";
      script.onload = function () { resolve(); };
      script.onerror = function () {
        mathjaxLoading = null;
        reject(new Error("MATHJAX_ASSET_MISSING"));
      };
      document.head.appendChild(script);
    });
    return mathjaxLoading;
  }

  function frameHeight() {
    var el = document.documentElement;
    var body = document.body;
    return Math.max(
      el ? el.scrollHeight : 0,
      body ? body.scrollHeight : 0,
      qa ? qa.scrollHeight : 0
    );
  }

  function djb2(text) {
    var hash = 5381;
    var value = String(text || "");
    for (var i = 0; i < value.length; i++) {
      hash = ((hash << 5) + hash + value.charCodeAt(i)) >>> 0;
    }
    return hash.toString(16);
  }

  function snapshotMediaUrls() {
    var nodes = qa ? qa.querySelectorAll("img, audio, source, video") : [];
    var urls = [];
    for (var i = 0; i < nodes.length; i++) {
      var src = nodes[i].getAttribute("src") || nodes[i].src || "";
      if (src) urls.push(src);
    }
    return urls;
  }

  async function updateQa(html, side) {
    lastSide = side || lastSide;
    var token = generation;
    var seq = ++updateSeq;
    var started = Date.now();
    if (containsMathjax(html)) {
      try {
        await lazyLoadMathJax();
      } catch (e) {
        post({
          v: 1,
          type: "renderError",
          stableCode: "MATHJAX_ASSET_MISSING",
          cardId: cardId,
          generation: token,
          side: side
        });
        throw e;
      }
    }
    if (token !== generation || seq !== updateSeq) return;
    try {
      await setInnerHTML(qa, html || "<div class=\"empty-card\"></div>");
    } catch (e) {
      qa.textContent = "Invalid html on card";
      if (String(e && e.message) === "MATHJAX_ASSET_MISSING") {
        post({
          v: 1,
          type: "renderError",
          stableCode: "MATHJAX_ASSET_MISSING",
          cardId: cardId,
          generation: token,
          side: side
        });
        throw e;
      }
    }
    if (token !== generation || seq !== updateSeq) return;
    if (containsMathjax(html) && window.MathJax && MathJax.startup) {
      try {
        await MathJax.startup.promise;
        if (MathJax.typesetClear) MathJax.typesetClear();
        if (MathJax.typesetPromise) await MathJax.typesetPromise([qa]);
      } catch (e) {
        post({
          v: 1,
          type: "renderError",
          stableCode: "MATHJAX_TYPESET_FAILED",
          cardId: cardId,
          generation: token,
          side: side
        });
      }
    }
    if (token !== generation || seq !== updateSeq) return;
    window.scrollTo(0, 0);
    post({
      v: 1,
      type: "renderComplete",
      cardId: cardId,
      generation: token,
      side: side,
      height: frameHeight(),
      durationMs: Date.now() - started
    });
  }

  function acceptSetCard(data) {
    if (!nonceMatches(data)) return false;
    var nextGen = data.generation || 0;
    return nextGen > generation;
  }

  function acceptShow(data) {
    if (!nonceMatches(data)) return false;
    if (data.generation !== generation) return false;
    if ((data.cardId || 0) !== cardId) return false;
    return true;
  }

  window.addEventListener("message", function (event) {
    if (!fromParent(event)) return;
    var data = event.data || {};
    if (data.type === "setCard") {
      if (!acceptSetCard(data)) return;
      nonce = data.nonce || nonce;
      generation = data.generation;
      cardId = data.cardId || 0;
      questionHtml = applyTyped(data.questionDisplayHtml || "", null);
      answerHtml = applyTyped(
        data.answerDisplayHtml || "",
        data.comparisonHtml || ""
      );
      var style = document.getElementById("card-css");
      if (!style) {
        style = document.createElement("style");
        style.id = "card-css";
        document.head.appendChild(style);
      }
      style.textContent = data.css || "";
      applyBodyClass(data.templateOrdinal || 0, data.theme || "day");
      post({
        v: 1,
        type: "cardAccepted",
        cardId: cardId,
        generation: generation
      });
      return;
    }
    if (data.type === "showQuestion") {
      if (!acceptShow(data)) return;
      updateQa(questionHtml, "question");
      return;
    }
    if (data.type === "showAnswer") {
      if (!acceptShow(data)) return;
      updateQa(answerHtml, "answer");
      return;
    }
    if (data.type === "clear") {
      if (!nonceMatches(data)) return;
      generation += 1;
      qa.innerHTML = "";
      if (window.MathJax && MathJax.typesetClear) MathJax.typesetClear();
      return;
    }
    // Test-only postMessage probe. Not part of OfficialReviewer.
    if (data.type === "testSnapshot") {
      post({
        v: 1,
        type: "testSnapshotResult",
        generation: generation,
        side: lastSide,
        bodyClass: document.body ? document.body.className : "",
        qaTextHash: djb2(qa ? qa.textContent : ""),
        mediaUrls: snapshotMediaUrls()
      });
    }
  });

  post({ v: 1, type: "frameReady" });
})();
