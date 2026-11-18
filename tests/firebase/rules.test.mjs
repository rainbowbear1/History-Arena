// Security-rule tests for firestore.rules. Run with `npm test` in this folder (starts the
// Firestore and Auth emulators; needs Java 21+). No real Firebase project is touched.
import { test, before, after, beforeEach } from "node:test";
import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import {
  collection, deleteDoc, doc, getCountFromServer, getDoc, getDocs, limit, orderBy, query, runTransaction,
  serverTimestamp, setDoc, Timestamp, updateDoc, where,
} from "firebase/firestore";

let env;
const GOOGLE = { firebase: { sign_in_provider: "google.com" } };

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-history-arena",
    firestore: { rules: readFileSync("../../firestore.rules", "utf8"), host: "127.0.0.1", port: 8080 },
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const db = (uid, name, extra = GOOGLE) => env.authenticatedContext(uid, { name, ...extra }).firestore();
const alice = () => db("alice", "Alice A");
const bob = () => db("bob", "Bob B");

function attempt(level, score, extra = {}) {
  const max = { 1: 1300, 2: 1300, 3: 1400, 4: 1400, 10: 1500 }[level] ?? 1300;
  return {
    level, character: "tomyris", score, max_score: max, correct: score / 100, wrong: 1, playtime_sec: 300,
    stars: score >= max * 0.95 ? 3 : score >= max * 0.6 ? 1 : 0, completed: true, revivals_used: 0,
    finished_at: 1763200000, game_id: "history-arena", client_version: "1.0.0", ...extra,
  };
}

// The same transaction as web/firebase-bridge.js submitResult, with optional tampering.
async function submit(fs, uid, name, a, tamper = (next) => next) {
  a = { passed: a.stars > 0, ...a };
  const playerRef = doc(fs, "players", uid);
  const attemptRef = doc(collection(playerRef, "attempts"));
  return runTransaction(fs, async (tx) => {
    const snap = await tx.get(playerRef);
    const prev = snap.exists() ? snap.data() : {};
    let next = { name, last: attemptRef.id, updated: serverTimestamp(), total: 0 };
    for (let i = 1; i <= 10; i++) {
      next["s" + i] = prev["s" + i] || 0;
      next["t" + i] = prev["t" + i] || 0;
    }
    next["s" + a.level] = Math.max(next["s" + a.level], a.score);
    next["t" + a.level] = Math.max(next["t" + a.level], a.stars);
    for (let j = 1; j <= 10; j++) next.total += next["s" + j];
    next = tamper(next, attemptRef);
    tx.set(attemptRef, { ...a, created: serverTimestamp() });
    tx.set(playerRef, next);
  });
}

// Pretends the last write was a minute ago, so the 5-second limit does not get in the way.
async function age(uid) {
  await env.withSecurityRulesDisabled((ctx) =>
    updateDoc(doc(ctx.firestore(), "players", uid), { updated: Timestamp.fromMillis(Date.now() - 60000) }));
}

test("a player saves a result under their own account", async () => {
  await assertSucceeds(submit(alice(), "alice", "Alice A", attempt(1, 1200)));
  const snap = await getDoc(doc(alice(), "players", "alice"));
  if (snap.get("total") !== 1200 || snap.get("s1") !== 1200 || snap.get("name") !== "Alice A") throw new Error("bad row");
});

test("best scores only rise; a weaker run keeps the best", async () => {
  await submit(alice(), "alice", "Alice A", attempt(1, 1200));
  await age("alice");
  await assertSucceeds(submit(alice(), "alice", "Alice A", attempt(1, 900)));
  await age("alice");
  await assertSucceeds(submit(alice(), "alice", "Alice A", attempt(2, 1300)));
  const snap = await getDoc(doc(alice(), "players", "alice"));
  if (snap.get("s1") !== 1200 || snap.get("total") !== 2500) throw new Error("best not kept");
});

test("one account cannot write another account's results", async () => {
  await submit(alice(), "alice", "Alice A", attempt(1, 600));
  await age("alice");
  // Bob runs the same transaction against Alice's documents.
  await assertFails(submit(bob(), "alice", "Bob B", attempt(1, 1500)));
  await assertFails(submit(bob(), "alice", "Alice A", attempt(1, 1500)));
  await assertFails(setDoc(doc(bob(), "players", "alice", "attempts", "x"), { ...attempt(1, 1500), passed: true, created: serverTimestamp() }));
  await assertFails(updateDoc(doc(bob(), "players", "alice"), { name: "Bob B" }));
  await assertFails(deleteDoc(doc(bob(), "players", "alice")));
  const snap = await getDoc(doc(alice(), "players", "alice"));
  if (snap.get("s1") !== 600) throw new Error("Alice's row changed");
});

test("signed-out visitors and non-Google accounts cannot read or write", async () => {
  await submit(alice(), "alice", "Alice A", attempt(1, 600));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDocs(collection(anon, "players")));
  await assertFails(submit(anon, "alice", "Alice A", attempt(1, 1500)));
  const password = db("eve", "Eve", { firebase: { sign_in_provider: "password" } });
  await assertFails(submit(password, "eve", "Eve", attempt(1, 600)));
});

test("signed-in players can read the leaderboard and their rank", async () => {
  await submit(alice(), "alice", "Alice A", attempt(1, 1200));
  await submit(bob(), "bob", "Bob B", attempt(1, 600));
  const top = await assertSucceeds(getDocs(query(collection(bob(), "players"), orderBy("total", "desc"), limit(20))));
  if (top.docs.map((d) => d.id).join() !== "alice,bob") throw new Error("wrong order");
  const higher = await assertSucceeds(getCountFromServer(query(collection(bob(), "players"), where("total", ">", 600))));
  if (higher.data().count !== 1) throw new Error("wrong rank");
});

test("attempt history is private and write-once", async () => {
  await submit(alice(), "alice", "Alice A", attempt(1, 600));
  const own = await getDocs(collection(alice(), "players", "alice", "attempts"));
  if (own.size !== 1) throw new Error("attempt missing");
  const ref = own.docs[0].ref.path;
  await assertFails(getDocs(collection(bob(), "players", "alice", "attempts")));
  await assertFails(updateDoc(doc(alice(), ref), { score: 1500 }));
  await assertFails(deleteDoc(doc(alice(), ref)));
  await assertFails(deleteDoc(doc(alice(), "players", "alice")));
});

test("tampered rows are rejected", async () => {
  await submit(alice(), "alice", "Alice A", attempt(1, 600));
  await age("alice");
  const tries = {
    "score above the level maximum": [attempt(1, 1800)],
    "score that is not a multiple of 100": [attempt(1, 650)],
    "wrong max_score": [attempt(1, 600, { max_score: 9900 })],
    "impossibly fast run": [attempt(1, 1500, { playtime_sec: 3 })],
    "level outside 1..10": [attempt(11, 100, { max_score: 1300 })],
    "extra attempt field": [attempt(1, 700, { uid: "bob" })],
    "total that is not the sum": [attempt(1, 700), (n) => ({ ...n, total: 99999 })],
    "raising another level": [attempt(1, 700), (n) => ({ ...n, s5: 1300, total: n.total + 1300 })],
    "lowering a best": [attempt(2, 300), (n) => ({ ...n, s1: 0, total: n.total - 600 })],
    "best above the attempt": [attempt(1, 700), (n) => ({ ...n, s1: 1500, total: n.total + 800 })],
    "someone else's name": [attempt(1, 700), (n) => ({ ...n, name: "Teacher" })],
    "client-chosen timestamp": [attempt(1, 700), (n) => ({ ...n, updated: Timestamp.fromMillis(0) })],
    "reusing an old attempt": [attempt(1, 700), async (n) => n],
  };
  for (const [label, [first, tamper]] of Object.entries(tries)) {
    let a = first;
    let fn = tamper;
    if (label === "reusing an old attempt") {
      const old = (await getDocs(collection(alice(), "players", "alice", "attempts"))).docs[0].id;
      fn = (n) => ({ ...n, last: old, s1: 1500, total: n.total + 800 });
      a = attempt(1, 1500);
    }
    try {
      await assertFails(submit(alice(), "alice", "Alice A", a, fn));
    } catch (e) {
      throw new Error("accepted: " + label);
    }
  }
  // A player row without an attempt in the same write is rejected too.
  await assertFails(updateDoc(doc(alice(), "players", "alice"), { s1: 1500, total: 1500, updated: serverTimestamp() }));
});

test("at most one result every 5 seconds", async () => {
  await assertSucceeds(submit(alice(), "alice", "Alice A", attempt(1, 600)));
  await assertFails(submit(alice(), "alice", "Alice A", attempt(1, 700)));
});

test("double-score bonus fits within the limit", async () => {
  await assertSucceeds(submit(alice(), "alice", "Alice A", attempt(1, 1500, { stars: 3 })));
});

test("a lower score never overwrites a higher personal best, even when the client tries", async () => {
  await submit(alice(), "alice", "Alice A", attempt(1, 1200));
  await age("alice");
  await assertFails(submit(alice(), "alice", "Alice A", attempt(1, 900), (next) => ({ ...next, s1: 900, total: 900 })));
  const snap = await getDoc(doc(alice(), "players", "alice"));
  if (snap.get("s1") !== 1200) throw new Error("best was lowered");
});

// The same transaction as web/firebase-bridge.js recordBossVictory, with optional tampering.
async function bossVictory(fs, uid, score, tamper = (next) => next) {
  const ref = doc(fs, "achievements", uid);
  return runTransaction(fs, async (tx) => {
    const snap = await tx.get(ref);
    const prev = snap.exists() ? snap.data() : {};
    tx.set(ref, tamper({
      bossDefeated: true, bossBest: Math.max(prev.bossBest || 0, score),
      firstDefeated: prev.firstDefeated || serverTimestamp(), updated: serverTimestamp(),
    }, prev));
  });
}

test("a BOSS victory is stored once and kept; the best only rises", async () => {
  await assertSucceeds(bossVictory(alice(), "alice", 3600));
  await assertSucceeds(bossVictory(alice(), "alice", 2000));
  const snap = await getDoc(doc(alice(), "achievements", "alice"));
  if (snap.get("bossBest") !== 3600 || snap.get("bossDefeated") !== true) throw new Error("achievement not kept");
  await assertFails(bossVictory(alice(), "alice", 2000, (next) => ({ ...next, bossBest: 2000 })));
  await assertFails(bossVictory(alice(), "alice", 4000, (next) => ({ ...next, bossDefeated: false })));
  await assertFails(bossVictory(alice(), "alice", 4000, (next) => ({ ...next, firstDefeated: serverTimestamp() })));
  await assertFails(deleteDoc(doc(alice(), "achievements", "alice")));
});

test("BOSS achievements: own account only, plausible scores only", async () => {
  await assertFails(bossVictory(bob(), "alice", 3600));
  await assertFails(bossVictory(alice(), "alice", 9900));
  await assertFails(bossVictory(alice(), "alice", 3650));
  await bossVictory(alice(), "alice", 3600);
  // Readable by signed-in players (trophies on the leaderboards), writable only by the owner.
  await assertSucceeds(getDoc(doc(bob(), "achievements", "alice")));
  await assertSucceeds(getDoc(doc(alice(), "achievements", "alice")));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "achievements", "alice")));
});

test("admin records: nobody can create them from the game; owners can read their own", async () => {
  await assertFails(setDoc(doc(alice(), "admins", "alice"), { role: "teacher" }));
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), "admins", "teacher"), { role: "teacher" }));
  const teacher = db("teacher", "Teacher T");
  await assertSucceeds(getDoc(doc(teacher, "admins", "teacher")));
  await assertSucceeds(getDoc(doc(alice(), "admins", "alice")));
  await assertFails(getDoc(doc(alice(), "admins", "teacher")));
  await assertFails(deleteDoc(doc(teacher, "admins", "teacher")));
});

// ---- All-in-One (level 12): its own leaderboard allinone/{uid} ----

const POOL = 133; // tasks in the ten campaign banks (the Godot tests check the rules' level maxima)

function poolAttempt(correct, answered, extra = {}) {
  return {
    level: 12, character: "tomyris", score: correct * 100, max_score: POOL * 100, correct, wrong: answered - correct,
    answered, playtime_sec: 1200, stars: 0, passed: false, completed: answered === POOL, revivals_used: 0,
    finished_at: 1763200000, game_id: "history-arena", client_version: "1.0.0", ...extra,
  };
}

// The same transaction as web/firebase-bridge.js saveAllInOne, with optional tampering.
async function poolRun(fs, uid, name, a, tamper = (row) => row) {
  const attemptRef = doc(collection(doc(fs, "players", uid), "attempts"));
  const bestRef = doc(fs, "allinone", uid);
  return runTransaction(fs, async (tx) => {
    const snap = await tx.get(bestRef);
    const acc = a.answered > 0 ? Math.floor((a.correct * 1000) / a.answered) : 0;
    const row = tamper({
      name, correct: a.correct, answered: a.answered, wrong: a.wrong, acc, time: a.playtime_sec, score: a.score,
      completed: a.completed, pool: a.max_score / 100, key: a.correct * 100000000 + acc * 100000 + (99999 - a.playtime_sec),
      run: attemptRef.id, updated: serverTimestamp(),
    });
    tx.set(attemptRef, { ...a, created: serverTimestamp() });
    if (!snap.exists() || row.key > snap.get("key")) tx.set(bestRef, row);
  });
}

test("All-in-One: a run is stored with its personal best; a weaker run keeps the best", async () => {
  await assertSucceeds(poolRun(alice(), "alice", "Alice A", poolAttempt(90, 120)));
  await assertSucceeds(poolRun(alice(), "alice", "Alice A", poolAttempt(40, 60)));
  await assertSucceeds(poolRun(alice(), "alice", "Alice A", poolAttempt(133, POOL, { playtime_sec: 4000 })));
  const best = await getDoc(doc(alice(), "allinone", "alice"));
  if (best.get("correct") !== 133 || best.get("completed") !== true || best.get("acc") !== 1000) throw new Error("best not kept");
  const runs = await getDocs(collection(alice(), "players", "alice", "attempts"));
  if (runs.size !== 3) throw new Error("runs missing");
  // The campaign row is untouched.
  if ((await getDoc(doc(alice(), "players", "alice"))).exists()) throw new Error("campaign row written");
});

test("All-in-One: ranked by correct answers, then accuracy, then time", async () => {
  await poolRun(alice(), "alice", "Alice A", poolAttempt(80, 100));
  await poolRun(bob(), "bob", "Bob B", poolAttempt(80, 90));
  await poolRun(db("cara", "Cara C"), "cara", "Cara C", poolAttempt(80, 90, { playtime_sec: 900 }));
  await poolRun(db("dan", "Dan D"), "dan", "Dan D", poolAttempt(81, 133, { score: 8300, completed: true }));
  const top = await assertSucceeds(getDocs(query(collection(bob(), "allinone"), orderBy("key", "desc"), limit(20))));
  if (top.docs.map((d) => d.id).join() !== "dan,cara,bob,alice") throw new Error("wrong order: " + top.docs.map((d) => d.id).join());
});

test("All-in-One: a lower result never replaces a better one", async () => {
  await poolRun(alice(), "alice", "Alice A", poolAttempt(90, 120));
  const weaker = poolAttempt(50, 70);
  await assertFails(poolRun(alice(), "alice", "Alice A", weaker, (row) => ({ ...row, key: row.key + 9000000000 })));
  const fs = alice();
  await assertFails(runTransaction(fs, async (tx) => {
    const attemptRef = doc(collection(doc(fs, "players", "alice"), "attempts"));
    tx.set(attemptRef, { ...weaker, created: serverTimestamp() });
    tx.set(doc(fs, "allinone", "alice"), {
      name: "Alice A", correct: 50, answered: 70, wrong: 20, acc: 714, time: 1200, score: 5000, completed: false,
      pool: POOL, key: 50 * 100000000 + 714 * 100000 + (99999 - 1200), run: attemptRef.id, updated: serverTimestamp(),
    });
  }));
  if ((await getDoc(doc(alice(), "allinone", "alice"))).get("correct") !== 90) throw new Error("best was lowered");
  await assertFails(deleteDoc(doc(alice(), "allinone", "alice")));
});

test("All-in-One: tampered runs and rows are rejected", async () => {
  const tries = {
    "more correct than answered": [poolAttempt(60, 50, { wrong: 0 })],
    "more answered than the pool": [poolAttempt(100, 140)],
    "wrong pool maximum": [poolAttempt(60, 80, { max_score: 9900 })],
    "score without correct answers": [poolAttempt(60, 80, { score: 9000 })],
    "completed without the whole pool": [poolAttempt(60, 80, { completed: true })],
    "stars on All-in-One": [poolAttempt(60, 80, { stars: 2, passed: true })],
    "wrong count that does not add up": [poolAttempt(60, 80, { wrong: 3 })],
    "accuracy that does not match": [poolAttempt(60, 80), (row) => ({ ...row, acc: 1000, key: row.key + 250 * 100000 })],
    "key that does not match": [poolAttempt(60, 80), (row) => ({ ...row, key: row.key + 1 })],
    "row that differs from its run": [poolAttempt(60, 80), (row) => ({ ...row, correct: 61, key: row.key + 100000000 })],
    "someone else's name": [poolAttempt(60, 80), (row) => ({ ...row, name: "Teacher" })],
    "client-chosen time stamp": [poolAttempt(60, 80), (row) => ({ ...row, updated: Timestamp.fromMillis(0) })],
  };
  for (const [label, [a, tamper]] of Object.entries(tries)) {
    try {
      await assertFails(poolRun(alice(), "alice", "Alice A", a, tamper));
    } catch (e) {
      throw new Error("accepted: " + label);
    }
  }
  // Another account's best, and a best without its run in the same write.
  await assertFails(poolRun(bob(), "alice", "Bob B", poolAttempt(60, 80)));
  await assertFails(setDoc(doc(alice(), "allinone", "alice"), {
    name: "Alice A", correct: 1, answered: 1, wrong: 0, acc: 1000, time: 5, score: 100, completed: false, pool: POOL,
    key: 100000000 + 1000 * 100000 + 99994, run: "nope", updated: serverTimestamp(),
  }));
  // An All-in-One run never raises the campaign.
  await assertFails(submit(alice(), "alice", "Alice A", poolAttempt(60, 80)));
});

test("All-in-One leaderboard: signed-in players only", async () => {
  await poolRun(alice(), "alice", "Alice A", poolAttempt(60, 80));
  await assertSucceeds(getDocs(collection(bob(), "allinone")));
  await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(), "allinone")));
});

// ---- BOSS runs (level 11) and trophies in achievements/{uid} ----

function bossAttempt(correct, extra = {}) {
  const trophy = correct >= 45 ? 3 : correct >= 38 ? 2 : correct >= 30 ? 1 : 0;
  return {
    level: 11, character: "tomyris", score: correct * 100, max_score: 5000, correct, wrong: 50 - correct,
    playtime_sec: 1500, stars: trophy, passed: trophy > 0, completed: true, revivals_used: 0,
    finished_at: 1763200000, game_id: "history-arena", client_version: "1.0.0", ...extra,
  };
}

// The same transaction as web/firebase-bridge.js saveBoss, with optional tampering.
async function bossRun(fs, uid, a, tamper = (next) => next) {
  const attemptRef = doc(collection(doc(fs, "players", uid), "attempts"));
  const ref = doc(fs, "achievements", uid);
  return runTransaction(fs, async (tx) => {
    const snap = await tx.get(ref);
    const prev = snap.exists() ? snap.data() : {};
    tx.set(attemptRef, { ...a, created: serverTimestamp() });
    if (a.stars > 0) {
      tx.set(ref, tamper({
        bossDefeated: true, bossBest: Math.max(prev.bossBest || 0, a.score), trophy: Math.max(prev.trophy || 0, a.stars),
        bestCorrect: Math.max(prev.bestCorrect || 0, a.correct), firstDefeated: prev.firstDefeated || serverTimestamp(),
        updated: serverTimestamp(), run: attemptRef.id,
      }, prev));
    }
  });
}

test("BOSS trophies: earned by correct answers, never downgraded", async () => {
  await assertSucceeds(bossRun(alice(), "alice", bossAttempt(39)));
  let snap = await getDoc(doc(alice(), "achievements", "alice"));
  if (snap.get("trophy") !== 2 || snap.get("bestCorrect") !== 39) throw new Error("silver not stored");
  await assertSucceeds(bossRun(alice(), "alice", bossAttempt(31)));
  await assertSucceeds(bossRun(alice(), "alice", bossAttempt(20, { completed: false, stars: 0, passed: false })));
  snap = await getDoc(doc(alice(), "achievements", "alice"));
  if (snap.get("trophy") !== 2 || snap.get("bestCorrect") !== 39 || snap.get("bossBest") !== 3900) throw new Error("trophy lowered");
  await assertSucceeds(bossRun(alice(), "alice", bossAttempt(47)));
  snap = await getDoc(doc(alice(), "achievements", "alice"));
  if (snap.get("trophy") !== 3) throw new Error("gold not stored");
  // Explicitly lowering is refused.
  await assertFails(bossRun(alice(), "alice", bossAttempt(31), (next) => ({ ...next, trophy: 1, bestCorrect: 31 })));
  await assertFails(deleteDoc(doc(alice(), "achievements", "alice")));
});

test("BOSS trophies: the trophy must match the run's correct answers", async () => {
  const tries = {
    "gold for 35 correct": [bossAttempt(35, { stars: 3 })],
    "bronze below 60 %": [bossAttempt(29, { stars: 1, passed: true })],
    "trophy for an unfinished run": [bossAttempt(40, { completed: false })],
    "more than 50 correct": [bossAttempt(51, { wrong: 0, score: 5100 })],
    "score without the correct answers": [bossAttempt(35, { score: 4500 })],
    "trophy above the run": [bossAttempt(32), (next) => ({ ...next, trophy: 3 })],
    "correct count above the run": [bossAttempt(32), (next) => ({ ...next, bestCorrect: 50 })],
    "best score above the run": [bossAttempt(32), (next) => ({ ...next, bossBest: 5000 })],
  };
  for (const [label, [a, tamper]] of Object.entries(tries)) {
    try {
      await assertFails(bossRun(alice(), "alice", a, tamper));
    } catch (e) {
      throw new Error("accepted: " + label);
    }
  }
  // A trophy without a run in the same write, and another account's achievement.
  await assertFails(setDoc(doc(alice(), "achievements", "alice"), {
    bossDefeated: true, bossBest: 4500, trophy: 3, bestCorrect: 45, firstDefeated: serverTimestamp(), updated: serverTimestamp(),
  }));
  await assertFails(bossRun(bob(), "alice", bossAttempt(45)));
});

test("BOSS: an old victory without run details keeps no trophy and never removes one", async () => {
  // Migration: a victory queued before trophies existed (score only) is stored without a trophy...
  await assertSucceeds(bossVictory(alice(), "alice", 3600, (next) => ({ ...next, trophy: 0, bestCorrect: 0 })));
  let snap = await getDoc(doc(alice(), "achievements", "alice"));
  if (snap.get("bossDefeated") !== true || (snap.get("trophy") || 0) !== 0) throw new Error("legacy victory wrong");
  // ...and cannot claim one.
  await assertFails(bossVictory(alice(), "alice", 3600, (next) => ({ ...next, trophy: 1, bestCorrect: 30 })));
  // A later run earns the trophy; an old victory sent afterwards keeps it.
  await assertSucceeds(bossRun(alice(), "alice", bossAttempt(40)));
  await assertSucceeds(bossVictory(alice(), "alice", 3000, (next, prev) => ({ ...next, trophy: prev.trophy, bestCorrect: prev.bestCorrect })));
  await assertFails(bossVictory(alice(), "alice", 3000, (next) => ({ ...next, trophy: 0, bestCorrect: 0 })));
  snap = await getDoc(doc(alice(), "achievements", "alice"));
  if (snap.get("trophy") !== 2) throw new Error("trophy lost");
});

test("BOSS trophies are visible to signed-in players for the leaderboards", async () => {
  await bossRun(alice(), "alice", bossAttempt(46));
  const list = await assertSucceeds(getDocs(query(collection(bob(), "achievements"), where("trophy", ">", 0))));
  if (list.size !== 1) throw new Error("trophy list");
  await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(), "achievements")));
  await assertFails(setDoc(doc(bob(), "achievements", "alice"), { bossDefeated: true }));
});
