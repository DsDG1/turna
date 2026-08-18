(function () {
  var host = document.getElementById("card-host");
  var frame = null;
  var frameReady = false;
  var nonce = Math.random().toString(36).slice(2) + Date.now().toString(36);
  var generation = 0;
  var pending = null;
  var lastAck = null;
  var payload = null;
  var lastFrameCardId = null;
  var presentSeq = 0;
  var acceptRebuilds = 0;
  var frameSeq = 0;
  var postedTypes = [];

  function randomNonce() {
    return Math.random().toString(36).slice(2) + Date.now().toString(36);
  }

  function ackTimeoutMs() {
    return window.__turnaAckTimeoutMs || 8000;
  }

  function publishDebug() {
    window.__turnaNonce = nonce;
    window.__turnaFrameSeq = frameSeq;
    window.__turnaPostedTypes = postedTypes.slice();
    window.__turnaLastRender = lastAck;
    window.__turnaCardId = lastFrameCardId;
  }

  function postToFrame(message) {
    postedTypes.push(message && message.type ? message.type : "");
    publishDebug();
    if (!frame || !frame.contentWindow) return;
    // Opaque sandbox origin cannot be targeted by https://anki.local.
    frame.contentWindow.postMessage(message, "*");
  }

  function waitForAck(kind, token, timeoutMs) {
    return new Promise(function (resolve) {
      var done = false;
      var timer = setTimeout(function () {
        if (done) return;
        done = true;
        resolve({
          ok: false,
          type: "renderError",
          stableCode: "RENDER_TIMEOUT",
          generation: token,
          height: 0
        });
      }, timeoutMs || ackTimeoutMs());
      pending = function (msg) {
        if (done) return false;
        if (msg.generation && msg.generation !== token) return false;
        if (kind && msg.type !== kind && msg.type !== "renderError") return false;
        done = true;
        clearTimeout(timer);
        resolve(msg);
        return true;
      };
    });
  }

  function replaceFrame() {
    nonce = randomNonce();
    frameReady = false;
    frameSeq += 1;
    if (frame && frame.parentNode) {
      frame.parentNode.removeChild(frame);
    }
    frame = document.createElement("iframe");
    frame.id = "card-frame";
    frame.setAttribute("sandbox", "allow-scripts");
    frame.setAttribute("src", "https://anki.local/assets/card-frame.html");
    frame.setAttribute("title", "Official Anki card");
    host.innerHTML = "";
    host.appendChild(frame);
    publishDebug();
  }

  window.addEventListener("message", function (event) {
    if (!frame || event.source !== frame.contentWindow) return;
    var msg = event.data || {};
    if (msg.v !== 1) return;
    if (msg.type === "frameReady") {
      frameReady = true;
      if (pending) pending({ type: "frameReady", generation: generation });
      return;
    }
    if (msg.nonce && msg.nonce !== nonce) return;
    lastAck = msg;
    publishDebug();
    if (pending) pending(msg);
  });

  async function ensureFrame(token) {
    if (frame && frameReady) return { ok: true, type: "frameReady" };
    replaceFrame();
    return waitForAck("frameReady", token, ackTimeoutMs());
  }

  function isAccepted(msg) {
    if (!msg) return false;
    if (msg.type === "renderError" || msg.stableCode === "RENDER_TIMEOUT") {
      return false;
    }
    return msg.type === "cardAccepted";
  }

  async function presentOnce(nextPayload, side, seq) {
    payload = nextPayload || payload || {};
    var token = payload.generation || generation + 1;
    var incomingCardId = payload.cardId;
    var newCard = !frame || incomingCardId !== lastFrameCardId;
    generation = token;
    lastAck = null;
    window.__turnaLastRender = null;
    postedTypes = [];
    if (newCard) {
      lastFrameCardId = incomingCardId;
      replaceFrame();
      var ready = frameReady
        ? { type: "frameReady", generation: token }
        : await waitForAck("frameReady", token, ackTimeoutMs());
      if (seq !== presentSeq) {
        return {
          ok: false,
          type: "renderError",
          stableCode: "RENDER_SUPERSEDED",
          generation: token
        };
      }
      if (ready && ready.stableCode === "RENDER_TIMEOUT") {
        lastAck = ready;
        publishDebug();
        return ready;
      }
    } else {
      await ensureFrame(token);
      if (seq !== presentSeq) {
        return {
          ok: false,
          type: "renderError",
          stableCode: "RENDER_SUPERSEDED",
          generation: token
        };
      }
    }
    var setMsg = {
      v: 1,
      type: "setCard",
      nonce: nonce,
      generation: token,
      cardId: payload.cardId || 0,
      questionDisplayHtml: payload.questionDisplayHtml || "",
      answerDisplayHtml: payload.answerDisplayHtml || "",
      css: payload.css || "",
      theme: payload.theme || "day",
      comparisonHtml: payload.comparisonHtml || "",
      templateOrdinal: payload.templateOrdinal || 0,
      bodyClass: payload.bodyClass || ""
    };
    async function acceptOrRebuild() {
      postToFrame(setMsg);
      var accepted = await waitForAck("cardAccepted", token, ackTimeoutMs());
      if (seq !== presentSeq) {
        return {
          ok: false,
          type: "renderError",
          stableCode: "RENDER_SUPERSEDED",
          generation: token
        };
      }
      if (isAccepted(accepted)) {
        acceptRebuilds = 0;
        return accepted;
      }
      if (acceptRebuilds < 1) {
        acceptRebuilds += 1;
        replaceFrame();
        await waitForAck("frameReady", token, ackTimeoutMs());
        if (seq !== presentSeq) {
          return {
            ok: false,
            type: "renderError",
            stableCode: "RENDER_SUPERSEDED",
            generation: token
          };
        }
        postToFrame(setMsg);
        accepted = await waitForAck("cardAccepted", token, ackTimeoutMs());
        if (seq !== presentSeq) {
          return {
            ok: false,
            type: "renderError",
            stableCode: "RENDER_SUPERSEDED",
            generation: token
          };
        }
        if (isAccepted(accepted)) {
          acceptRebuilds = 0;
          return accepted;
        }
      }
      lastAck = accepted;
      publishDebug();
      return accepted;
    }
    var accepted = await acceptOrRebuild();
    if (!isAccepted(accepted)) {
      return accepted;
    }
    if (seq !== presentSeq) {
      return {
        ok: false,
        type: "renderError",
        stableCode: "RENDER_SUPERSEDED",
        generation: token
      };
    }
    postToFrame({
      v: 1,
      type: side === "answer" ? "showAnswer" : "showQuestion",
      nonce: nonce,
      generation: token,
      cardId: payload.cardId || 0
    });
    var complete = await waitForAck("renderComplete", token, ackTimeoutMs());
    lastAck = complete;
    publishDebug();
    return complete;
  }

  function present(nextPayload, side) {
    var seq = ++presentSeq;
    return presentOnce(nextPayload, side, seq);
  }

  window.OfficialReviewer = {
    ready: function () { return true; },
    setCard: function (next) {
      payload = next || {};
      generation = payload.generation || generation + 1;
      return present(payload, "question").then(function () { return true; });
    },
    showQuestion: function () {
      return present(payload || {}, "question");
    },
    showAnswer: function () {
      return present(payload || {}, "answer");
    },
    present: present,
    setTheme: function (theme) {
      if (payload) payload.theme = theme;
      if (frame && frameReady && payload) {
        generation += 1;
        payload.generation = generation;
        postToFrame({
          v: 1,
          type: "setCard",
          nonce: nonce,
          generation: generation,
          cardId: payload.cardId || 0,
          questionDisplayHtml: payload.questionDisplayHtml || "",
          answerDisplayHtml: payload.answerDisplayHtml || "",
          css: payload.css || "",
          theme: theme,
          comparisonHtml: payload.comparisonHtml || "",
          templateOrdinal: payload.templateOrdinal || 0,
          bodyClass: payload.bodyClass || ""
        });
      }
    },
    clearCard: function () {
      generation += 1;
      payload = null;
      lastFrameCardId = null;
      window.__turnaCardId = null;
      if (frame && frame.parentNode) {
        frame.parentNode.removeChild(frame);
      }
      frame = null;
      frameReady = false;
      host.innerHTML = "";
      publishDebug();
    },
    takeAck: function () {
      return lastAck;
    }
  };
  publishDebug();
})();
