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
  const max = { 1: 1500, 2: 1300, 3: 1400 }[level] ?? 1300;
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
  await assertSucceeds(submit(alice(), "alice", "Alice A", attempt(1, 1700, { stars: 3 })));
});
