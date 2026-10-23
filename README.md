# Northstar Health prototype

This is a dependency-free, clickable prototype for the Northstar Health product brief. It is intentionally a prototype rather than a working health app: device permissions, health sync, authentication, timers, backups and file exports are represented with prepared states only.

## Run locally

From the project root:

```bash
python3 -m http.server 4173
```

Open [http://localhost:4173](http://localhost:4173).

## Prototype journeys

- **Today → Active Workout:** Start a Full Body A session, complete squat sets, open the rest timer, minimise, resume, finish and save.
- **Train → Templates:** Browse the reviewed template collection and open a routine preview.
- **Progress:** Open the exercise trend and weekly review.
- **Health:** Inspect sleep, steps, resting heart rate, weight and connection/source states.
- **Onboarding:** Use the playground rail’s “Run onboarding” action to walk through goals, schedule and the simulated Apple Health handoff.
- **Settings & privacy:** Explore export, backup, restore, imported-data removal and destructive confirmation states.
- **Theme:** Toggle the light/dark treatment from the playground rail.

## Product boundaries represented in the demo

- Fictional Alex data is fixed to Friday, 23 October 2026.
- Health metrics show a source and date, and missing records are not rendered as zeroes.
- There is no readiness score, medical advice, AI coach, account, social layer or live wearable connection.
- The prototype is responsive: the desktop view includes a playground rail, while narrow screens focus on the mobile frame.
