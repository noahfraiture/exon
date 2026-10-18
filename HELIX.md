# Exon native Helix mode

Exon adds an opt-in selection-first editing mode to Neovim 0.13 development.
Enable it in `init.lua`:

```lua
vim.o.helix = true
```

For optional command configuration, use `vim.helix.setup()` instead. Calling it
without options enables all defaults; no per-delimiter configuration is needed.
The upstream base is pinned in [MAINTENANCE.md](contrib/helix/MAINTENANCE.md).
Insertion, indentation and completion reuse Neovim 0.13's native machinery.

The mode, selection collection, position tracking, edit transactions and undo
metadata live in Neovim core. Bundled Lua implements the commands. No editing
plugin or normal-mode keymap translation is required. `mim`, `mi(`, `ma/`, `x`,
and multiple selections are available with that one setting.

This is an initial native implementation, not complete Helix parity. See the
compatibility boundary below before adopting it as your only editor.

## Build and try without changing your configuration

With Nix, build or try the fork directly:

```sh
nix build github:noahfraiture/exon
./result/bin/exon -u NONE --cmd 'set helix'
# Or run without creating ./result:
nix run github:noahfraiture/exon -- -u NONE --cmd 'set helix'
```

The flake exports `packages.<system>.default` and `exon`, plus
`overlays.default`. See [Nix installation](contrib/helix/NIX.md) for flake-input,
NixOS and Home Manager examples. Nix builds the fork from source with its
matching runtime; Helix remains opt-in through `vim.helix.setup()` or the boolean.
Launch with `exon` or its short name `ex`; `nvim` remains a compatibility name.
All three read your existing Neovim configuration. The names are included in
new source installs and bundles; the older preview archives below contain `nvim`.

Prebuilt Linux x86-64 (Ubuntu 24.04) and macOS Apple Silicon bundles are available
in the [preview release](https://github.com/noahfraiture/exon/releases/tag/helix-preview-0.1.3).
Extract the matching archive and run its `bin/nvim` with the included configuration:

```sh
./neovim-helix-Linux-X64/bin/nvim -i NONE \
  -u ./neovim-helix-Linux-X64/share/neovim-helix/init.lua
# On macOS, replace neovim-helix-Linux-X64 with neovim-helix-macOS-ARM64.
```

Keep the bundle's `bin` and `share` directories together. Each archive includes
a SHA-256 checksum and a smoke test. See the [verification record](contrib/helix/TESTING.md)
for tested platforms, results and the compatibility boundary.
Bundles include license notices and matching application/dependency source;
see [distribution details](contrib/helix/DISTRIBUTION.md).
The macOS bundle uses upstream's release settings without gettext UI
translations, so it does not require Homebrew gettext at runtime.

The default `master` branch contains Exon:

```sh
git clone https://github.com/noahfraiture/exon.git
cd exon
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
"$HOME/.local/opt/neovim-helix/bin/exon"
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
  Then press `bb`: `two ` should be selected, without the first `t` from
  `three`. Press `ee`: ` three` should be selected, without the last `o`
  from `two`.
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
| `mr` + old + new delimiter | Replace surrounds, e.g. `mr"'` changes double to single quotes |
| `md` + delimiter | Delete surrounds, retaining their contents |
| `C`, `Alt-C` | Add a selection on the next / previous line |
| `,`, `Alt-,` | Keep the primary / remove the primary selection |
| `(`, `)` | Rotate the primary selection |
| `;`, `Alt-;` | Collapse selections to heads / reverse direction |
| `s`, `S` | Select regex matches / split selections by regex |
| `/`, `?`, `n`, `N`, `*` | Search forward/backward, repeat, search selection |
| `i a c`, `I A o O` | Native insert, append, change and indented line insertion |
| `>` / `<`, `J` | Indent/unindent selected lines / join lines with native rules |
| `d y p P R r` | Delete, yank, paste, replace selections/characters |
| `"` + register | Choose a named register, including clipboard registers |
| `u`, `U` | Native undo / redo, including session-local selection metadata |
| `zz`, `zc`, `zt`, `zb` | Center the cursor line / align it at the top or bottom |
| `zj`, `zk`, `z` + down/up arrow | Scroll down / up, with an optional prefix count |
| `Ctrl-F`, `Ctrl-B`, `PageDown`, `PageUp` | Native page down / up |
| `Ctrl-D`, `Ctrl-U` | Native half-page down / up |
| `Z` + view commands, `Esc` | Sticky view commands / leave view mode |
| `~`, backtick, `Alt-backtick` | Case changes |
| `:`, `Ctrl-W` | Native command line / window commands |

Selections use Unicode grapheme boundaries, including combining characters and
ZWJ emoji. Overlapping selections and identical insertion gaps merge. Adjacent
selections remain distinct until an edit brings them to the same position.
Word classes use Neovim's Unicode classification and respect 'iskeyword'.
Case transforms also use Neovim's native Unicode conversion.

View commands reuse Neovim's viewport, including folds, wrapped lines and
`scrolloff`. The `z` prefix ends after one action; `Z` stays active until Escape.
Paging keys also work after either prefix. Alignment preserves selections;
scrolling preserves secondary selections and moves the primary only when native
scrolling moves the cursor. Horizontal `zm` alignment is not implemented.

Register paste follows Helix's content rule: if any copied fragment ends with a
line ending, `p` inserts below the selected lines and `P` above them. `x` normally
includes the newline, so deleting/yanking that selection produces linewise
paste. The same rule applies to text from named registers and the system
clipboard; a multiline fragment without a trailing newline stays characterwise.
Paste counts repeat each fragment. With more selections than fragments, the
last fragment is repeated. `R` still replaces selections directly.
The default register respects Neovim's `clipboard=unnamed`/`unnamedplus` options;
explicit register names keep their meaning. Clipboard contents are read when
pasting, so external changes are visible without polling during cursor motions.

Textobjects are lexical delimiter/word/paragraph objects. They do not yet use
tree-sitter to distinguish syntax nodes or delimiters inside comments/strings.
Regular expressions currently use Neovim's regex syntax.

## Configuration and plugins

`h` is the new mapping namespace. Existing `n` mappings remain Vim mappings.
Insert mode uses the existing `i` namespace and real Insert-mode events.
Command arguments are read literally: remapping `i` or `w` does not change
`miw`, and remapping `(` does not change the delimiter read by `ms(`.

Defaults already include `ms(`, `ms[`, `ms"`, `ms/`, etc.: `ms` reads its next
character. The following setup only adds custom pairs and optional shortcuts:

```lua
vim.g.mapleader = ' '
vim.helix.setup({
  -- enabled = true is the default.
  surrounds = {
    c = { '/*', '*/' }, -- msc adds; mic selects inside; mac selects around.
    t = { '<em>', '</em>' }, -- mst, mit, mat; mim also recognizes this pair.
  },
  keymaps = {
    ['<leader>s'] = 'ms', -- Space s, then any delimiter/custom key.
    ['<leader>w'] = '<Cmd>write<CR>',
    ['<leader>i'] = function() vim.helix.textobject('m') end,
  },
})
```

Custom entries supplement the built-in pairs (or override their keys). Pair
keys are one character; `m`, `w`, `W` and `p` are reserved textobjects. Delimiters
may contain multiple characters, but must be nonempty single-line strings
without NUL. The same registry serves adding, inside/around selection and the
nearest-surround objects, replacement and deletion. Matching remains lexical,
not syntax-aware.

With the cursor or a selection inside `"hello"`, `mr"'` produces `'hello'` and
`md"` produces `hello`. `mr([` changes parentheses to square brackets; either
the opening or closing bracket identifies the pair. `mrm'` replaces the closest
surround with single quotes; `mdm` removes the closest surround. Prefix counts
select an outer pair: `2mr([` replaces the second enclosing parenthesis pair.
Custom keys work in both positions, for example `mrct` replaces `/* ... */`
with `<em> ... </em>` using the configuration above.

These commands apply at every selection and undo together. They retain the
selected content, direction and primary selection, then return to Helix normal
mode. Multiple cursors inside one pair edit its delimiters once. If any selection
lacks a matching pair, or shared delimiters need conflicting replacements, the
command leaves the text and selections unchanged. Escape cancels either prompt.
Lua mappings can call `vim.helix.replace_surround('"', "'")` and
`vim.helix.delete_surround('m')`; both accept an optional enclosing-pair count.

`keymaps` values may be strings, callbacks or `false` (`<Nop>`). They use the `h`
namespace and do not change Insert mappings. Use ordinary `vim.keymap.set()`
when you need options such as descriptions, expressions or buffer-local maps.
On another setup call, omitted surrounds are retained; `surrounds = {}` clears
custom pairs. Supplied keymaps update their keys and leave other mappings alone.
`enabled = false` configures the commands without enabling the mode.

The ordinary mapping API also works without setup:

```lua
vim.o.helix = true
vim.keymap.set('h', '<Space>w', '<Cmd>write<CR>')
vim.keymap.set('h', 'Q', function()
  vim.helix.textobject('m') -- Same object used by mim.
end)
vim.keymap.set('h', 'gd', vim.lsp.buf.definition)
vim.keymap.set('h', '<Space>(', function()
  vim.helix.surround('(') -- Wrap every current selection.
end)
```

Disable the mode for an otherwise ordinary buffer with `vim.b.helix = false`.
Special, readonly and unmodifiable buffers use ordinary Vim behavior. This lets
pickers, file browsers and terminals retain their existing input modes.

An explicit `nvim_win_set_cursor()`, `cursor()`, `setpos('.')` or `:normal`
command is a primary-cursor operation and collapses the selection collection.
Buffer edits instead move the existing selection endpoints and preserve other
windows' selection state. Plugins that want to operate on all selections should
use the selection APIs rather than replay a primary-cursor edit.

The example uses built-in completion and snippets. Native insertion is handled
by upstream 0.13's multicursor engine: Helix transfers its cursor contexts into
that engine and takes them back on exit. There is no separate Lua insertion
interpreter or completion fallback that discards the other selections.
Compatible completion applies at every cursor, including differently sized
changes on one line. This uses one primary completion candidate; independent
per-cursor language-server requests and snippet groups are not implied.
Built-in snippet placeholders still use Vim Select mode. External
completion/snippet plugins need their own workflow tests.

`o`/`O`, `I`/`A`, typing, Insert mappings, control keys and indentation reuse native
commands. Native Insert undo boundaries are preserved: cursor movements can
start another undo block, just as in ordinary Neovim. Each such change affects
all participating cursors. `>`/`<` indent each selected line once (even when
several selections share it), respecting `shiftwidth`, `expandtab` and
`shiftround`. `J` joins selected lines, or the next line for a one-line selection,
using native whitespace and `joinspaces` rules. Disjoint ranges undo together.
No extra keymaps are required; these are configurable defaults.

Mouse input uses Neovim's native hit testing and scrolling. Enable terminal
mouse reporting with `vim.o.mouse = 'a'`. A text click replaces the selection
collection with the clicked character. Dragging, double-clicking a word and
triple-clicking a line become Helix selections on release. Blockwise mouse
selections keep Vim Visual behavior. Wheel scrolling targets the hovered window
and preserves secondary selections; if native scrolling clamps the primary
cursor into the viewport, its selection moves to that character. Native Insert
clicks reposition the primary cursor; subsequent typing still uses all cursors.
Mouse bindings can be overridden in the `h` namespace.

Other current boundaries include macro/dot-repeat parity, full Helix command
coverage, mouse selection parity and syntax-aware textobjects. Dot-repeat is
optional scope, not a migration requirement. Persistent undo files retain
Neovim's existing format: text undo survives restart; extra selection snapshots
are session-local. The command layer still uses a temporary document snapshot,
so very large files need further performance work. See the
[architecture and feature review](contrib/helix/REVIEW.md).

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
15 (upstream's current prerelease level); upstream APIs retain their contracts.

Bundled helpers: `vim.helix.setup()`, `surround()`, `replace_surround()`,
`delete_surround()`, `indent()`, `join()`, `textobject()`, `select()`, `search()`, `format()`,
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
