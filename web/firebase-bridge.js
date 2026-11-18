// History Arena online bridge: Google sign-in (Firebase Authentication) and the leaderboard
// (Cloud Firestore). index.html loads firebase-config.js and then this file (html/head_include).
// The game talks only to window.HistoryArenaHub (contract: docs/online.md), so a Game Hub bridge
// with the same methods can replace this file later.
//
// Security: this file and firebase-config.js hold only public client values. Who may write what is
// decided by firestore.rules on Google's servers; the player id always comes from the signed-in
// Firebase session, never from the game.
(function () {
  "use strict";
  var SDK = "https://www.gstatic.com/firebasejs/13.1.0/";
  var LEVELS = 10;
  var ALL_IN_ONE = 12; // All-in-One runs: own leaderboard allinone/{uid}, never the campaign total.
  // Local testing against the Firebase Emulator Suite: http://localhost:<port>/?emulator=1
  var EMULATOR = /^(localhost|127\.0\.0\.1)$/.test(location.hostname) && /[?&]emulator=1\b/.test(location.search);
  var DEMO_CONFIG = { apiKey: "demo-key", authDomain: "demo-history-arena.firebaseapp.com", projectId: "demo-history-arena", appId: "demo" };

  var config = EMULATOR ? DEMO_CONFIG : window.HISTORY_ARENA_FIREBASE || {};
  var configured = !!(config.apiKey && config.authDomain && config.projectId && config.appId);
  var A = null; // firebase/auth module
  var F = null; // firebase/firestore module
  var auth = null;
  var db = null;
  var loadError = "";

  var ready = configured ? init() : Promise.resolve();

  function init() {
    return Promise.all([import(SDK + "firebase-app.js"), import(SDK + "firebase-auth.js"), import(SDK + "firebase-firestore.js")])
      .then(function (m) {
        var app = m[0].initializeApp(config);
        A = m[1];
        F = m[2];
        auth = A.getAuth(app); // Keeps the session in IndexedDB, so a refresh stays signed in.
        db = F.getFirestore(app);
        if (EMULATOR) {
          A.connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
          F.connectFirestoreEmulator(db, "127.0.0.1", 8080);
        }
        return auth.authStateReady();
      })
      .catch(function (e) {
        loadError = "Firebase жүктелмеді: " + (e && e.message ? e.message : e);
        console.error(loadError);
      });
  }

  function userJson() {
    var u = auth && auth.currentUser;
    return u ? JSON.stringify({ uid: u.uid, name: u.displayName || "Ойыншы" }) : "";
  }

  function whenReady() {
    return ready.then(function () {
      if (loadError) throw loadError;
    });
  }

  function message(e) {
    var code = e && e.code ? e.code : "";
    var known = {
      "auth/popup-blocked": "браузер кіру терезесін бұғаттады, қалқымалы терезелерге рұқсат беріңіз",
      "auth/popup-closed-by-user": "кіру терезесі жабылды",
      "auth/cancelled-popup-request": "кіру терезесі жабылды",
      "auth/unauthorized-domain": "бұл сайт Firebase-те рұқсат етілмеген (Authorized domains)",
      "auth/network-request-failed": "желі қатесі",
      "permission-denied": "сервер жазуға рұқсат бермеді",
      unavailable: "сервер қолжетімсіз",
    };
    return known[code] || (e && e.message) || String(e);
  }

  function requireUser() {
    if (!auth.currentUser) throw "кірмегенсіз";
    return auth.currentUser;
  }

  function levelFields(data) {
    var levels = {};
    for (var i = 1; i <= LEVELS; i++) {
      levels[i] = { score: data["s" + i] || 0, stars: data["t" + i] || 0 };
    }
    return levels;
  }

  // Only the fields the security rules accept; numbers must stay integers.
  function attemptDoc(a) {
    var keys = ["level", "character", "score", "max_score", "correct", "wrong", "playtime_sec", "stars",
      "passed", "completed", "revivals_used", "finished_at", "game_id", "client_version", "answered"];
    var doc = {};
    keys.forEach(function (k) {
      if (a[k] !== undefined) doc[k] = typeof a[k] === "number" ? Math.round(a[k]) : a[k];
    });
    doc.created = F.serverTimestamp();
    return doc;
  }

  // A campaign run (levels 1-10): the attempt plus the player's per-level bests, in one transaction.
  function saveCampaign(user, a) {
    var playerRef = F.doc(db, "players", user.uid);
    var attemptRef = F.doc(F.collection(playerRef, "attempts"));
    return F.runTransaction(db, function (tx) {
      return tx.get(playerRef).then(function (snap) {
        var prev = snap.exists() ? snap.data() : {};
        var next = { name: user.displayName || "Ойыншы", last: attemptRef.id, updated: F.serverTimestamp(), total: 0 };
        for (var i = 1; i <= LEVELS; i++) {
          next["s" + i] = prev["s" + i] || 0;
          next["t" + i] = prev["t" + i] || 0;
        }
        var k = Math.round(a.level);
        next["s" + k] = Math.max(next["s" + k], Math.round(a.score));
        next["t" + k] = Math.max(next["t" + k], Math.round(a.stars));
        for (var j = 1; j <= LEVELS; j++) next.total += next["s" + j];
        tx.set(attemptRef, attemptDoc(a));
        tx.set(playerRef, next);
        return next.total;
      });
    });
  }

  // All-in-One ranking key, the same as ProgressStore.all_in_one_key and firestore.rules: correct
  // answers, then accuracy (per thousand), then the shorter active time.
  function poolRow(user, a, runId) {
    var correct = Math.round(a.correct);
    var answered = Math.round(a.answered);
    var time = Math.round(a.playtime_sec);
    var acc = answered > 0 ? Math.floor((correct * 1000) / answered) : 0;
    return {
      name: user.displayName || "Ойыншы", correct: correct, answered: answered, wrong: Math.round(a.wrong), acc: acc,
      time: time, score: Math.round(a.score), completed: a.completed === true, pool: Math.round(a.max_score / 100),
      key: correct * 100000000 + acc * 100000 + (99999 - time), run: runId, updated: F.serverTimestamp(),
    };
  }

  // An All-in-One run: the attempt, and the personal best in allinone/{uid} only when it is better.
  function saveAllInOne(user, a) {
    var attemptRef = F.doc(F.collection(F.doc(db, "players", user.uid), "attempts"));
    var bestRef = F.doc(db, "allinone", user.uid);
    return F.runTransaction(db, function (tx) {
      return tx.get(bestRef).then(function (snap) {
        var row = poolRow(user, a, attemptRef.id);
        tx.set(attemptRef, attemptDoc(a));
        if (!snap.exists() || row.key > snap.get("key")) tx.set(bestRef, row);
        return 0;
      });
    });
  }

  window.HistoryArenaHub = {
    configured: configured,

    // -> Promise<string>: {"uid","name"} JSON once Firebase has restored any saved session, or "".
    waitForUser: function () {
      return whenReady().then(userJson);
    },

    // -> {"uid","name"} JSON for the current session, or "".
    getCurrentUser: function () {
      return userJson();
    },

    // -> Promise<string> resolving to {"uid","name"} JSON, or rejecting with a message.
    signInWithGoogle: function () {
      return whenReady()
        .then(function () {
          var provider = new A.GoogleAuthProvider();
          provider.setCustomParameters({ prompt: "select_account" });
          return A.signInWithPopup(auth, provider);
        })
        .then(userJson)
        .catch(function (e) {
          throw message(e);
        });
    },

    // -> Promise<void>
    signOut: function () {
      return whenReady().then(function () {
        return A.signOut(auth);
      });
    },

    // payloadJson: one attempt record, stored under players/{uid}/attempts. A campaign run also
    // raises the player's per-level best in players/{uid}; an All-in-One run its personal best in
    // allinone/{uid}; each in one transaction with the attempt.
    // -> Promise<string>: {"ok": true, "total": n} or {"ok": false, "error": "...", "rejected": bool}
    submitResult: function (payloadJson) {
      return whenReady()
        .then(function () {
          var user = requireUser();
          var a = JSON.parse(payloadJson);
          return Math.round(a.level) === ALL_IN_ONE ? saveAllInOne(user, a) : saveCampaign(user, a);
        })
        .then(function (total) {
          return JSON.stringify({ ok: true, total: total });
        })
        .catch(function (e) {
          console.warn("submitResult failed", e);
          // The rules refused this record: sending it again will not help, so the game moves on.
          return JSON.stringify({ ok: false, error: message(e), rejected: !!(e && e.code === "permission-denied") });
        });
    },

    // -> Promise<string>: {"ok": true, "levels": {"1": {"score","stars"}, ...}, "total": n}
    getMyProgress: function () {
      return whenReady()
        .then(function () {
          return F.getDoc(F.doc(db, "players", requireUser().uid));
        })
        .then(function (snap) {
          var data = snap.exists() ? snap.data() : {};
          return JSON.stringify({ ok: true, levels: levelFields(data), total: data.total || 0 });
        })
        .catch(function (e) {
          return JSON.stringify({ ok: false, error: message(e) });
        });
    },

    // Permanent achievements and roles of the signed-in account.
    // -> Promise<string>: {"ok": true, "bossDefeated": bool, "bossBest": n, "admin": bool}
    // admin is true when an administrator document admins/{uid} exists; only the project owner can
    // create those (Firebase Console), the security rules forbid clients from writing them.
    getEntitlements: function () {
      return whenReady()
        .then(function () {
          var uid = requireUser().uid;
          return Promise.all([F.getDoc(F.doc(db, "achievements", uid)), F.getDoc(F.doc(db, "admins", uid))]);
        })
        .then(function (r) {
          var a = r[0].exists() ? r[0].data() : {};
          return JSON.stringify({ ok: true, bossDefeated: a.bossDefeated === true, bossBest: a.bossBest || 0, admin: r[1].exists() });
        })
        .catch(function (e) {
          return JSON.stringify({ ok: false, error: message(e) });
        });
    },

    // Marks the BOSS as defeated for this account (permanent) and raises the best BOSS score.
    // -> Promise<string>: {"ok": true} or {"ok": false, "error": "..."}
    recordBossVictory: function (score) {
      return whenReady()
        .then(function () {
          var ref = F.doc(db, "achievements", requireUser().uid);
          return F.runTransaction(db, function (tx) {
            return tx.get(ref).then(function (snap) {
              var prev = snap.exists() ? snap.data() : {};
              tx.set(ref, {
                bossDefeated: true,
                bossBest: Math.max(prev.bossBest || 0, Math.round(score)),
                firstDefeated: prev.firstDefeated || F.serverTimestamp(),
                updated: F.serverTimestamp(),
              });
            });
          });
        })
        .then(function () {
          return JSON.stringify({ ok: true });
        })
        .catch(function (e) {
          console.warn("recordBossVictory failed", e);
          return JSON.stringify({ ok: false, error: message(e) });
        });
    },

    // board "campaign" (default): players by total score; "allinone": All-in-One personal bests by
    // their ranking key. Rows carry the board's fields: campaign {"name","total","me"}, All-in-One
    // {"name","correct","answered","acc","time","completed","me"}; "me" adds "rank" (0 = no result yet).
    // -> Promise<string>: {"ok": true, "rows": [...], "me": {...}}
    getLeaderboard: function (limit, board) {
      var uid = "";
      var rows = [];
      var pool = board === "allinone";
      var col = pool ? "allinone" : "players";
      var field = pool ? "key" : "total";
      function row(d) {
        var r = { name: d.get("name"), me: d.id === uid };
        if (pool) {
          ["correct", "answered", "acc", "time"].forEach(function (k) {
            r[k] = d.get(k) || 0;
          });
          r.completed = d.get("completed") === true;
        } else {
          r.total = d.get("total");
        }
        return r;
      }
      return whenReady()
        .then(function () {
          uid = requireUser().uid;
          var top = F.query(F.collection(db, col), F.orderBy(field, "desc"), F.limit(Math.min(Math.max(limit || 20, 1), 50)));
          return Promise.all([F.getDocs(top), F.getDoc(F.doc(db, col, uid))]);
        })
        .then(function (r) {
          r[0].forEach(function (d) {
            rows.push(row(d));
          });
          if (!r[1].exists()) return { total: 0, rank: 0 };
          var mine = row(r[1]);
          var higher = F.query(F.collection(db, col), F.where(field, ">", r[1].get(field)));
          return F.getCountFromServer(higher).then(function (c) {
            mine.rank = c.data().count + 1;
            return mine;
          });
        })
        .then(function (me) {
          return JSON.stringify({ ok: true, rows: rows, me: me });
        })
        .catch(function (e) {
          return JSON.stringify({ ok: false, error: message(e) });
        });
    },
  };
})();
