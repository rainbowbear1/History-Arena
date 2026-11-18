// Fills the running Firestore emulator with a small demo class for trying the teacher dashboard
// locally. No real Firebase project is touched.
//   1. npm run emulators                       (in this folder; needs Java 21+)
//   2. node seed-demo.mjs                      (in another terminal)
//   3. serve the web build on localhost and open admin.html?emulator=1; in the browser console run
//      emulatorSignIn("teacher-demo", "Demo Teacher"). The page says "No access" and shows the
//      account's UID (the Auth emulator chooses it), exactly as for a real teacher.
//   4. node seed-demo.mjs <that UID>           makes that account an administrator; reload the page.
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { readFileSync } from "node:fs";
import { doc, setDoc, Timestamp } from "firebase/firestore";

const env = await initializeTestEnvironment({
  projectId: "demo-history-arena",
  firestore: { rules: readFileSync("../../firestore.rules", "utf8"), host: "127.0.0.1", port: 8080 },
});
const MAX = [1300, 1300, 1400, 1400, 1300, 1300, 1200, 1300, 1300, 1500];
const now = Date.now();
const ago = (hours) => Timestamp.fromMillis(now - hours * 3600 * 1000);

const students = [
  { uid: "aigerim", name: "Айгерім Сәрсенова", passed: 10, stars: 3, boss: 46, pool: [121, 133, 3650, true], hours: 2 },
  { uid: "daniyar", name: "Данияр Оспанов", passed: 10, stars: 2, boss: 39, pool: [70, 96, 2410, false], hours: 20 },
  { uid: "madina", name: "Мадина Қасымова", passed: 6, stars: 1, boss: 0, pool: null, hours: 30 },
  { uid: "timur", name: "Timur Akhmetov", passed: 2, stars: 1, boss: 0, pool: null, hours: 70 },
];

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  if (process.argv[2]) await setDoc(doc(db, "admins", process.argv[2]), { role: "teacher", note: "emulator demo" });
  for (const s of students) {
    const row = { name: s.name, last: "seed", updated: ago(s.hours), total: 0 };
    let n = 0;
    for (let i = 1; i <= 10; i++) {
      const score = i <= s.passed ? Math.round((MAX[i - 1] * (0.7 + 0.1 * s.stars)) / 100) * 100 : 0;
      row["s" + i] = Math.min(score, MAX[i - 1]);
      row["t" + i] = i <= s.passed ? s.stars : 0;
      row.total += row["s" + i];
      if (i <= s.passed) {
        await setDoc(doc(db, "players", s.uid, "attempts", "run" + ++n), {
          level: i, character: "tomyris", score: row["s" + i], max_score: MAX[i - 1], correct: row["s" + i] / 100, wrong: 2,
          playtime_sec: 240 + i * 20, stars: s.stars, passed: true, completed: true, revivals_used: 0, finished_at: 0,
          game_id: "history-arena", client_version: "1.0.0", created: ago(s.hours + 10 - i),
        });
      }
    }
    await setDoc(doc(db, "players", s.uid, "attempts", "left"), {
      level: Math.min(s.passed + 1, 10), character: "mode", score: 300, max_score: 1300, correct: 3, wrong: 4, playtime_sec: 95,
      stars: 0, passed: false, completed: false, abandoned: true, revivals_used: 0, finished_at: 0, game_id: "history-arena",
      client_version: "1.0.0", created: ago(s.hours - 0.5),
    });
    await setDoc(doc(db, "players", s.uid), row);
    await setDoc(doc(db, "profiles", s.uid), { name: s.name, firstSeen: ago(s.hours + 48), lastSeen: ago(s.hours - 1) });
    if (s.boss) {
      const trophy = s.boss >= 45 ? 3 : s.boss >= 38 ? 2 : 1;
      await setDoc(doc(db, "players", s.uid, "attempts", "boss"), {
        level: 11, character: "abylai", score: s.boss * 100, max_score: 5000, correct: s.boss, wrong: 50 - s.boss, playtime_sec: 1610,
        stars: trophy, passed: true, completed: true, revivals_used: 0, finished_at: 0, game_id: "history-arena", client_version: "1.0.0",
        created: ago(s.hours),
      });
      await setDoc(doc(db, "achievements", s.uid), {
        bossDefeated: true, bossBest: s.boss * 100, trophy, bestCorrect: s.boss, firstDefeated: ago(s.hours), updated: ago(s.hours), run: "boss",
      });
    }
    if (s.pool) {
      const [correct, answered, time, completed] = s.pool;
      const acc = Math.floor((correct * 1000) / answered);
      await setDoc(doc(db, "players", s.uid, "attempts", "pool"), {
        level: 12, character: "kerey", score: correct * 100, max_score: 13300, correct, wrong: answered - correct, answered,
        playtime_sec: time, stars: 0, passed: false, completed, revivals_used: 0, finished_at: 0, game_id: "history-arena",
        client_version: "1.0.0", created: ago(s.hours - 0.2),
      });
      await setDoc(doc(db, "allinone", s.uid), {
        name: s.name, correct, answered, wrong: answered - correct, acc, time, score: correct * 100, completed, pool: 133,
        key: correct * 100000000 + acc * 100000 + (99999 - time), run: "pool", updated: ago(s.hours - 0.2),
      });
    }
  }
});
console.log("Seeded %d demo players%s.", students.length, process.argv[2] ? " and the administrator " + process.argv[2] : "");
await env.cleanup();
