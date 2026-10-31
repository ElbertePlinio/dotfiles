---
name: tiktok
description: Use when the user asks to scroll, watch, or browse TikTok on their phone, such as the For You feed on a topic, a search, or a hashtag, with likes and comments.
---

Run TikTok sessions on the user's Android phone with `tt` in `~/Projects/Personal/tiktok-scroll`. The script runs on this computer and drives the phone over ADB with uiautomator2. Claude Haiku 5.5 judges compressed frames. Never drive TikTok by hand with screenshots; that path is slow.

1. Check the phone with `adb devices -l`. It must show one device as `device`, unlocked. If it is missing or locked, ask the user to connect it by USB or wireless debugging and unlock it.
2. Run from the project directory, with a timeout above the session length:
   - For You: `uv run tt fyp -m 5`. To favor a topic: `uv run tt fyp "jogos" -m 5`.
   - Search or hashtag: `uv run tt search "#receitas" -m 5`.
   - Add `--dry-run` to do everything except likes and saves.
   - To inspect exposure, run `uv run tt exposure`.
3. The command prints a JSON summary when it ends. Per-video details are in `runs/<stamp>-<mode>/log.jsonl`, with one small WebP frame per video beside it.
4. Report videos watched, likes, comment likes, saves, copied links, model cost, and `stopped_by`. Mention notable videos from the log notes.

The script turns on Do Not Disturb (alarms only), raises the screen timeout only when the session needs more time than the current setting, disables third-party accessibility services, and restores all three at the end. Taste lives in `taste.yaml` (`gosta`, `evita`, `limites`); edit it when the user describes their taste. If `stopped_by` names a missing button or screen, run `uv run tt calibrate` and compare `runs/calibrate-*/tree.xml` with the selectors in `tt/session.py`. TikTok updates can rename them.

The session hides what it can: it prefers wireless debugging (USB debugging left off, with a warning if it is on), installs no automation APK (`u2.jar` runs as a shell process), and clears third-party accessibility services. It varies watch time, swipe paths, action timing, breaks, and an occasional app switch, and keeps likes, saves, and comment likes at human rates.

It cannot hide wireless debugging, developer options, or the synthetic touch events that drive the phone. There is no zero-detection mode on a stock phone; say that plainly instead of promising one. Rooting would change the device layer but breaks banking apps and the warranty. A separate account or a spare phone is the reliable protection.

Ask before sessions longer than 30 minutes or more than a few per day. Automation breaks TikTok's terms and can get the account limited. The script never follows, comments, reposts, or messages; keep it that way.
