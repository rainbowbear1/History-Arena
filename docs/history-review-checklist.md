# Historical accuracy checklist

All 132 tasks are listed with their answers in `docs/content-review.md`. Questions only use facts
taught in standard Kazakhstan history courses; where sources disagree, the uncertain detail was
left out (for example the exact year of the Аңырақай battle, 1729 or 1730, and the length of the
Отырар siege). Please tick each item after checking it against the school textbook or your teacher.

## New in the playtest pass (please check these first)
The Отырар level now asks mainly about the **Mongol conquest**; extra decoys are hand-written per
question (listed in `docs/content-review.md` as "decoys on harder levels").
- [ ] **otyrar-05** — Темучин proclaimed **Шыңғыс хан** and founded the Mongol Empire in **1206**
      (wrong options 1219, 1162, 1237).
- [ ] **otyrar-06** — Шыңғыс хан's law code: **«Ұлы Яса»**.
- [ ] **otyrar-13** — Khwarazm was ruled by **Мұхаммед** (Ала ад-Дин Мұхаммед II) in 1219; wrong
      options Текеш, Атсыз, Қайырхан. Spelling: is «Мұхаммед» how your textbook names him?
- [ ] **otyrar-07** matching: Мұхаммед шах — "Моңғолдармен соғысқан Хорезм билеушісі".
- [ ] **otyrar-09** chronology starts with **Моңғол империясының құрылуы** (1206).
- [ ] Decoys that are deliberately "near misses" (wrong for this question but real dates or names
      from the same period): xviii_xix-06 **1824** (Kіші жүз, not Орта жүз), independence-01
      **25 Oct 1990** (sovereignty declaration) and **1 Dec 1991**, independence-03 **1993** (first
      constitution, not the current one), independence-07 **Мәлібеков, Шота Уәлиханов** (emblem
      authors), xx_century-02 **Байтұрсынұлы, Дулатұлы** (Алаш leaders, not the chairman),
      xx_century-07 **1989** (last test, not closure), kazakh_khanate-05 **1428**, kazakh_khanate-01
      **Моғолстан** (where Керей and Жәнібек went, not the state they left).
- [ ] xx_century-13 — **Хиуаз Доспанова** replaces Томирис as a wrong option (she was a WWII pilot but
      not a Hero of the Soviet Union).
- [ ] Replaced anachronistic options: golden_horde-07 (Цин императоры → Бату хан, Әбілқайыр хан),
      golden_horde-08, dzungar-01, dzungar-07, huns-02, huns-05, huns-10, saka-09, and the year
      options of xviii_xix-01/06/09/13, xx_century-01.

## Check first (sources differ or wording matters)
- [ ] **dzungar-04, dzungar-09** — Аңырақай: leader given as **Әбілқайыр хан**. Most textbooks say so;
      some name other leaders.
- [ ] **dzungar-08** — «Елім-ай» linked to **Ақтабан шұбырынды** (traditional attribution).
- [ ] **dzungar-11** — **Жалаңтөс батыр** came to help Жәңгір at Орбұлақ (1643).
- [ ] **otyrar-08** — Otrar besieged by Genghis Khan's sons **Шағатай мен Үгедей**.
- [ ] **otyrar-10** — after 1220 the city **was destroyed** (it was later rebuilt; the answer refers
      to 1220 only).
- [ ] **kazakh_khanate-05** — fill-in answer is **1465**; the assignment PDF writes **1465–1466 жж.**
      Should the answer be "1465–1466"?
- [ ] **kazakh_khanate-01** — Керей and Жәнібек left **Әбілқайыр хандығы**.
- [ ] **golden_horde-03** — capital given simply as **Сарай** (Сарай-Бату, later Сарай-Берке).
- [ ] **golden_horde-08** — **Әбілқайыр хандығы** as a successor state (others existed too, e.g.
      Ноғай Ордасы; they are not among the options).
- [ ] **golden_horde-13** — the Ұлытау mausoleum is "**considered**" Жошы хан's (wording hedged on purpose).
- [ ] **xx_century-03** — Ахмет Байтұрсынұлы's main field given as **Kazakh language and alphabet**.

## Quick confirm (well established, but please glance)
- [ ] Years: 1219 (Отырар siege), 1723, 1643, 1771, 1731, 1801, 1822, 1845, 1916, 1936, 1954, 1986,
      1991 (Семей test site closed; independence 16 Dec), 1992 (UN; state symbols), 1993 (теңге),
      1995 (Constitution), 1997 (capital moved to Ақмола).
- [ ] Laws: «Қасым ханның қасқа жолы», «Есім ханның ескі жолы», «Жеті жарғы» (Тәуке).
- [ ] Төле би – Ұлы жүз, Қазыбек би – Орта жүз, Әйтеке би – Кіші жүз.
- [ ] Ясауи mausoleum built on **Әмір Темір's** order; Бату – grandson of Шыңғыс хан; Өзбек хан – Islam.
- [ ] Flag author **Шәкен Ниязбеков**; EXPO-2017 in Астана; Gagarin launched from Байқоңыр (1961).

## Map pins (approximate city coordinates)
- [ ] Pins use rounded city coordinates: Есік (for the Issyk kurgan), Отырар (archaeological site),
      Сарайшық (near Атырау), Байқоңыр (town; the launch pads are a little north-east), Түркістан,
      Семей, Алматы. On the game map these are accurate to well within a pin's size.

## Images
- [ ] `golden_man.jpg` is the museum **reconstruction** of the Golden Man (the question asks only the period).
- [ ] `abai.jpg` — confirm it is the commonly used photograph of Abai.

## Characters and protagonists (decision needed)
- [x] ~~Level 4 suggested Әл-Фараби~~ — fixed: the roster's Әл-Фараби was replaced by **Қайырхан**, the
      ruler who led Отырар's defence in 1219–1220 (the level's questions now focus on the Mongol conquest).
- [ ] Levels 5 (Алтын Орда) and 10 (Тәуелсіздік) have **no suggested protagonist** — no roster character
      fits. Optionally replace one roster character (for example a second Kazakh Khanate khan) with a
      Golden Horde figure.
- [ ] Character titles/descriptions in `data/characters.json`.

## Older content (levels 1–3, written before this review)
- [ ] `saka`, `huns`, `turkic` files — same review as above; note **saka-01** calls Томирис a Saka
      queen (Herodotus calls her queen of the Massagetae, a Saka-related people).
