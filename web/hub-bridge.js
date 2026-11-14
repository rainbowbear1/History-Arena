// History Arena <-> Game Hub bridge (loaded by the exported index.html via html/head_include).
//
// This is the NOT-CONFIGURED stub shipped until the Game Hub team provides the real bridge.
// The real file must implement the same object using the Hub's shared authentication and
// backend (Firebase or Supabase, decided by the Hub team). Contract: docs/hub-integration.md.
//
// Rules for the real implementation:
//  - Only public client configuration may appear here (e.g. a Firebase web config or a
//    Supabase anon key protected by row-level security). Never service keys or secrets.
//  - Results go to a server-side function that validates them; never write leaderboard rows
//    directly from the browser.
(function () {
  "use strict";
  window.HistoryArenaHub = {
    configured: false,

    // -> JSON string {"uid","name","email"} for an existing session, or "".
    getCurrentUser: function () {
      return "";
    },

    // -> Promise<string> resolving to {"uid","name","email"} JSON, or rejecting with a message.
    signInWithGoogle: function () {
      return Promise.reject("Game Hub is not configured yet");
    },

    // -> Promise<void>
    signOut: function () {
      return Promise.resolve();
    },

    // payloadJson: one attempt record (see docs/hub-integration.md)
    // -> Promise<string> resolving to {"ok": true} or {"ok": false, "error": "..."} JSON.
    submitResult: function (payloadJson) {
      return Promise.resolve(JSON.stringify({ ok: false, error: "not configured" }));
    },
  };
})();
