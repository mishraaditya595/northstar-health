const fixture = {
  today: "Friday, 23 October 2026",
  routine: "Full Body A",
  exercises: [
    { name: "Squat", detail: "3 × 8 · 60 kg", previous: "3 × 8 · 57.5 kg" },
    { name: "Bench press", detail: "3 × 8 · 45 kg", previous: "3 × 8 · 42.5 kg" },
    { name: "Seated cable row", detail: "3 × 10 · 42 kg", previous: "3 × 10 · 40 kg" },
    { name: "Romanian deadlift", detail: "3 × 8 · 55 kg", previous: "3 × 8 · 52.5 kg" },
    { name: "Plank", detail: "3 × 45 sec", previous: "3 × 40 sec" },
  ],
  health: {
    sleep: "6 h 18 min",
    sleepAverage: "7 h 10 min",
    steps: "6,420",
    heartRate: "58 bpm",
    weight: "74.2 kg",
  },
};

const state = {
  screen: "today",
  theme: "light",
  onboardingStep: 0,
  onboardingGoal: "Build strength",
  onboardingDays: ["Mon", "Wed", "Fri"],
  onboardingEquipment: "Gym",
  energy: null,
  workout: {
    active: false,
    minimised: false,
    completedSets: 0,
    totalSets: 3,
    weight: [60, 60, 60],
    reps: [8, 8, 8],
    note: "",
  },
  completedToday: false,
  overlay: null,
  timerSeconds: 90,
};

const app = document.querySelector("#app");
const rail = document.querySelector("#prototype-rail");

function icon(name) {
  const icons = {
    today: "⌂",
    train: "◒",
    progress: "↗",
    health: "♡",
    profile: "A",
    back: "‹",
    arrow: "›",
    sleep: "☾",
    steps: "⌁",
    heart: "♡",
    weight: "◉",
    workout: "✦",
    timer: "◷",
    note: "≡",
    settings: "⚙",
    lock: "▣",
    export: "↥",
    check: "✓",
    plus: "+",
  };
  return icons[name] || "•";
}

function button(label, action, className = "primary-button", attrs = "") {
  return `<button class="${className}" data-action="${action}" ${attrs}>${label}</button>`;
}

function metricCard(type, label, value, source, action = "") {
  const clickable = action ? `data-action="${action}" role="button" tabindex="0"` : "";
  return `<div class="metric-card ${type}" ${clickable}>
    <span class="metric-icon">${icon(type)}</span>
    <span class="metric-label">${label}</span>
    <strong class="metric-value">${value}</strong>
    <span class="metric-source">${source}</span>
  </div>`;
}

function topbar(title, subtitle = "", action = "settings") {
  return `<header class="app-topbar">
    <div><p class="date-label">${subtitle}</p><h2>${title}</h2></div>
    <button class="profile-button" data-action="${action}" aria-label="Open profile and settings">A</button>
  </header>`;
}

function backbar(title, action = "back") {
  return `<header class="app-topbar compact">
    <button class="back-button" data-action="${action}" aria-label="Go back">${icon("back")}</button>
    <h3>${title}</h3><span style="width:40px"></span>
  </header>`;
}

function sectionHeading(title, link = "", action = "") {
  return `<div class="section-heading"><h3>${title}</h3>${link ? `<button class="text-button" data-action="${action}">${link}</button>` : ""}</div>`;
}

function nav(active) {
  const items = [
    ["today", "Today", "today"],
    ["train", "Train", "train"],
    ["progress", "Progress", "progress"],
    ["health", "Health", "health"],
  ];
  return `<nav class="bottom-nav" aria-label="Main navigation">${items.map(([id, label, glyph]) =>
    `<button class="nav-item ${active === id ? "active" : ""}" data-action="${id}"><span class="nav-icon">${icon(glyph)}</span>${label}</button>`
  ).join("")}</nav>`;
}

function shell(content, active = "today", options = {}) {
  const resume = state.workout.active && state.workout.minimised && !options.hideResume
    ? `<div class="mini-resume"><span class="resume-pulse"></span><div><strong>Workout in progress</strong><span>Squat · ${state.workout.completedSets}/${state.workout.totalSets} sets</span></div><button data-action="resume-workout">Resume</button></div>`
    : "";
  return `<div class="app-shell"><div class="app-scroll">${content}</div>${resume}${nav(active)}</div>`;
}

function onboardingShell(content) {
  return `<div class="app-shell onboarding"><div class="app-scroll">${content}</div></div>`;
}

function progressDots(step) {
  return `<div class="progress-pips">${[0, 1, 2].map((index) => `<i class="${index <= step ? "active" : ""}"></i>`).join("")}</div>`;
}

function render() {
  document.body.classList.toggle("dark", state.theme === "dark");
  app.innerHTML = renderScreen();
  rail.innerHTML = renderRail();
  bindActions();
  if (state.overlay?.type === "timer") startTimerLoop();
}

function renderScreen() {
  if (state.screen === "onboarding") return renderOnboarding();
  if (state.screen === "train") return renderTrain();
  if (state.screen === "templates") return renderTemplates();
  if (state.screen === "routine") return renderRoutine();
  if (state.screen === "builder") return renderBuilder();
  if (state.screen === "schedule") return renderSchedule();
  if (state.screen === "activeWorkout") return renderActiveWorkout();
  if (state.screen === "finishReview") return renderFinishReview();
  if (state.screen === "complete") return renderComplete();
  if (state.screen === "sessionDetail") return renderSessionDetail();
  if (state.screen === "progress") return renderProgress();
  if (state.screen === "progressDetail") return renderProgressDetail();
  if (state.screen === "weeklyReview") return renderWeeklyReview();
  if (state.screen === "health") return renderHealth();
  if (state.screen === "healthDetail") return renderHealthDetail();
  if (state.screen === "connections") return renderConnections();
  if (state.screen === "settings") return renderSettings();
  if (state.screen === "privacy") return renderPrivacy();
  return renderToday();
}

function renderToday() {
  const completed = state.completedToday;
  const progress = completed ? 100 : 66.66;
  const weekLabel = completed ? "3 of 3 planned sessions complete" : "2 of 3 planned sessions complete";
  return shell(`
    ${topbar("Today", "Friday · 23 Oct 2026")}
    <section class="hero-card">
      <p class="kicker">${completed ? "Workout complete" : "Planned for today"}</p>
      <h3>${fixture.routine}</h3>
      <p>5 exercises · Around 45 min · Gym</p>
      <div class="hero-actions">${button(completed ? "View session" : "Start workout", completed ? "session-detail" : "start-workout", "primary-button")}<button class="text-button" data-action="routine">${completed ? "Edit routine" : "Edit"}</button><button class="text-button" data-action="schedule">Move</button></div>
    </section>
    ${sectionHeading("Energy check-in", "Edit later", "energy")}
    <div class="checkin-row">${["Low", "Okay", "Good", "Skip"].map((item) => `<button class="checkin-chip ${state.energy === item ? "selected" : ""}" data-action="energy-${item.toLowerCase()}">${item}</button>`).join("")}</div>
    ${sectionHeading("Recent health", "See all", "health")}
    <div class="health-grid">
      ${metricCard("sleep", "Sleep", fixture.health.sleep, "Apple Health · Today", "sleep-detail")}
      ${metricCard("steps", "Steps", fixture.health.steps, "Updated 18:20", "steps-detail")}
      ${metricCard("heart", "Resting HR", fixture.health.heartRate, "23 Oct · Apple", "heart-detail")}
    </div>
    <div class="section-heading"><h3>One useful context</h3></div>
    <div class="card insight-card"><span class="insight-mark">☾</span><p>Your last recorded sleep was <strong>52 min shorter</strong> than your recent average.</p><button class="text-button" data-action="sleep-detail">View</button></div>
    ${sectionHeading("This week", "Weekly review", "weekly-review")}
    <div class="card week-card"><div class="week-card-top"><strong>${weekLabel}</strong><span>${completed ? "Keep the rhythm" : "Friday session"}</span></div><div class="progress-track"><div class="progress-fill ${completed ? "full" : ""}" style="width:${progress}%"></div></div><div class="week-dots"><span class="done"><i></i>Mon</span><span class="done"><i></i>Wed</span><span class="${completed ? "done" : "today"}"><i></i>Fri</span><span><i></i>Sun</span></div></div>
  `, "today");
}

function renderTrain() {
  return shell(`
    ${topbar("Train", "Plan and perform training")}
    <div class="row-between"><div><p class="muted">Friday, 23 October</p><h3 style="margin:4px 0 0;font-size:18px">Your training week</h3></div>${button("+ Create routine", "builder", "secondary-button")}</div>
    <div class="week-strip" style="margin-top:18px">${["M","T","W","T","F","S","S"].map((day, i) => `<button class="day-cell ${i === 4 ? "selected" : ""}" data-action="schedule"><small>${day}</small><strong>${19 + i}</strong></button>`).join("")}</div>
    ${sectionHeading("Today’s session", "Open routine", "routine")}
    <div class="card routine-card"><div class="row-between"><div><span class="tag">${icon("workout")} Strength</span><h3 style="margin-top:10px">Full Body A</h3></div><span class="muted">45 min</span></div><div class="routine-meta"><span>5 exercises</span><span>Gym equipment</span><span>Last used 19 Oct</span></div>${button("Start workout", "start-workout", "primary-button full-width")}</div>
    ${sectionHeading("Saved routines", "Templates", "templates")}
    <div class="stack"><div class="card list-card" data-action="routine" role="button" tabindex="0"><span class="list-art">✦</span><div class="list-copy"><h3>Full Body A</h3><p>5 exercises · Last used 19 Oct</p></div><span class="arrow">›</span></div><div class="card list-card" data-action="templates" role="button" tabindex="0"><span class="list-art">◌</span><div class="list-copy"><h3>Browse reviewed templates</h3><p>Strength, muscle building and general fitness</p></div><span class="arrow">›</span></div></div>
    ${sectionHeading("More ways to move", "", "")}
    <div class="stack"><div class="card list-card" data-action="schedule" role="button" tabindex="0"><span class="list-art">▦</span><div class="list-copy"><h3>Weekly schedule</h3><p>Move one session without changing future weeks</p></div><span class="arrow">›</span></div><div class="card list-card" data-action="cardio" role="button" tabindex="0"><span class="list-art">⌁</span><div class="list-copy"><h3>Log cardio</h3><p>Walk, run or cycle without live tracking</p></div><span class="arrow">›</span></div></div>
  `, "train");
}

function renderTemplates() {
  return shell(`${backbar("Templates", "train")}<p class="muted" style="margin:0 0 18px">Start with something reviewed, then make it yours.</p><div class="template-grid">
    <article class="template-card"><div class="template-visual"><span></span><span></span><span></span></div><h3>Three-day full body</h3><p>Strength · 3 days/week · Gym · About 45 min</p>${button("View template", "template-full-body", "secondary-button full-width")}</article>
    <article class="template-card"><div class="template-visual"><span style="background:rgba(94,90,166,.5)"></span><span style="background:rgba(94,90,166,.22)"></span><span style="background:rgba(36,92,66,.3)"></span></div><h3>Upper / lower starter</h3><p>Build muscle · 4 days/week · Gym · About 50 min</p>${button("View template", "template-upper-lower", "secondary-button full-width")}</article>
  </div>`, "train");
}

function renderRoutine() {
  return shell(`${backbar("Full Body A", "train")}<div class="row-between"><div><span class="tag">${icon("workout")} Saved routine</span><p class="muted" style="margin:9px 0 0">Gym · Around 45 min · 5 exercises</p></div><button class="icon-button small" data-action="builder">⋯</button></div><div class="section-heading"><h3>Exercise order</h3><span>Targets</span></div><div class="detail-list">${fixture.exercises.map((exercise, index) => `<div class="exercise-row"><span class="exercise-index">${index + 1}</span><div><strong>${exercise.name}</strong><span>${exercise.detail} · Rest ${index === 4 ? "45 sec" : "90 sec"}</span></div></div>`).join("")}</div><div class="card week-card" style="margin-top:15px"><div class="week-card-top"><strong>Weekly assignment</strong><span>Mon / Wed / Fri</span></div><p class="muted" style="margin:0;line-height:1.5">This routine is planned for Friday today. Moving one occurrence will not change future weeks.</p></div><div style="margin-top:18px">${button("Start workout", "start-workout", "primary-button full-width")}</div><div style="display:flex;justify-content:center;gap:20px;margin-top:16px"><button class="text-button" data-action="builder">Edit routine</button><button class="text-button" data-action="schedule">Schedule</button></div>`, "train");
}

function renderBuilder() {
  return shell(`${backbar("Routine builder", "routine")}<label class="field-label" style="margin-bottom:18px">Routine name<input value="Full Body A" /></label><div class="section-heading"><h3>Exercises</h3><span>Drag to reorder</span></div><div class="detail-list">${fixture.exercises.map((exercise, index) => `<div class="exercise-row"><span class="exercise-index">≡</span><div style="flex:1"><strong>${exercise.name}</strong><span>${exercise.detail} · Rest ${index === 4 ? "45 sec" : "90 sec"}</span></div><button class="icon-button small" data-action="exercise-detail">›</button></div>`).join("")}</div><button class="secondary-button full-width" style="margin-top:12px" data-action="exercise-picker">+ Add exercise</button><label class="field-label" style="margin-top:16px">Routine notes<textarea placeholder="Optional notes for future sessions"></textarea></label><div style="margin-top:18px">${button("Save routine", "routine", "primary-button full-width")}</div>`, "train");
}

function renderSchedule() {
  return shell(`${backbar("Weekly schedule", "train")}<div class="row-between"><div><h3 style="margin:0;font-size:18px">19–25 October</h3><p class="muted" style="margin:5px 0 0">Move a single occurrence or update the plan.</p></div><button class="quiet-button" data-action="schedule">Today</button></div><div class="stack" style="margin-top:19px">${["Monday, 19 Oct", "Tuesday, 20 Oct", "Wednesday, 21 Oct", "Thursday, 22 Oct", "Friday, 23 Oct", "Saturday, 24 Oct", "Sunday, 25 Oct"].map((day, i) => `<div class="card list-card" data-action="schedule"><div class="list-copy"><h3>${day}</h3><p>${[0,2,4].includes(i) ? `${i === 4 ? "Full Body A · Today" : i === 2 ? "Full Body B · Completed" : "Full Body A · Completed"}` : "Rest / unassigned"}</p></div><span class="arrow">›</span></div>`).join("")}</div>`, "train");
}

function renderActiveWorkout() {
  const rows = state.workout.weight.map((weight, index) => `<tr class="${index < state.workout.completedSets ? "completed" : ""}">
    <td>${index + 1}</td><td class="previous">${index === 0 ? "57.5" : "57.5"} / 8</td>
    <td><input aria-label="Set ${index + 1} weight" type="number" value="${weight}" /></td>
    <td><input aria-label="Set ${index + 1} reps" type="number" value="${state.workout.reps[index]}" /></td>
    <td><button class="complete-button" data-action="complete-set" data-set="${index}">${index < state.workout.completedSets ? "Done" : "Complete"}</button></td>
  </tr>`).join("");
  return `<div class="app-shell workout-shell"><div class="app-scroll"><div class="workout-top"><button class="back-button" data-action="minimise-workout" aria-label="Minimise workout">↓</button><div class="center"><strong>Full Body A</strong><span>1 of 5 · Squat</span></div><span class="elapsed">18:42</span></div><div class="current-exercise"><div class="exercise-heading"><div><h2>Squat</h2><p>3 working sets · 60 kg target · 90 sec rest</p></div><span class="tag">${state.workout.completedSets}/${state.workout.totalSets}</span></div><table class="set-table"><thead><tr><th>Set</th><th>Previous</th><th>kg</th><th>Reps</th><th></th></tr></thead><tbody>${rows}</tbody></table><div class="workout-secondary"><button class="quiet-button" data-action="add-set">+ Add set</button><button class="quiet-button" data-action="workout-note">${icon("note")} Notes / effort</button></div></div><div class="next-card"><span class="exercise-index">2</span><div><strong>Next · Bench press</strong><span>3 × 8 at 45 kg · Previous 42.5 kg</span></div><span class="arrow">›</span></div><button class="finish-link" data-action="finish-review">Finish workout</button></div>${state.overlay ? renderOverlay() : ""}</div>`;
}

function renderFinishReview() {
  return shell(`${backbar("Finish workout?", "active-workout")}<div class="card week-card"><div class="week-card-top"><strong>Full Body A</strong><span>18:42</span></div><div class="progress-track"><div class="progress-fill" style="width:${state.workout.completedSets === 0 ? 0 : 22}%"></div></div><p class="muted" style="margin:13px 0 0">${state.workout.completedSets} of 15 sets completed · 4 exercises still to go</p></div><div class="section-heading"><h3>Before you save</h3></div><div class="card insight-card"><span class="insight-mark">!</span><p>Unfinished sets will not be recorded as completed. You can keep training or save this partial session.</p></div><label class="field-label" style="margin-top:18px">Session note<textarea placeholder="How did this session feel?"></textarea></label><div style="display:grid;gap:9px;margin-top:18px">${button("Keep training", "active-workout", "secondary-button full-width")}${button("Save workout", "complete", "primary-button full-width")}</div>`, "today");
}

function renderComplete() {
  return shell(`${backbar("Workout complete", "today")}<div style="padding:14px 0 6px;text-align:center"><div style="display:grid;place-items:center;width:62px;height:62px;margin:8px auto 17px;border-radius:20px;background:var(--forest-soft);color:var(--forest);font-size:28px">✓</div><p class="kicker" style="color:var(--forest);">Saved on this phone</p><h2 style="margin:0;font-size:28px;letter-spacing:-.06em">Nice work, Alex.</h2><p class="muted" style="max-width:250px;margin:10px auto 0;line-height:1.5">Your Full Body A session is saved. One small step becomes a pattern when you can see it later.</p></div><div class="card week-card" style="margin-top:22px"><div class="week-card-top"><strong>Full Body A</strong><span>23 Oct 2026</span></div><div class="record-list"><div class="record-row"><span>Duration</span><strong>18 min</strong></div><div class="record-row"><span>Completed sets</span><strong>${state.workout.completedSets} / 15</strong></div><div class="record-row"><span>Highlight</span><strong>${state.workout.completedSets ? "60 kg squat" : "Session saved"}</strong></div></div></div><div style="display:grid;gap:9px;margin-top:17px">${button("View session", "session-detail", "secondary-button full-width")}${button("Done", "today", "primary-button full-width")}</div>`, "today");
}

function renderSessionDetail() {
  return shell(`${backbar("Session detail", "today")}<div class="row-between"><div><span class="tag">${icon("workout")} Northstar logger</span><h3 style="margin:10px 0 4px;font-size:19px">Full Body A</h3><p class="muted" style="margin:0">Friday, 23 Oct 2026 · 18 min</p></div><button class="icon-button small" data-action="settings">⋯</button></div><div class="section-heading"><h3>Completed sets</h3><span>${state.workout.completedSets} recorded</span></div><div class="detail-list">${fixture.exercises.slice(0, state.completedToday ? 5 : 1).map((exercise, index) => `<div class="exercise-row"><span class="exercise-index">✓</span><div><strong>${exercise.name}</strong><span>${index === 0 ? `${state.workout.completedSets} × 8 · 60 kg` : exercise.detail}</span></div></div>`).join("")}</div><div class="card insight-card" style="margin-top:16px"><span class="insight-mark">i</span><p>This session was recorded by Northstar. Imported watch summaries may only include duration and activity type.</p></div>`, "today");
}

function renderProgress() {
  return shell(`${topbar("Progress", "Review change over time")}<div class="card week-card"><div class="week-card-top"><strong>2 of 3 sessions this week</strong><span>4 weeks</span></div><div class="bar-chart"><div class="bar" style="height:45%" data-label="W-3"><span class="bar-value">2</span></div><div class="bar" style="height:70%" data-label="W-2"><span class="bar-value">3</span></div><div class="bar" style="height:55%" data-label="W-1"><span class="bar-value">2</span></div><div class="bar highlight" style="height:70%" data-label="Now"><span class="bar-value">2</span></div></div></div>${sectionHeading("Exercise progress", "See all", "progress-detail")}<div class="stack"><div class="card list-card" data-action="progress-detail" role="button" tabindex="0"><span class="list-art">↑</span><div class="list-copy"><h3>Squat</h3><p>Best set · 60 kg × 8 · +2.5 kg since 19 Oct</p></div><span class="arrow">›</span></div><div class="card list-card" data-action="progress-detail" role="button" tabindex="0"><span class="list-art">→</span><div class="list-copy"><h3>Bench press</h3><p>Best set · 45 kg × 8 · +2.5 kg since 19 Oct</p></div><span class="arrow">›</span></div></div>${sectionHeading("Recent personal bests", "", "")}<div class="card week-card"><div class="record-list"><div class="record-row"><span>Squat · 23 Oct</span><strong>60 kg × 8</strong></div><div class="record-row"><span>Bench press · 21 Oct</span><strong>45 kg × 8</strong></div><div class="record-row"><span>Romanian deadlift · 19 Oct</span><strong>55 kg × 8</strong></div></div></div>${sectionHeading("Weekly review", "Open review", "weekly-review")}<div class="card insight-card"><span class="insight-mark">↗</span><p>You completed one more session than the week before. Sleep context stays separate from performance.</p><button class="text-button" data-action="weekly-review">Open</button></div>`, "progress");
}

function renderProgressDetail() {
  return shell(`${backbar("Squat progress", "progress")}<div class="row-between"><div><span class="tag">Best set load</span><h3 style="margin:10px 0 0;font-size:25px">60 kg × 8</h3></div><select style="padding:9px;border:1px solid var(--line);border-radius:10px;background:var(--surface);color:var(--ink);font-size:11px"><option>4 weeks</option><option>12 weeks</option></select></div><div class="card chart-card" style="margin-top:18px"><h3>Recorded best set</h3><svg class="chart-svg" viewBox="0 0 340 132" role="img" aria-label="Squat recorded best set rose from 52.5 to 60 kilograms"><path d="M6 112 H334 M6 77 H334 M6 42 H334" stroke="var(--line)" stroke-width="1"/><path d="M12 104 C75 100 85 90 140 82 S215 59 255 50 S302 34 329 23" fill="none" stroke="var(--forest)" stroke-width="3" stroke-linecap="round"/><circle cx="12" cy="104" r="4" fill="var(--surface)" stroke="var(--forest)" stroke-width="3"/><circle cx="140" cy="82" r="4" fill="var(--surface)" stroke="var(--forest)" stroke-width="3"/><circle cx="255" cy="50" r="4" fill="var(--surface)" stroke="var(--forest)" stroke-width="3"/><circle cx="329" cy="23" r="5" fill="var(--forest)"/><text x="275" y="18" fill="var(--muted)" font-size="10">60 kg</text></svg><div class="chart-labels"><span>6 Oct</span><span>13 Oct</span><span>19 Oct</span><span>23 Oct</span></div></div><div class="section-heading"><h3>Sessions behind the line</h3><span>4 records</span></div><div class="card week-card"><div class="record-list"><div class="record-row"><span>23 Oct · Full Body A</span><strong>60 kg × 8</strong></div><div class="record-row"><span>19 Oct · Full Body A</span><strong>57.5 kg × 8</strong></div><div class="record-row"><span>12 Oct · Full Body A</span><strong>55 kg × 8</strong></div><div class="record-row"><span>6 Oct · Full Body A</span><strong>52.5 kg × 8</strong></div></div></div>`, "progress");
}

function renderWeeklyReview() {
  return shell(`${backbar("Weekly review", "progress")}<p class="date-label">19–25 October 2026</p><h2 style="margin:0;font-size:27px;letter-spacing:-.06em">A steady week.</h2><div class="card week-card" style="margin-top:18px"><div class="week-card-top"><strong>2 of 3 planned sessions complete</strong><span>So far</span></div><div class="progress-track"><div class="progress-fill" style="width:66%"></div></div><div class="record-list" style="margin-top:13px"><div class="record-row"><span>Monday · Full Body A</span><strong>Complete</strong></div><div class="record-row"><span>Wednesday · Full Body B</span><strong>Complete</strong></div><div class="record-row"><span>Friday · Full Body A</span><strong>Planned</strong></div></div></div>${sectionHeading("Performance change", "", "")}<div class="card insight-card"><span class="insight-mark">↑</span><p>Your squat best set moved from <strong>57.5 kg to 60 kg</strong> in the last session.</p></div>${sectionHeading("Sleep context", "Sleep detail", "sleep-detail")}<div class="card week-card"><div class="row-between"><div><span class="muted">Recent average</span><h3 style="margin:5px 0 0;font-size:20px">7 h 10 min</h3></div><div style="text-align:right"><span class="muted">Latest</span><h3 style="margin:5px 0 0;font-size:20px;color:var(--sleep)">6 h 18 min</h3></div></div><p class="muted" style="margin:13px 0 0;line-height:1.5">This is context, not a readiness score or a medical conclusion.</p></div><div style="margin-top:18px">${button("Edit next week’s plan", "schedule", "secondary-button full-width")}</div>`, "progress");
}

function renderHealth() {
  return shell(`${topbar("Health", "Your imported and manual metrics")}<div class="row-between"><div><span class="tag">Connected</span><p class="muted" style="margin:9px 0 0">Apple Watch via Apple Health</p></div><button class="text-button" data-action="connections">Manage</button></div><div class="card insight-card" style="margin-top:17px"><span class="insight-mark">↻</span><p>Last sync <strong>18:20 today</strong>. Data dates are shown on every card.</p><button class="text-button" data-action="connections">Sources</button></div>${sectionHeading("Today", "", "")}<div class="stack">${metricCard("sleep", "Sleep", fixture.health.sleep, "Night ending 23 Oct · Apple Health", "sleep-detail")}${metricCard("steps", "Steps", fixture.health.steps, "23 Oct · Updated 18:20", "steps-detail")}${metricCard("heart", "Resting heart rate", fixture.health.heartRate, "23 Oct · Apple Health", "heart-detail")}${metricCard("weight", "Weight", fixture.health.weight, "Entered 22 Oct · Manual", "weight-detail")}</div>${sectionHeading("Imported activities", "Session history", "session-detail")}<div class="card list-card"><span class="list-art">⌁</span><div class="list-copy"><h3>Outdoor walk</h3><p>22 Oct · 28 min · Apple Health summary</p></div><span class="tag">Imported</span></div>`, "health");
}

function renderHealthDetail() {
  const kind = state.healthDetail || "sleep";
  const data = {
    sleep: { title: "Sleep", icon: "sleep", value: fixture.health.sleep, caption: "Night ending 23 October", accent: "sleep", note: "Compared with your 7-night average ending 22 October." },
    steps: { title: "Steps", icon: "steps", value: fixture.health.steps, caption: "Friday, 23 October · Updated 18:20", accent: "", note: "No target is set. Northstar keeps this as a record, not a judgement." },
    heart: { title: "Resting heart rate", icon: "heart", value: fixture.health.heartRate, caption: "Record dated 23 October", accent: "", note: "Northstar does not grade this as normal or abnormal." },
    weight: { title: "Weight", icon: "weight", value: fixture.health.weight, caption: "Manual entry · 22 October", accent: "", note: "Manual and imported records remain visibly separate." },
  }[kind];
  const isSleep = kind === "sleep";
  const chart = isSleep ? `<div class="bar-chart" style="height:152px"><div class="bar" style="height:70%;background:var(--sleep-soft)" data-label="17"><span class="bar-value">7:02</span></div><div class="bar" style="height:78%;background:var(--sleep-soft)" data-label="18"><span class="bar-value">7:24</span></div><div class="bar" style="height:65%;background:var(--sleep-soft)" data-label="19"><span class="bar-value">6:12</span></div><div class="bar" style="height:82%;background:var(--sleep-soft)" data-label="20"><span class="bar-value">7:40</span></div><div class="bar" style="height:75%;background:var(--sleep-soft)" data-label="21"><span class="bar-value">7:15</span></div><div class="bar" style="height:79%;background:var(--sleep-soft)" data-label="22"><span class="bar-value">7:31</span></div><div class="bar highlight" style="height:63%;background:var(--sleep)" data-label="23"><span class="bar-value">6:18</span></div></div>` : `<div class="chart-card" style="margin-top:14px"><svg class="chart-svg" viewBox="0 0 340 132"><path d="M6 112 H334 M6 77 H334 M6 42 H334" stroke="var(--line)" stroke-width="1"/><path d="M12 78 C64 71 83 82 132 58 S195 70 237 48 S285 55 329 29" fill="none" stroke="var(--forest)" stroke-width="3" stroke-linecap="round"/><circle cx="329" cy="29" r="5" fill="var(--forest)"/></svg><div class="chart-labels"><span>17 Oct</span><span>19 Oct</span><span>21 Oct</span><span>23 Oct</span></div></div>`;
  return shell(`${backbar(`${icon(data.icon)} ${data.title}`, "health")}<div class="metric-hero ${data.accent}"><div><span class="big-label">${data.caption}</span><div class="big-number">${data.value}</div></div><span class="trend">${isSleep ? "52 min below\nrecent average" : "Source verified"}</span></div><div class="card chart-card" style="margin-top:14px"><div class="row-between"><h3>${isSleep ? "Last 7 nights" : "Recent records"}</h3><select style="padding:8px;border:1px solid var(--line);border-radius:9px;background:var(--surface);color:var(--ink);font-size:10px"><option>${isSleep ? "7 days" : "30 days"}</option><option>4 weeks</option></select></div>${chart}</div><div class="section-heading"><h3>Records</h3><span>Source and date</span></div><div class="card week-card"><div class="record-list">${isSleep ? `<div class="record-row"><span>23 Oct · Apple Health</span><strong>6 h 18 min</strong></div><div class="record-row"><span>22 Oct · Apple Health</span><strong>7 h 31 min</strong></div><div class="record-row"><span>21 Oct · Apple Health</span><strong>7 h 15 min</strong></div>` : `<div class="record-row"><span>23 Oct · ${data.title}</span><strong>${data.value}</strong></div><div class="record-row"><span>22 Oct · Previous record</span><strong>${kind === "weight" ? "74.5 kg" : kind === "steps" ? "8,130" : "59 bpm"}</strong></div>`}</div></div><div class="card insight-card" style="margin-top:15px"><span class="insight-mark">i</span><p>${data.note}</p></div>${kind === "weight" ? `<button class="secondary-button full-width" style="margin-top:15px" data-action="add-weight">+ Add weight entry</button>` : ""}`, "health");
}

function renderConnections() {
  return shell(`${backbar("Connections & sources", "health")}<div class="card routine-card"><div class="row-between"><div><span class="tag">Connected</span><h3 style="margin:10px 0 4px">Apple Health</h3><p class="muted" style="margin:0">Apple Watch · Last refresh 18:20 today</p></div><span style="font-size:22px;color:var(--forest)">✓</span></div><div class="routine-meta"><span>Sleep available</span><span>Steps available</span><span>Resting HR available</span><span>Weight available</span></div>${button("Refresh connection", "refresh-connection", "secondary-button full-width")}</div>${sectionHeading("Preferred source", "", "")}<div class="card list-card"><span class="list-art">☾</span><div class="list-copy"><h3>Sleep</h3><p>Apple Health · Choose another source if added later</p></div><span class="arrow">›</span></div><div class="card list-card" style="margin-top:8px"><span class="list-art">◉</span><div class="list-copy"><h3>Weight</h3><p>Manual entries preferred</p></div><span class="arrow">›</span></div>${sectionHeading("Connection controls", "", "")}<div class="card settings-list"><div class="settings-row" data-action="refresh-connection" role="button" tabindex="0"><span class="setting-icon">↻</span><div><strong>Refresh now</strong><span>Ask the phone health store for new records</span></div><span class="arrow">›</span></div><div class="settings-row" data-action="disconnect" role="button" tabindex="0"><span class="setting-icon">×</span><div><strong>Disconnect</strong><span>Stops future imports; does not delete Apple Health records</span></div><span class="arrow">›</span></div></div>`, "health");
}

function renderSettings() {
  return shell(`${backbar("Settings", "today")}<div class="card settings-list"><div class="settings-group">Personalise</div><div class="settings-row" data-action="preferences" role="button" tabindex="0"><span class="setting-icon">⌘</span><div><strong>Preferences & reminders</strong><span>Goal, units, week start and notifications</span></div><span class="arrow">›</span></div><div class="settings-group">Data and connections</div><div class="settings-row" data-action="connections" role="button" tabindex="0"><span class="setting-icon">♡</span><div><strong>Connections</strong><span>Apple Health · Connected</span></div><span class="arrow">›</span></div><div class="settings-row" data-action="privacy" role="button" tabindex="0"><span class="setting-icon">${icon("lock")}</span><div><strong>Privacy & data</strong><span>Export, backup, restore and delete</span></div><span class="arrow">›</span></div><div class="settings-group">Support</div><div class="settings-row"><span class="setting-icon">?</span><div><strong>Help</strong><span>How Northstar handles missing data</span></div><span class="arrow">›</span></div><div class="settings-row"><span class="setting-icon">i</span><div><strong>About</strong><span>Prototype version 0.1 · Local-only demo</span></div></div></div><p class="muted" style="margin:18px 4px;line-height:1.5">No account or cloud-sync status is shown in this prototype. Workout data stays on this phone until a user chooses a backup flow.</p>`, "today");
}

function renderPrivacy() {
  return shell(`${backbar("Privacy & data", "settings")}<p class="muted" style="line-height:1.55">Northstar stores your workout records and any health records you choose to import. Disconnecting a source stops future imports; it does not delete records from Apple Health or Health Connect.</p><div class="stack" style="margin-top:18px"><div class="card list-card" data-action="export" role="button" tabindex="0"><span class="list-art">↥</span><div class="list-copy"><h3>Export records</h3><p>Choose workout, health or all Northstar records</p></div><span class="arrow">›</span></div><div class="card list-card" data-action="backup" role="button" tabindex="0"><span class="list-art">▣</span><div class="list-copy"><h3>Create backup</h3><p>Prepare a local backup file (simulated)</p></div><span class="arrow">›</span></div><div class="card list-card" data-action="restore" role="button" tabindex="0"><span class="list-art">↥</span><div class="list-copy"><h3>Restore backup</h3><p>Preview replacement before anything changes</p></div><span class="arrow">›</span></div><div class="card list-card" data-action="remove-imported" role="button" tabindex="0"><span class="list-art">×</span><div class="list-copy"><h3>Remove imported data</h3><p>Remove Northstar copies only</p></div><span class="arrow">›</span></div><div class="card list-card" data-action="delete-all" role="button" tabindex="0"><span class="list-art" style="color:var(--danger);background:var(--danger-soft)">!</span><div class="list-copy"><h3 style="color:var(--danger)">Delete all Northstar data</h3><p>Requires a separate confirmation</p></div><span class="arrow">›</span></div></div>${state.overlay ? renderOverlay() : ""}`, "today");
}

function renderOnboarding() {
  const step = state.onboardingStep;
  if (step === 0) return onboardingShell(`<div class="brand-mark"><span class="brand-dot"></span> Northstar</div><div class="onboard-spacer"></div><div class="onboard-illustration"><div class="orbit"></div><div class="paper-card"><strong>Full Body A</strong><div class="paper-line short"></div><div class="paper-line"></div><div class="paper-line short"></div><div class="paper-line"></div></div><div class="floating-pill">6 h 18 min sleep</div></div><h1>Your training. <em>The whole picture.</em></h1><p>Plan your sessions, remember what you lifted and see health context from the devices you already own.</p><div class="onboard-spacer"></div>${button("Get started", "onboard-next", "primary-button full-width")}<button class="quiet-button full-width" style="margin-top:10px" data-action="today">Explore the demo instead</button><p style="margin-top:15px;color:#97b59e;font-size:10px;text-align:center;max-width:none">No account needed to get started</p>`);
  if (step === 1) return onboardingShell(`${progressDots(0)}<p class="eyebrow" style="margin:0;color:#a8c7ad">Step 1 of 3</p><h1>What are you working towards?</h1><p>Northstar uses this to make your first routine feel relevant. You can change it later.</p><div class="choice-list">${["Build strength", "Build muscle", "General fitness"].map((item) => `<button class="choice ${state.onboardingGoal === item ? "selected" : ""}" data-action="goal-${item.toLowerCase().replaceAll(" ", "-")}"><span>${item}<small>${item === "Build strength" ? "Focus on progressive lifts" : item === "Build muscle" ? "Balanced volume and consistency" : "Build a steady movement habit"}</small></span><span class="check">✓</span></button>`).join("")}</div><div class="row-between" style="margin-top:auto"><button class="quiet-button" data-action="onboard-back">Back</button>${button("Continue", "onboard-next", "primary-button")}</div>`);
  if (step === 2) return onboardingShell(`${progressDots(1)}<p class="eyebrow" style="margin:0;color:#a8c7ad">Step 2 of 3</p><h1>When and where do you train?</h1><p>Pick a starting point. This is planning, not a commitment the app will enforce.</p><div class="choice-list">${["Gym", "Dumbbells at home", "Bodyweight"].map((item) => `<button class="choice ${state.onboardingEquipment === item ? "selected" : ""}" data-action="equipment-${item.toLowerCase().replaceAll(" ", "-")}"><span>${item}</span><span class="check">✓</span></button>`).join("")}</div><p style="margin:2px 0 10px;color:#bcd5c2;font-size:11px">Preferred training days</p><div class="checkin-row">${["Mon", "Wed", "Fri"].map((day) => `<button class="checkin-chip selected" data-action="noop">${day}</button>`).join("")}</div><div class="row-between" style="margin-top:auto"><button class="quiet-button" data-action="onboard-back">Back</button>${button("Continue", "onboard-next", "primary-button")}</div>`);
  if (step === 3) return onboardingShell(`${progressDots(2)}<p class="eyebrow" style="margin:0;color:#a8c7ad">Step 3 of 3</p><h1>Bring in your health data</h1><p>Connect a phone health store if you want sleep, steps, resting heart rate and imported workout summaries beside your training.</p><div class="platform-card"><strong>Apple Health</strong><p>Your phone's permission screen opens here. You choose which categories to share. This is a simulated handoff for the prototype.</p></div><div style="margin-top:auto">${button("Connect Apple Health", "onboard-connect", "primary-button full-width")}<button class="quiet-button full-width" style="margin-top:10px" data-action="onboard-skip">Skip for now</button></div>`);
  return onboardingShell(`${progressDots(2)}<p class="eyebrow" style="margin:0;color:#a8c7ad">Connection result</p><h1>A useful start.</h1><p>Here is the kind of result Northstar would show after the phone permission handoff.</p><div class="result-list"><div class="result-row"><i>✓</i> Sleep records available</div><div class="result-row"><i>✓</i> Steps available</div><div class="result-row"><i>✓</i> Resting heart rate available</div><div class="result-row missing"><i>—</i> No workout summary received yet</div></div><p style="color:#bcd5c2;font-size:11px">You can start training without connecting health data.</p><div style="margin-top:auto">${button("Continue to Today", "onboard-finish", "primary-button full-width")}</div>`);
}

function renderRail() {
  const journeys = [
    ["today", "Today overview"], ["train", "Plan a routine"], ["active-workout", "Active workout"], ["progress", "Review progress"], ["health", "Health context"], ["settings", "Settings & privacy"],
  ];
  return `<div class="rail-card"><h2>Playground controls</h2><p>Jump between the core product moments, or run the onboarding path from the beginning.</p><div class="rail-actions">${journeys.map(([action, label]) => `<button class="${(state.screen === action || (action === "active-workout" && state.screen === "activeWorkout")) ? "active" : ""}" data-action="${action}">${label}</button>`).join("")}<button data-action="onboarding">↗ Run onboarding</button><button data-action="reset-demo">↺ Reset demo</button></div><div class="rail-footer"><span>Prototype only</span><button class="toggle ${state.theme === "dark" ? "on" : ""}" data-action="toggle-theme"><span class="toggle-track"></span>${state.theme === "dark" ? "Dark" : "Light"}</button></div></div><div class="rail-card"><h3>What to notice</h3><div class="rail-highlight"><span>✦</span><span>The workout logger keeps previous numbers visible while today's set stays editable.</span></div><div class="rail-highlight"><span>☾</span><span>Health context is dated and sourced, never turned into a medical readiness score.</span></div></div>`;
}

function renderOverlay() {
  const overlay = state.overlay;
  if (!overlay) return "";
  if (overlay.type === "timer") return `<div class="modal-backdrop"><div class="sheet"><div class="sheet-handle"></div><h3>Rest timer</h3><p>Take the time you need. The timer is a prepared prototype state, not a live training requirement.</p><div class="timer-display">${formatTime(state.timerSeconds)}</div><div class="sheet-actions"><button class="quiet-button" data-action="timer-plus">+30 sec</button><button class="secondary-button" data-action="timer-skip">Skip rest</button><button class="primary-button" data-action="close-overlay">Close</button></div></div></div>`;
  if (overlay.type === "note") return `<div class="modal-backdrop"><div class="sheet"><div class="sheet-handle"></div><h3>Set notes and effort</h3><p>Optional context for this session. Nothing here changes your training plan.</p><div class="form-stack"><label class="field-label">How did the set feel?<select><option>Choose an option</option><option>Comfortable</option><option>Challenging</option><option>Near limit</option></select></label><label class="field-label">Note<textarea placeholder="e.g. Felt steady after a longer warm-up"></textarea></label></div><div class="sheet-actions" style="margin-top:16px"><button class="quiet-button" data-action="close-overlay">Cancel</button><button class="primary-button" data-action="close-overlay">Save note</button></div></div></div>`;
  if (overlay.type === "weight") return `<div class="modal-backdrop"><div class="sheet"><div class="sheet-handle"></div><h3>Add weight entry</h3><p>Manual records remain labelled as manual entries.</p><div class="form-stack"><label class="field-label">Weight<input value="74.2" type="number" /></label><label class="field-label">Unit<select><option>kg</option><option>lb</option></select></label><label class="field-label">Date<input value="2026-10-23" type="date" /></label></div><div class="sheet-actions" style="margin-top:16px"><button class="quiet-button" data-action="close-overlay">Cancel</button><button class="primary-button" data-action="close-overlay">Save entry</button></div></div></div>`;
  const destructive = overlay.type === "delete";
  return `<div class="modal-backdrop"><div class="sheet"><div class="sheet-handle"></div><h3>${destructive ? "Delete all Northstar data?" : overlay.title || "Prototype handoff"}</h3><p>${destructive ? "This removes workouts, plans and Northstar's imported copies from this prototype. It does not delete anything from Apple Health or Health Connect. This action is simulated." : overlay.body || "This is a prepared prototype state. No file or external record will actually change."}</p><div class="sheet-actions"><button class="quiet-button" data-action="close-overlay">Cancel</button><button class="${destructive ? "danger-button" : "primary-button"}" data-action="close-overlay">${destructive ? "Delete demo data" : "Continue"}</button></div></div></div>`;
}

function formatTime(seconds) {
  const minutes = Math.floor(seconds / 60).toString().padStart(2, "0");
  const remainder = (seconds % 60).toString().padStart(2, "0");
  return `${minutes}:${remainder}`;
}

let timerHandle;
function startTimerLoop() {
  clearInterval(timerHandle);
  timerHandle = setInterval(() => {
    if (!state.overlay || state.overlay.type !== "timer") return clearInterval(timerHandle);
    state.timerSeconds = state.timerSeconds > 0 ? state.timerSeconds - 1 : 90;
    const display = document.querySelector(".timer-display");
    if (display) display.textContent = formatTime(state.timerSeconds);
  }, 1000);
}

function bindActions() {
  document.querySelectorAll("[data-action]").forEach((element) => {
    element.addEventListener("click", () => handleAction(element.dataset.action, element));
    element.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        handleAction(element.dataset.action, element);
      }
    });
  });
}

function resetWorkout() {
  state.workout = { active: false, minimised: false, completedSets: 0, totalSets: 3, weight: [60, 60, 60], reps: [8, 8, 8], note: "" };
}

function handleAction(action, element) {
  if (action === "toggle-theme") { state.theme = state.theme === "light" ? "dark" : "light"; return render(); }
  if (action === "reset-demo") {
    state.screen = "today"; state.completedToday = false; state.energy = null; state.overlay = null; state.onboardingStep = 0; state.theme = "light"; resetWorkout(); return render();
  }
  if (action === "onboarding") { state.screen = "onboarding"; state.onboardingStep = 0; state.overlay = null; return render(); }
  if (action === "onboard-next") { state.onboardingStep = Math.min(3, state.onboardingStep + 1); return render(); }
  if (action === "onboard-back") { state.onboardingStep = Math.max(1, state.onboardingStep - 1); return render(); }
  if (action === "onboard-skip") { state.screen = "today"; state.onboardingStep = 0; return render(); }
  if (action === "onboard-connect") { state.onboardingStep = 4; return render(); }
  if (action === "onboard-finish") { state.screen = "today"; state.onboardingStep = 0; return render(); }
  if (action === "goal-build-strength") { state.onboardingGoal = "Build strength"; return render(); }
  if (action === "goal-build-muscle") { state.onboardingGoal = "Build muscle"; return render(); }
  if (action === "goal-general-fitness") { state.onboardingGoal = "General fitness"; return render(); }
  if (action.startsWith("equipment-")) { state.onboardingEquipment = action.replace("equipment-", "").replaceAll("-", " ").replace(/^./, (letter) => letter.toUpperCase()); return render(); }
  if (action.startsWith("energy-")) { state.energy = action.replace("energy-", "").replace(/^./, (letter) => letter.toUpperCase()); return render(); }
  if (action === "noop") return;
  if (action === "today") { state.screen = "today"; state.overlay = null; return render(); }
  if (action === "train") { state.screen = "train"; state.overlay = null; return render(); }
  if (action === "progress") { state.screen = "progress"; state.overlay = null; return render(); }
  if (action === "health") { state.screen = "health"; state.overlay = null; return render(); }
  if (action === "settings") { state.screen = "settings"; state.overlay = null; return render(); }
  if (action === "privacy") { state.screen = "privacy"; state.overlay = null; return render(); }
  if (action === "connections") { state.screen = "connections"; state.overlay = null; return render(); }
  if (action === "templates") { state.screen = "templates"; state.overlay = null; return render(); }
  if (action === "template-full-body" || action === "template-upper-lower") { state.screen = "routine"; state.overlay = null; return render(); }
  if (action === "routine") { state.screen = "routine"; state.overlay = null; return render(); }
  if (action === "builder") { state.screen = "builder"; state.overlay = null; return render(); }
  if (action === "schedule") { state.screen = "schedule"; state.overlay = null; return render(); }
  if (action === "exercise-picker" || action === "exercise-detail") { state.overlay = { type: "notice", title: "Exercise selection", body: "The full exercise picker and custom exercise branch are represented as a prepared prototype handoff in this first slice." }; return render(); }
  if (action === "cardio") { state.overlay = { type: "notice", title: "Log cardio", body: "Walk, Run, Cycle and Other would open a simple manual entry sheet here. The data remains simulated in this prototype." }; return render(); }
  if (action === "start-workout") { state.screen = "activeWorkout"; state.workout.active = true; state.workout.minimised = false; state.overlay = null; return render(); }
  if (action === "active-workout" || action === "resume-workout") { state.screen = "activeWorkout"; state.workout.active = true; state.workout.minimised = false; state.overlay = null; return render(); }
  if (action === "minimise-workout") { state.screen = "today"; state.workout.active = true; state.workout.minimised = true; state.overlay = null; return render(); }
  if (action === "complete-set") {
    const setIndex = Number(element?.dataset.set || 0);
    if (setIndex === state.workout.completedSets) { state.workout.completedSets = Math.min(state.workout.totalSets, state.workout.completedSets + 1); state.timerSeconds = 90; state.overlay = { type: "timer" }; return render(); }
    return;
  }
  if (action === "add-set") { state.workout.totalSets += 1; state.workout.weight.push(60); state.workout.reps.push(8); state.overlay = { type: "notice", title: "Set added", body: "A fourth set is now available in the editable workout state." }; return render(); }
  if (action === "workout-note") { state.overlay = { type: "note" }; return render(); }
  if (action === "finish-review") { state.screen = "finishReview"; state.overlay = null; return render(); }
  if (action === "complete") { state.screen = "complete"; state.completedToday = true; state.workout.active = false; state.workout.minimised = false; state.overlay = null; return render(); }
  if (action === "session-detail") { state.screen = "sessionDetail"; state.overlay = null; return render(); }
  if (action === "progress-detail") { state.screen = "progressDetail"; state.overlay = null; return render(); }
  if (action === "weekly-review") { state.screen = "weeklyReview"; state.overlay = null; return render(); }
  if (action === "sleep-detail" || action === "steps-detail" || action === "heart-detail" || action === "weight-detail") { state.healthDetail = action.replace("-detail", ""); state.screen = "healthDetail"; state.overlay = null; return render(); }
  if (action === "add-weight") { state.overlay = { type: "weight" }; return render(); }
  if (action === "refresh-connection") { state.overlay = { type: "notice", title: "Refresh prepared", body: "A real build would ask the phone health store for new records here. This prototype keeps the last successful sync visible." }; return render(); }
  if (action === "disconnect") { state.overlay = { type: "notice", title: "Disconnect connection?", body: "Disconnecting stops future imports. Previously imported Northstar copies stay until you remove them separately." }; return render(); }
  if (action === "preferences") { state.overlay = { type: "notice", title: "Preferences", body: "Goal, units, week start, appearance and workout reminders would be edited in this screen." }; return render(); }
  if (action === "export") { state.overlay = { type: "notice", title: "Export records", body: "Choose workout, health or all Northstar records and hand off to the system share/file picker. No file is created in this prototype." }; return render(); }
  if (action === "backup") { state.overlay = { type: "notice", title: "Create backup", body: "A local backup file would be prepared here. Nothing is written in this prototype." }; return render(); }
  if (action === "restore") { state.overlay = { type: "notice", title: "Restore backup", body: "The real flow would preview that existing local data will be replaced and offer Back up first." }; return render(); }
  if (action === "remove-imported") { state.overlay = { type: "notice", title: "Remove imported data", body: "This removes Northstar's imported copies only. It does not delete records from Apple Health or Health Connect." }; return render(); }
  if (action === "delete-all") { state.overlay = { type: "delete" }; return render(); }
  if (action === "timer-plus") { state.timerSeconds += 30; return render(); }
  if (action === "timer-skip" || action === "close-overlay") { state.overlay = null; clearInterval(timerHandle); return render(); }
  if (action === "back") { state.overlay = null; state.screen = state.screen === "healthDetail" ? "health" : state.screen === "progressDetail" || state.screen === "weeklyReview" ? "progress" : state.screen === "routine" || state.screen === "builder" || state.screen === "schedule" || state.screen === "templates" ? "train" : state.screen === "settings" || state.screen === "privacy" || state.screen === "connections" ? "today" : "today"; return render(); }
}

render();
