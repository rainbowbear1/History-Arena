// FAKE bridge for local browser tests only. It signs in a made-up test user and records
// submitted results in window.__submitted. Never deploy this file.
(function () {
  "use strict";
  var user = null;
  window.__submitted = [];
  window.HistoryArenaHub = {
    configured: true,
    getCurrentUser: function () {
      return user ? JSON.stringify(user) : "";
    },
    signInWithGoogle: function () {
      return new Promise(function (resolve) {
        setTimeout(function () {
          user = { uid: "test-uid-001", name: "Тест Оқушы", email: "student@example.test" };
          resolve(JSON.stringify(user));
        }, 300);
      });
    },
    signOut: function () {
      user = null;
      return Promise.resolve();
    },
    submitResult: function (payloadJson) {
      window.__submitted.push(JSON.parse(payloadJson));
      return Promise.resolve(JSON.stringify({ ok: true }));
    },
  };
})();
