(function () {
  window.OfficialReviewerTest = {
    snapshot: function (generation, nonce) {
      window.__turnaLastSnapshot = null;
      var frame = document.getElementById("card-frame");
      if (!frame || !frame.contentWindow) return "0";
      frame.contentWindow.postMessage(
        { v: 1, type: "testSnapshot", generation: generation, nonce: nonce },
        "*"
      );
      return "1";
    }
  };
  window.addEventListener("message", function (event) {
    var data = event.data || {};
    if (data && data.type === "testSnapshotResult") {
      window.__turnaLastSnapshot = data;
    }
  });
})();
