# SystemCleaner

A safe, one-folder PC cleaner for **Windows** and **WSL/Linux**. It finds junk files that eat
your disk space and slow your machine down — temp files, browser caches, package-manager
caches, trashed files and old logs — shows you a report first, and only deletes what you approve.

Everything is safe-mode: it only touches well-known junk locations, never deletes anything on
its own, and keeps a log of everything it does.

## What's in this project

| File | What it does |
|------|--------------|
| `SystemCleaner.bat`   | **Double-click this on Windows** — a simple menu, no typing |
| `clean-windows.ps1` | Cleaner for your **Windows** PC (PowerShell) |
| `clean-linux.sh`    | Cleaner for **WSL/Linux** (bash) |
| `SystemCleaner-windows.log` | Auto-created log, created on first Windows clean |
| `SystemCleaner-linux.log`   | Auto-created log, created on first Linux clean |

Both tools do the same job:

1. **Scan** — shows a table of junk categories with sizes. Nothing is deleted at this point.
2. **Clean** — shows the report, then removes only what you pick (or everything safe with a
   single command).
3. **Dry-run** — preview exactly what would be removed, without removing anything.
4. **Schedule** — optional daily auto-run at 09:00 (Windows Task Scheduler or Linux cron),
   with a matching command to turn it off again.

## Windows — how to use it

**Easiest way (no commands at all):** double-click `SystemCleaner.bat` in this folder. A menu
opens — just type a number and press Enter:

```
1 = Scan only (see junk, delete nothing)
2 = Clean - pick what to clean
3 = Clean everything safe
4 = Preview what a full clean would remove
5 = Run every day at 09:00 automatically
6 = Stop the automatic run
7 = View the cleaner log
0 = Exit
```

Prefer typing commands instead? Open **PowerShell** in this folder:

```
cd <your path>\SystemCleaner
```

Then run one of these:

| Command | What it does |
|---------|--------------|
| `.\clean-windows.ps1` | Show the junk report only |
| `.\clean-windows.ps1 -Clean` | Ask which items to clean |
| `.\clean-windows.ps1 -Clean -All` | Clean everything safe |
| `.\clean-windows.ps1 -Clean -All -DryRun` | Preview without deleting |
| `.\clean-windows.ps1 -Schedule` | Auto-run every day at 09:00 |
| `.\clean-windows.ps1 -RemoveSchedule` | Stop the auto-run |

First time only: if PowerShell refuses to run scripts, allow it for this folder with
`Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` before running.

**For the full clean, run as Administrator:** right-click PowerShell → *Run as administrator*,
then use `-Clean -All`. A few categories (Windows temp files, Windows Update cache) need
admin rights; without them those are listed as skipped, and everything else is still cleaned.

## WSL/Linux — how to use it

From this folder (or anywhere):

```
./clean-linux.sh scan          # junk report, nothing deleted
./clean-linux.sh clean all     # clean everything safe
./clean-linux.sh clean apt cache   # clean only the listed categories
./clean-linux.sh dry-run       # preview without deleting
./clean-linux.sh schedule      # auto-run every day at 09:00
./clean-linux.sh unschedule    # stop the auto-run
./clean-linux.sh log           # see the cleaner log
./clean-linux.sh help          # all commands
```

### What it cleans

- **apt package cache** — downloaded `.deb` installers that are already installed
- **user cache (`~/.cache`)** — app caches that rebuild themselves
- **package-manager caches** — pip, npm, bun, cargo, go caches (redownloaded only if needed)
- **trash** — files you deleted through the file manager
- **old temp files** — your own files in `/tmp` older than 7 days
- **old system journals** — reported for info; reduce them with (needs sudo):
  `sudo journalctl --vacuum-size=64M`

### One important WSL note

Cleaning files inside WSL frees space *inside WSL*, but that space is often **not returned to
Windows automatically** (WSL grows and shrinks its disk image lazily). To see real disk-space
gain on the Windows side later, shut WSL down and compact the virtual disk:

```
wsl.exe --shutdown
```

Then, in a Windows PowerShell window (administrator), compact the image (use the path shown by
`wsl --manage <distro> --set-sparse true` or locate the `ext4.vhdx` under
`%LOCALAPPDATA%\Packages\*Ubuntu*\LocalState`) with:

```
Optimize-VHD -Path <path-to-your\ext4.vhdx> -Mode Full
```

## Safety

- Nothing is deleted in `scan`, `dry-run`, or `help` mode.
- `clean` always shows the report first; the "everything safe" flag only touches the listed
  junk categories — never documents, downloads, pictures or installed programs.
- Browser cleaning removes cache files only (no bookmarks, passwords or logins).
- Every clean writes to a log in this folder, so you can see exactly what was removed.

## Getting space back the easy way

A 100–500 MB clean with this tool is normal on a fresh setup. The biggest, fastest day-to-day
wins are the big caches (browsers + package managers) plus emptying the recycle bin/trash.
Run `schedule` once on each machine and forget about it — it cleans itself while you sleep.

## Version history

**v1.1 — 2026-09-20 — Double-click menu**
- Added `SystemCleaner.bat`: a double-click Windows menu (scan / clean / preview /
  schedule / unschedule / view log). No commands to type, just pick a number.
- Improved Windows scheduling to use Task Scheduler reliably.

**v1.0 — 2026-09-20 — First release**
- Windows cleaner (`clean-windows.ps1`): scan, clean, dry-run, daily schedule.
- WSL/Linux cleaner (`clean-linux.sh`): apt cache, user cache, package-manager caches,
  trash, old temp files, journals; cron daily schedule.
- Professional README, safety-first design, auto-generated logs.

---

*Built for Salman — simple, safe, and it logs everything.*