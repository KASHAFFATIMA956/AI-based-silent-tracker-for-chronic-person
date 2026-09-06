# Seeded Accounts — Quick Reference

Every value below is pulled directly from `Backend/seed.py` (the single source
of truth for seed data — see [[schema]] and [[conventions]]), not from memory
or other project docs.

**This reflects the same data that was seeded into the real Railway
production database** via `railway connect Postgres --tunnel-only` +
`python seed.py` on 2026-09-02 — safe to use for live demo testing against
the deployed backend (`https://roznoor-production.up.railway.app`).

**For hackathon judges**: any login identifier below + the shared password
works directly on the live web app at `https://roznoor.up.railway.app` (or
the Android APK in `Mobile App APK file/`) — no signup needed. These are
fictional demo accounts, safe to share openly.

**Login**: `POST /auth/login` with `phone_or_email` (the "Login identifier"
column below) + the shared password. All ten seeded users share one demo
password, hashed via `app.core.security.hash_password` — never a
per-user password (`seed.py`'s `SEED_PASSWORD`):

```
RozNoor@123
```

---

## Patients

Risk level is each patient's **most recent** seeded entry (`days_ago=0`) —
the one a fresh login/timeline will show first. Diagnosis/MR number/assigned
doctor included for cross-reference against the Doctors table below.

| Name | Login identifier | Password | Risk level | Diagnosis | MR number | Assigned doctor |
|---|---|---|---|---|---|---|
| Ghulam Rasool | `ghulam.rasool@roznoor.care` | `RozNoor@123` | 🔴 **Red** — chest pain at rest | Heart failure | MR 40-1188 | Dr. Ayesha Farooq |
| Zubaida Bibi | `zubaida.b@roznoor.care` | `RozNoor@123` | 🟠 **Orange** — weight/sleep/energy trend | Heart failure, post-discharge | MR 40-2291 | Dr. Ayesha Farooq |
| Naseem Akhtar | `naseem.a@roznoor.care` | `RozNoor@123` | 🟠 **Orange** — missed doses + rising fatigue | Post-surgical | MR 40-2010 | Dr. Hamza Iqbal |
| Bashir Ahmed | `bashir.a@roznoor.care` | `RozNoor@123` | 🟡 **Yellow** — sleep below band, 2 nights | Heart failure | MR 40-1974 | Dr. Ayesha Farooq |
| Farida Yousuf | `farida.y@roznoor.care` | `RozNoor@123` | 🟡 **Yellow** — appetite down | Post-surgical | MR 40-2255 | Dr. Hamza Iqbal |
| Mukhtar Ali | `mukhtar.a@roznoor.care` | `RozNoor@123` | 🟢 **Green** — stable | Heart failure | MR 40-1902 | Dr. Ayesha Farooq |

**For a demo needing a Red alert**: log in as **Ghulam Rasool**. For a
mixed/realistic doctor roster (multiple risk levels at once), log in as
either doctor below.

---

## Doctors

| Name | Login identifier | Password | Assigned patients |
|---|---|---|---|
| Dr. Ayesha Farooq | `a.farooq@civilhosp.pk` | `RozNoor@123` | Ghulam Rasool, Zubaida Bibi, Bashir Ahmed, Mukhtar Ali (4 patients) |
| Dr. Hamza Iqbal | `h.iqbal@civilhosp.pk` | `RozNoor@123` | Naseem Akhtar, Farida Yousuf (2 patients) |

---

## Admin

| Name | Login identifier | Password |
|---|---|---|
| Sadia Kamran | `s.kamran@civilhosp.pk` | `RozNoor@123` |

---

## Attendant

| Name | Login identifier | Password | Linked patient |
|---|---|---|---|
| Imran Zubair | `imran.z@roznoor.care` | `RozNoor@123` | Zubaida Bibi |
