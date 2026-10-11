---
name: zen-browser
description: Use when the user asks you to do something in their own Zen browser, such as a logged-in dashboard, download or form, on their Hyprland desktop.
---

Drive the user's real, logged-in Zen window on Hyprland. Do not use Playwright, a fresh profile, or Pickforge's desktop lab; those lack the user's sessions. Work only in pages the user named or the task needs.

1. Find Zen with `hyprctl clients -j | jq '.[] | select(.class=="zen") | {address, at, size, workspace: .workspace.id}'`.
2. Focus it: `hyprctl dispatch 'hl.dsp.focus({workspace = N})'`, then `hyprctl dispatch 'hl.dsp.focus({window = "address:0x..."})'`. Older Hyprland uses `hyprctl dispatch workspace N` and `focuswindow address:0x...`.
3. Before every input, check `[ "$(hyprctl activewindow -j | jq -r .class)" = zen ] || exit 1`. Never type into another window.
4. Navigate with `wtype -M ctrl t -m ctrl`, then `wtype '<url>'` and `wtype -k Return`. Wait a few seconds for the page.
5. Look with `grim -g "X,Y WxH" -s 0.5 <file>.png`, using the window's `at` and `size`. Read the image before acting.
6. Read and act through the DevTools console. Write the JavaScript to a file, run `wl-copy < file.js`, open the console with `wtype -M ctrl -M shift k -m shift -m ctrl`, paste with `wtype -M ctrl v -m ctrl`, and press `wtype -k Return`. Use `copy(JSON.stringify(...))` in the page and `wl-paste` to bring results back.
7. Prefer clicking by visible text, such as `[...document.querySelectorAll('button')].find(b => b.innerText.trim() === 'Create').click()`. For React inputs, set values with the native value setter and dispatch an `input` event. Fall back to real `wtype` keys when a widget ignores synthetic events: focus the element from the console, close DevTools with `wtype -k F12` so focus returns to the page, then type and press Return. Don't use Ctrl+A on the page; it selects the page, not the field.
8. Screenshot after each consequential step to confirm the result.

Stop and hand over for passwords, 2FA, payment, CAPTCHA, or a password-manager prompt. Never type or read the user's credentials. When a page shows a secret, move it straight into its store, such as Secret Manager, without printing it. Then clear it with `wl-copy --clear` and remove any page variable that held it. Ask before purchases, deletions, publishing, or account changes the user did not request. Downloads land in `~/Downloads`; move them to the task's folder and report the paths.
