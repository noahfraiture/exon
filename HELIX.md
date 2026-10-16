# Native Helix mode

This fork adds an opt-in selection-first editing mode to Neovim 0.12.6.
Enable it in `init.lua`:

```lua
vim.o.helix = true
```

The mode, selection collection, position tracking, edit transactions and undo
metadata live in Neovim core. Bundled Lua implements the commands. No editing
plugin or normal-mode keymap translation is required. `mim`, `mi(`, `ma/`, `x`,
and multiple selections are available with that one setting.

This is an initial native implementation, not complete Helix parity. See the
compatibility boundary below before adopting it as your only editor.

## Build and try without changing your configuration

Prebuilt Linux x86-64 (Ubuntu 24.04) and macOS Apple Silicon bundles are available
in the [preview release](https://github.com/noahfraiture/neovim/releases/tag/helix-preview-0.1.0).
Extract the matching archive and run its `bin/nvim` with the included configuration:

```sh
./neovim-helix-Linux-X64/bin/nvim -i NONE \
  -u ./neovim-helix-Linux-X64/share/neovim-helix/init.lua
# On macOS, replace neovim-helix-Linux-X64 with neovim-helix-macOS-ARM64.
```

Keep the bundle's `bin` and `share` directories together. Each archive includes
a SHA-256 checksum and a smoke test. See the [verification record](contrib/helix/TESTING.md)
for tested platforms, results and the compatibility boundary.

Use the `helix` branch, not the upstream `master` branch:

```sh
git clone --branch helix https://github.com/noahfraiture/neovim.git neovim-helix
cd neovim-helix
make CMAKE_BUILD_TYPE=RelWithDebInfo
VIMRUNTIME="$PWD/runtime" ./build/bin/nvim -u contrib/helix/init.lua
```

Neovim's [build prerequisites](BUILD.md#build-prerequisites) apply. Building
downloads dependencies into `.deps` and puts the executable in `build/bin`.
The example configuration installs no plugins, changes no configuration files,
and saves files only when you request it.

To use only the mode with an otherwise empty configuration:

```sh
VIMRUNTIME="$PWD/runtime" ./build/bin/nvim -u NONE --cmd 'set helix'
```

Install the binary and matching runtime together into a separate prefix:

```sh
cmake --install build --prefix "$HOME/.local/opt/neovim-helix"
"$HOME/.local/opt/neovim-helix/bin/nvim"
```

Add `vim.o.helix = true` to your configuration when ready. `vim.pack` continues
to install ordinary plugins; it cannot install these core changes into a stock
Neovim executable. The old `require('helix').setup()` plugin is not needed.
Remove that setup when migrating so two editing backends do not run together.

## Small manual test

Open a scratch buffer containing:

```text
outer([hello])
let r = /abc/;
one two three
one
two
```

* Place the cursor inside `hello`. Type `mim`: `hello` should be selected.
  Type `cworld<Esc>` to replace it. `u` restores `hello` and its selection;
  `U` redoes the change.
* Place the cursor inside `abc`. Type `ma/`: `/abc/` should be selected.
* At the beginning of `one two three`, press `w` repeatedly: the selection
  advances through all three words. It does not get stuck on a space.
* At the `o` in the last standalone `one`, type `C`: another selection appears
  on the next line. `miwcX<Esc>` changes both words. `u` restores both words
  and both selections. `,` keeps only the primary selection.
* `:set nohelix` returns to ordinary Vim editing. `:set helix` enables it again.

The `contrib/helix/init.lua` configuration adds buffer navigation, save/quit,
file browsing and LSP actions. Its buffer navigation and textobjects are covered
by the native functional tests. It enables built-in LSP completion when an
attached language server supports completion; it does not install servers.

## Commands included

| Keys | Action |
| --- | --- |
| `h j k l`, arrows | Move the selection's head |
| `w b e`, `W B E` | Word and WORD motions; counts are supported |
| `gg ge gh gl` | Document/line boundaries |
| `f F t T` + character | Find/select to a character |
| `v`, `Esc` | Toggle selection extension / return to normal selection behavior |
| `x`, `%` | Select lines / the document |
| `mim`, `mam` | Inside / around the closest enclosing surround |
| `mi(`, `ma[`, `mi"`, `ma/`, etc. | Inside / around a specific delimiter |
| `miw`, `miW`, `mip` | Word, WORD, paragraph objects |
| `ms` + delimiter | Surround selections |
| `C`, `Alt-C` | Add a selection on the next / previous line |
| `,`, `Alt-,` | Keep the primary / remove the primary selection |
| `(`, `)` | Rotate the primary selection |
| `;`, `Alt-;` | Collapse selections to heads / reverse direction |
| `s`, `S` | Select regex matches / split selections by regex |
| `/`, `?`, `n`, `N`, `*` | Search forward/backward, repeat, search selection |
| `i a c`, `I A o O` | Insert, append, change, line insertion |
| `d y p P R r` | Delete, yank, paste, replace selections/characters |
| `"` + register | Choose a named register, including clipboard registers |
| `u`, `U` | Native undo / redo, including session-local selection metadata |
| `~`, backtick, `Alt-backtick` | Case changes |
| `:`, `Ctrl-W` | Native command line / window commands |

Selections use Unicode grapheme boundaries, including combining characters and
ZWJ emoji. Overlapping selections and identical insertion gaps merge. Adjacent
selections remain distinct until an edit brings them to the same position.

Textobjects are lexical delimiter/word/paragraph objects. They do not yet use
tree-sitter to distinguish syntax nodes or delimiters inside comments/strings.
Regular expressions currently use Neovim's regex syntax.

## Configuration and plugins

`h` is the new mapping namespace. Existing `n` mappings remain Vim mappings.
Insert mode uses the existing `i` namespace and real Insert-mode events.

```lua
vim.o.helix = true
vim.keymap.set('h', '<Space>w', '<Cmd>write<CR>')
vim.keymap.set('h', 'Q', function()
  vim.helix.textobject('m') -- Same object used by mim.
end)
vim.keymap.set('h', 'gd', vim.lsp.buf.definition)
```

Disable the mode for an otherwise ordinary buffer with `vim.b.helix = false`.
Special, readonly and unmodifiable buffers use ordinary Vim behavior. This lets
pickers, file browsers and terminals retain their existing input modes.

An explicit `nvim_win_set_cursor()`, `cursor()`, `setpos('.')` or `:normal`
command is a primary-cursor operation and collapses the selection collection.
Buffer edits instead move the existing selection endpoints and preserve other
windows' selection state. Plugins that want to operate on all selections should
use the selection APIs rather than replay a primary-cursor edit.

The example uses built-in completion and snippets. Completion is deliberately a
single-context operation: starting native completion keeps only the primary
cursor. Built-in snippet placeholders use native Vim Select mode and return to
Helix editing afterward. Multicursor typing, backspace, delete, arrows, paste,
tabs, basic autoindent and insert mappings are supported. Context-sensitive
multicursor completion/snippet groups and full indent-expression behavior are
not implemented. External completion/snippet plugins need their own workflow
tests or adapters; loading successfully is not a compatibility certification.

Other current boundaries include macro/dot-repeat parity, full Helix command
coverage, mouse selection parity and syntax-aware textobjects. Persistent undo
files retain Neovim's existing format: text undo survives restart; the extra
selection snapshots are session-local. The command layer currently uses a
temporary document snapshot, so very large files need further performance work.

## Selection APIs

```lua
local state = vim.api.nvim_helix_get_state(0)
-- state.selections: { {start_row, start_col, end_row, end_col, backward}, ... }
-- state.primary is one-based; rows and byte columns are zero-based.
-- Ranges are half-open, ordered and non-overlapping.

vim.api.nvim_helix_set_selections(0, {
  {0, 0, 0, 3, false},
  {1, 0, 1, 3, false},
}, 1, false)

vim.api.nvim_helix_apply_edits({
  {0, 0, 0, 3, {'replacement'}},
  {1, 0, 1, 3, {'replacement'}},
}, false)
```

Edit coordinates refer to the document before any edits. Core validates the
request before mutation and applies edits from last to first in one undo group.
`join=true` joins an active insert transaction. Callers can then set resulting
selections explicitly. The APIs are fork extensions at experimental API level
15; upstream APIs through level 14 retain their existing contracts.

Bundled helpers: `vim.helix.textobject()`, `select()`, `search()`, `format()`,
`get_state()` and `statusline()`. See `:help helix-mode`.

## Automated tests and rebasing

```sh
TEST_FILE=test/functional/editor/helix_spec.lua make functionaltest
TEST_FILE=test/functional/editor make functionaltest
TEST_FILE=test/functional/api make functionaltest
TEST_FILE=test/functional/lua/snippet_spec.lua make functionaltest
TEST_FILE=test/functional/plugin/lsp/completion_spec.lua make functionaltest
```

The functional tests drive real Neovim input and UI state; they do not substitute
a fake Neovim host. The dedicated workflow builds the fork and runs these checks.
See [maintenance notes](contrib/helix/MAINTENANCE.md) for the upstream base,
integration points and rebase procedure.
