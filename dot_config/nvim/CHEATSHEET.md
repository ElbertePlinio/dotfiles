# Neovim Cheatsheet

> `<leader>` is `Space` | Try `<leader>sk` to fuzzy-search all keymaps

## Navigation

| Key | Action |
|---|---|
| `h` `j` `k` `l` | Move left/down/up/right |
| `w` `b` | Next/previous word |
| `0` `^` `$` | Start / first non-blank / end of line |
| `gg` `G` | Top / bottom of file |
| `<C-d>` `<C-u>` | Half-page down/up |
| `%` | Jump to matching bracket |

## Editor

| Key | Action |
|---|---|
| `<leader>w` | Save |
| `<leader>q` | Quit |
| `<leader>c` | Close buffer |
| `<leader>bd` | Delete buffer |
| `u` `<C-r>` | Undo / redo |
| `<leader>fn` | New file (neo-tree) |
| `<leader>e` | Toggle file explorer (neo-tree) |
| `<leader>E` | Explorer at current file |
| `<leader>fE` | Toggle neo-tree float |

## Search & Replace

| Key | Action |
|---|---|
| `<leader><space>` | Find files (telescope) |
| `<leader>/` | Grep project |
| `<leader>sg` | Grep in cwd |
| `<leader>sb` | Search buffers |
| `<leader>sh` | Search help tags |
| `<leader>sk` | Search keymaps |
| `<leader>sr` | Search & replace (grug-far) |
| `*` `#` | Search word under cursor forward/backward |

## LSP / Code Intelligence

| Key | Action |
|---|---|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gr` | Go to references |
| `gi` | Go to implementation |
| `K` | Hover docs |
| `<leader>ca` | Code actions |
| `<leader>rn` | Rename symbol |
| `<leader>cr` | Rename file (LSP) |
| `<leader>cf` | Format buffer |
| `[d` `]d` | Prev/next diagnostic |
| `<leader>xx` | Toggle trouble (diagnostics list) |

## Flutter (`<leader>f`)

| Key | Action |
|---|---|
| `<F5>` | Run / Debug |
| `<S-F5>` | Stop |
| `<F6>` | Hot Reload |
| `<S-F6>` | Hot Restart |
| `<leader>fd` | Select device |
| `<leader>fe` | Emulators |
| `<leader>fl` | Toggle logs |
| `<leader>ft` | DevTools start |
| `<leader>fT` | Open DevTools |
| `<leader>fi` | Inspect widget |
| `<leader>fo` | Outline toggle |

## Debug (DAP)

| Key | Action |
|---|---|
| `<leader>du` | Toggle debug UI |
| `<leader>dc` | Continue |
| `<leader>do` | Step over |
| `<leader>di` | Step into |
| `<leader>dO` | Step out |

## Git

| Key | Action |
|---|---|
| `<leader>gg` | Lazygit |
| `<leader>gb` | Git branches |
| `<leader>gc` | Git commits (telescope) |
| `<leader>gs` | Git status |
| `]c` `[c` | Next/prev hunk |
| `<leader>hs` | Stage hunk |
| `<leader>hr` | Reset hunk |
| `<leader>hp` | Preview hunk |
| `<leader>hb` | Blame line |

## AI

| Key | Action |
|---|---|
| `<leader>aa` | Toggle Copilot |
| `<leader>ac` | Copilot Chat open |
| `<leader>aC` | Copilot Chat quick |
| `<leader>cc` | Claude Code open |

## Window Management

| Key | Action |
|---|---|
| `<C-h/j/k/l>` | Move to left/down/up/right window |
| `<leader>sv` | Split vertical |
| `<leader>sh` | Split horizontal |
| `<leader>se` | Make splits equal |
| `<leader>sx` | Close split |
| `<leader>wm` | Maximize toggle |
| `<Tab>` | Next buffer |
| `<S-Tab>` | Previous buffer |

## Essentials

| Key | Action |
|---|---|
| `i` | Enter insert mode |
| `Esc` / `<C-c>` | Back to normal mode |
| `v` | Visual mode (select text) |
| `V` | Visual line mode |
| `<C-v>` | Visual block mode |
| `y` | Yank (copy) |
| `p` | Paste after cursor |
| `dd` | Delete line |
| `ciw` | Change inner word |
| `<leader>L` | Lazy (plugin manager) |
| `<leader>uC` | Toggle colorscheme picker |
| `:q!` | Force quit |
| `:wq` | Save and quit |
