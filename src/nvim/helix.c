// Native selection-first state. Command policy lives in vim.helix; document
// storage, selection positions, input dispatch and undo remain owned by core.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "klib/kvec.h"
#include "nvim/api/buffer.h"
#include "nvim/api/extmark.h"
#include "nvim/api/keysets_defs.h"
#include "nvim/api/private/defs.h"
#include "nvim/api/private/dispatch.h"
#include "nvim/api/private/helpers.h"
#include "nvim/autocmd.h"
#include "nvim/autocmd_defs.h"
#include "nvim/buffer_defs.h"
#include "nvim/context.h"
#include "nvim/cursor.h"
#include "nvim/decoration_defs.h"
#include "nvim/drawscreen.h"
#include "nvim/eval/typval.h"
#include "nvim/eval/typval_defs.h"
#include "nvim/extmark.h"
#include "nvim/globals.h"
#include "nvim/helix.h"
#include "nvim/highlight_group.h"
#include "nvim/insert.h"
#include "nvim/keycodes.h"
#include "nvim/lua/executor.h"
#include "nvim/macros_defs.h"
#include "nvim/mbyte.h"
#include "nvim/mcursor.h"
#include "nvim/memline.h"
#include "nvim/memory.h"
#include "nvim/message.h"
#include "nvim/option_vars.h"
#include "nvim/state.h"
#include "nvim/state_defs.h"
#include "nvim/strings.h"
#include "nvim/ui.h"
#include "nvim/undo.h"

typedef struct {
  HelixSelection selection;
  bool primary;
} HelixIndexedSelection;

typedef struct helix_window {
  struct helix_window *next;
  handle_T window;
  handle_T buffer;
  uint32_t decorations;
  size_t count;
  size_t primary;
  bool extending;
  bool visible;
  pos_T cursor;
  ContextVec contexts;
  ContextVec saved_cursors;
} HelixWindow;

static HelixWindow *windows;
static bool inserting;
static handle_T insert_window;
static handle_T insert_buffer;
static HelixSnapshot *insert_before;
static LuaRef command_ref = LUA_NOREF;

#include "helix.c.generated.h"

static bool is_inserting(win_T *wp)
{
  return inserting && wp->handle == insert_window && wp->w_buffer->handle == insert_buffer;
}

static bool load_commands(Error *err)
{
  if (command_ref == LUA_NOREF) {
    Object result = NLUA_EXEC_STATIC("return require('vim.helix')._dispatch",
                                     ((Array)ARRAY_DICT_INIT), kRetLuaref, NULL, err);
    if (result.type == kObjectTypeLuaRef) {
      command_ref = result.data.luaref;
    }
  }
  return command_ref != LUA_NOREF;
}

static int position_compare(pos_T a, pos_T b)
{
  return a.lnum == b.lnum ? (a.col > b.col) - (a.col < b.col)
                          : (a.lnum > b.lnum) - (a.lnum < b.lnum);
}

bool helix_enabled(win_T *wp)
{
  if (mc_replaying() || !p_hx || wp->w_buffer->b_p_bt[0] != NUL || !wp->w_buffer->b_p_ma
      || wp->w_buffer->b_p_ro || wp->w_buffer->b_ml.ml_mfp == NULL
      || ex_normal_busy || cmdwin_type != 0) {
    return false;
  }
  dictitem_T *override = tv_dict_find(wp->w_buffer->b_vars, S_LEN("helix"));
  return !(override && override->di_tv.v_type == VAR_BOOL
           && override->di_tv.vval.v_bool == kBoolVarFalse);
}

static pos_T clamp_position(buf_T *buf, pos_T p)
{
  p.lnum = MAX(1, MIN(p.lnum, buf->b_ml.ml_line_count));
  char *line = ml_get_buf(buf, p.lnum);
  p.col = MAX(0, MIN(p.col, (colnr_T)strlen(line)));
  p.col -= utf_head_off(line, line + p.col);
  p.coladd = 0;
  return p;
}

static pos_T next_position(buf_T *buf, pos_T p)
{
  char *line = ml_get_buf(buf, p.lnum);
  if (line[p.col] != NUL) {
    p.col += utfc_ptr2len(line + p.col);
  } else if (p.lnum < buf->b_ml.ml_line_count) {
    p.lnum++;
    p.col = 0;
  }
  return p;
}

static pos_T previous_position(buf_T *buf, pos_T p)
{
  if (p.col > 0) {
    char *line = ml_get_buf(buf, p.lnum);
    p.col -= utf_head_off(line, line + p.col - 1) + 1;
  } else if (p.lnum > 1) {
    p.lnum--;
    p.col = (colnr_T)strlen(ml_get_buf(buf, p.lnum));
  }
  return p;
}

static HelixWindow *window_state(win_T *wp, bool create)
{
  for (HelixWindow *hw = windows; hw; hw = hw->next) {
    if (hw->window == wp->handle && hw->buffer == wp->w_buffer->handle) {
      return hw;
    }
  }
  if (!create) {
    return NULL;
  }
  HelixWindow *hw = xcalloc(1, sizeof(*hw));
  hw->window = wp->handle;
  hw->buffer = wp->w_buffer->handle;
  hw->decorations = (uint32_t)nvim_create_namespace((String)STRING_INIT);
  hw->next = windows;
  windows = hw;

  Object target = WINDOW_OBJ(wp->handle);
  Dict(ns_opts) scope = { 0 };
  PUT_KEY(scope, ns_opts, wins, ((Array){ .items = &target, .size = 1 }));
  Error err = ERROR_INIT;
  nvim__ns_set(hw->decorations, &scope, &err);
  api_clear_error(&err);

  HelixSelection selection = { .start = clamp_position(wp->w_buffer, wp->w_cursor) };
  selection.end = next_position(wp->w_buffer, selection.start);
  store_selections(wp, hw, &selection, 1, 0, false);
  return hw;
}

static HelixSelection selection_at(win_T *wp, HelixWindow *hw, size_t i)
{
  HelixSelection selection = { 0 };
  if (is_inserting(wp)) {
    selection.start = wp->w_cursor;
    if (i != hw->primary) {
      const ContextVec *contexts = mc_contexts();
      size_t index = i < hw->primary ? i : i - 1;
      if (index < kv_size(*contexts)) {
        mc_context_position(&kv_A(*contexts, index), &selection.start);
      }
    }
    selection.end = selection.start;
    return selection;
  }
  Context *ctx = &kv_A(hw->contexts, i);
  if (!ctx_selection_get(ctx, &selection.start, &selection.end)) {
    selection.start = clamp_position(wp->w_buffer, wp->w_cursor);
    selection.end = next_position(wp->w_buffer, selection.start);
  }
  selection.backward = ctx->selection_backward;
  selection.start = clamp_position(wp->w_buffer, selection.start);
  selection.end = clamp_position(wp->w_buffer, selection.end);
  if (position_compare(selection.end, selection.start) < 0) {
    selection.end = selection.start;
  }
  return selection;
}

static void clear_contexts(ContextVec *contexts)
{
  for (size_t i = 0; i < kv_size(*contexts); i++) {
    ctx_free(&kv_A(*contexts, i));
  }
  kv_destroy(*contexts);
  *contexts = (ContextVec)KV_INITIAL_VALUE;
}

static void store_contexts(buf_T *buf, HelixWindow *hw, HelixSelection *items, size_t count,
                           size_t primary, bool extending)
{
  clear_contexts(&hw->contexts);
  hw->count = count;
  hw->primary = primary;
  hw->extending = extending;
  for (size_t i = 0; i < count; i++) {
    items[i].start = clamp_position(buf, items[i].start);
    items[i].end = clamp_position(buf, items[i].end);
    Context ctx = CONTEXT_INIT;
    ctx.pos = items[i].backward || equalpos(items[i].start, items[i].end)
              ? items[i].start : previous_position(buf, items[i].end);
    ctx_selection_set(&ctx, buf, items[i].start, items[i].end, items[i].backward);
    kv_push(hw->contexts, ctx);
  }
  hw->cursor = kv_A(hw->contexts, primary).pos;
}

static void store_selections(win_T *wp, HelixWindow *hw, HelixSelection *items, size_t count,
                             size_t primary, bool extending)
{
  store_contexts(wp->w_buffer, hw, items, count, primary, extending);
  if (helix_enabled(wp)) {
    wp->w_cursor = hw->cursor;
    wp->w_set_curswant = true;
  }
  redraw_later(wp, UPD_VALID);
}

static void render_selections(win_T *wp, HelixWindow *hw)
{
  normalize_selections(wp, hw);
  extmark_clear(wp->w_buffer, hw->decorations, 0, 0, MAXLNUM, MAXCOL);
  hw->visible = helix_enabled(wp);
  if (!hw->visible) {
    return;
  }
  int selection_hl = syn_name2id("HelixSelection");
  int cursor_hl = syn_name2id("HelixCursor");
  if (!selection_hl) {
    selection_hl = syn_name2id("Visual");
  }
  if (!cursor_hl) {
    cursor_hl = syn_name2id("Cursor");
  }
  for (size_t i = 0; i < hw->count; i++) {
    HelixSelection s = selection_at(wp, hw, i);
    Error err = ERROR_INIT;
    Dict(set_extmark) opts = { 0 };
    PUT_KEY(opts, set_extmark, scoped, true);
    PUT_KEY(opts, set_extmark, priority, 150);
    PUT_KEY(opts, set_extmark, strict, false);
    if (position_compare(s.start, s.end) < 0 && !is_inserting(wp)) {
      PUT_KEY(opts, set_extmark, end_row, s.end.lnum - 1);
      PUT_KEY(opts, set_extmark, end_col, s.end.col);
      PUT_KEY(opts, set_extmark, hl_group, INTEGER_OBJ(selection_hl));
      PUT_KEY(opts, set_extmark, hl_eol, true);
      nvim_buf_set_extmark(hw->buffer, hw->decorations, s.start.lnum - 1, s.start.col,
                           &opts, &err);
    }
    if (i != hw->primary) {
      pos_T head = is_inserting(wp) || s.backward || position_compare(s.start, s.end) == 0
                   ? s.start : previous_position(wp->w_buffer, s.end);
      pos_T next = next_position(wp->w_buffer, head);
      opts = (Dict(set_extmark)){ 0 };
      PUT_KEY(opts, set_extmark, scoped, true);
      PUT_KEY(opts, set_extmark, strict, false);
      PUT_KEY(opts, set_extmark, priority, 200);
      if (next.lnum == head.lnum && next.col > head.col) {
        PUT_KEY(opts, set_extmark, end_row, next.lnum - 1);
        PUT_KEY(opts, set_extmark, end_col, next.col);
        PUT_KEY(opts, set_extmark, hl_group, INTEGER_OBJ(cursor_hl));
      } else {
        Object chunks[] = { CSTR_AS_OBJ(" "), INTEGER_OBJ(cursor_hl) };
        Object chunk = ARRAY_OBJ(((Array){ .items = chunks, .size = 2 }));
        PUT_KEY(opts, set_extmark, virt_text, ((Array){ .items = &chunk, .size = 1 }));
        PUT_KEY(opts, set_extmark, virt_text_pos, STATIC_CSTR_AS_STRING("overlay"));
        nvim_buf_set_extmark(hw->buffer, hw->decorations, head.lnum - 1, head.col,
                             &opts, &err);
        api_clear_error(&err);
        continue;
      }
      nvim_buf_set_extmark(hw->buffer, hw->decorations, head.lnum - 1, head.col,
                           &opts, &err);
    }
    api_clear_error(&err);
  }
}

static int compare_selections(const void *left, const void *right)
{
  const HelixIndexedSelection *a = left;
  const HelixIndexedSelection *b = right;
  int start = position_compare(a->selection.start, b->selection.start);
  return start ? start : position_compare(a->selection.end, b->selection.end);
}

/// External API edits may make ranges overlap or move insertion gaps together.
/// Canonicalize in core, preserving the identity/direction of the primary.
static void normalize_selections(win_T *wp, HelixWindow *hw)
{
  if (is_inserting(wp)) {
    hw->count = kv_size(*mc_contexts()) + 1;
    hw->primary = MIN(hw->primary, hw->count - 1);
    return;
  }

  if (hw->count < 2 || textlock > 0) {
    return;
  }
  HelixIndexedSelection *ordered = xcalloc(hw->count, sizeof(*ordered));
  for (size_t i = 0; i < hw->count; i++) {
    ordered[i].selection = selection_at(wp, hw, i);
    ordered[i].primary = i == hw->primary;
  }
  qsort(ordered, hw->count, sizeof(*ordered), compare_selections);
  HelixSelection *items = xcalloc(hw->count, sizeof(*items));
  size_t count = 0;
  size_t primary = 0;
  for (size_t i = 0; i < hw->count; i++) {
    HelixSelection s = ordered[i].selection;
    if (count > 0 && (position_compare(s.start, items[count - 1].end) < 0
                      || position_compare(s.start, items[count - 1].start) == 0)) {
      if (position_compare(s.end, items[count - 1].end) > 0) {
        items[count - 1].end = s.end;
      }
      if (ordered[i].primary) {
        items[count - 1].backward = s.backward;
        primary = count - 1;
      }
    } else {
      items[count] = s;
      if (ordered[i].primary) {
        primary = count;
      }
      count++;
    }
  }
  bool changed = count != hw->count || primary != hw->primary;
  for (size_t i = 0; !changed && i < count; i++) {
    HelixSelection old = selection_at(wp, hw, i);
    changed = position_compare(old.start, items[i].start) != 0
              || position_compare(old.end, items[i].end) != 0
              || old.backward != items[i].backward;
  }
  if (changed) {
    store_selections(wp, hw, items, count, primary, hw->extending);
  }
  xfree(items);
  xfree(ordered);
}

bool helix_extending(void)
{
  HelixWindow *hw = window_state(curwin, false);
  return hw && hw->extending;
}

/// Argument keys belong to the active command, not the top-level mapping table.
bool helix_pending_argument(void)
{
  Error err = ERROR_INIT;
  Object result = NLUA_EXEC_STATIC("return require('vim.helix')._pending_argument()",
                                   ((Array)ARRAY_DICT_INIT), kRetNilBool, NULL, &err);
  bool pending = result.type == kObjectTypeBoolean && result.data.boolean;
  api_free_object(result);
  api_clear_error(&err);
  return pending;
}

/// Explicit legacy cursor APIs are intentional jumps. Buffer edits instead
/// transform the extmarks and never collapse a window's selection collection.
void helix_cursor_set(win_T *wp)
{
  HelixWindow *hw = window_state(wp, false);
  if (hw && helix_enabled(wp) && !is_inserting(wp) && !Visual.active) {
    HelixSelection s = { .start = clamp_position(wp->w_buffer, wp->w_cursor) };
    s.end = is_inserting(wp) ? s.start : next_position(wp->w_buffer, s.start);
    store_selections(wp, hw, &s, 1, 0, false);
    render_selections(wp, hw);
  }
}

void helix_refresh(void)
{
  if (mc_replaying()) {
    return;
  }
  if (inserting && !(State & MODE_INSERT) && restart_edit == 0) {
    helix_insert_end();
  }
  // Hide stale decorations after a global toggle, including inactive windows.
  for (HelixWindow *hw = windows; hw; hw = hw->next) {
    Error err = ERROR_INIT;
    win_T *wp = find_window_by_handle(hw->window, &err);
    if (wp && wp->w_buffer->handle == hw->buffer && hw->visible && !helix_enabled(wp)) {
      render_selections(wp, hw);
    }
    api_clear_error(&err);
  }
  if (!helix_enabled(curwin) || Visual.active) {
    if (State == MODE_HELIX) {
      State = MODE_NORMAL;
      may_trigger_modechanged();
    }
    return;
  }
  HelixWindow *hw = window_state(curwin, true);
  {
    HelixSelection s = selection_at(curwin, hw, hw->primary);
    curwin->w_cursor = is_inserting(curwin) || s.backward ? s.start
                                                          : position_compare(s.start,
                                                                             s.end) == 0 ? s.start
                                                                                         :
                       previous_position(curbuf, s.end);
    hw->cursor = curwin->w_cursor;
  }
  render_selections(curwin, hw);
}

bool helix_prepare(void)
{
  if (!helix_enabled(curwin) || Visual.active || inserting) {
    return false;
  }
  Error err = ERROR_INIT;
  if (!load_commands(&err)) {
    if (ERROR_SET(&err)) {
      emsg(err.msg);
      api_clear_error(&err);
    }
    return false;
  }
  State = MODE_HELIX;
  helix_refresh();
  may_trigger_modechanged();
  ui_cursor_shape();
  return true;
}

static bool read_position(buf_T *buf, Array values, size_t index, pos_T *out, Error *err)
{
  Object row = values.items[index];
  Object col = values.items[index + 1];
  if (row.type != kObjectTypeInteger || col.type != kObjectTypeInteger
      || row.data.integer < 0 || row.data.integer >= buf->b_ml.ml_line_count
      || col.data.integer < 0 || col.data.integer > MAXCOL) {
    api_set_error(err, kErrorTypeValidation, "Invalid Helix position");
    return false;
  }
  char *line = ml_get_buf(buf, (linenr_T)row.data.integer + 1);
  if ((size_t)col.data.integer > strlen(line)
      || utf_head_off(line, line + col.data.integer) != 0) {
    api_set_error(err, kErrorTypeValidation, "Helix position is not a UTF-8 boundary");
    return false;
  }
  *out = (pos_T){ .lnum = (linenr_T)row.data.integer + 1, .col = (colnr_T)col.data.integer };
  return true;
}

Dict helix_state(win_T *wp, Arena *arena)
{
  HelixWindow *hw = window_state(wp, true);
  normalize_selections(wp, hw);
  Dict state = arena_dict(arena, 5);
  Array selections = arena_array(arena, hw->count);
  for (size_t i = 0; i < hw->count; i++) {
    HelixSelection s = selection_at(wp, hw, i);
    Array item = arena_array(arena, 5);
    ADD_C(item, INTEGER_OBJ(s.start.lnum - 1));
    ADD_C(item, INTEGER_OBJ(s.start.col));
    ADD_C(item, INTEGER_OBJ(s.end.lnum - 1));
    ADD_C(item, INTEGER_OBJ(s.end.col));
    ADD_C(item, BOOLEAN_OBJ(s.backward));
    ADD_C(selections, ARRAY_OBJ(item));
  }
  PUT_C(state, "selections", ARRAY_OBJ(selections));
  PUT_C(state, "primary", INTEGER_OBJ((Integer)hw->primary + 1));
  PUT_C(state, "extending", BOOLEAN_OBJ(hw->extending));
  PUT_C(state, "enabled", BOOLEAN_OBJ(helix_enabled(wp)));
  PUT_C(state, "inserting", BOOLEAN_OBJ(is_inserting(wp)));
  return state;
}

void helix_set_selections(win_T *wp, Array selections, Integer primary, bool extending, Error *err)
{
  if (is_inserting(wp)) {
    api_set_error(err, kErrorTypeException,
                  "Cannot replace Helix selections during native insertion");
    return;
  }
  if (selections.size == 0 || selections.size > 10000 || primary < 1
      || primary > (Integer)selections.size) {
    api_set_error(err, kErrorTypeValidation, "Invalid Helix selection count or primary index");
    return;
  }
  HelixSelection *items = xcalloc(selections.size, sizeof(*items));
  for (size_t i = 0; i < selections.size; i++) {
    Object obj = selections.items[i];
    if (obj.type != kObjectTypeArray || obj.data.array.size != 5
        || obj.data.array.items[4].type != kObjectTypeBoolean) {
      api_set_error(err, kErrorTypeValidation,
                    "Expected [start_row, start_col, end_row, end_col, backward]");
      break;
    }
    Array values = obj.data.array;
    if (!read_position(wp->w_buffer, values, 0, &items[i].start, err)
        || !read_position(wp->w_buffer, values, 2, &items[i].end, err)) {
      break;
    }
    items[i].backward = values.items[4].data.boolean;
    if (position_compare(items[i].start, items[i].end) > 0
        || (i > 0 && (position_compare(items[i].start, items[i - 1].end) < 0
                      || position_compare(items[i].start, items[i - 1].start) == 0))) {
      api_set_error(err, kErrorTypeValidation,
                    "Helix selections must be ordered and non-overlapping");
      break;
    }
  }
  if (!ERROR_SET(err)) {
    HelixWindow *hw = window_state(wp, true);
    store_selections(wp, hw, items, selections.size, (size_t)primary - 1, extending);
    render_selections(wp, hw);
  }
  xfree(items);
}

void helix_apply_edits(Array edits, bool join, Error *err)
{
  if (edits.size > 10000) {
    api_set_error(err, kErrorTypeValidation, "Too many Helix edits (maximum 10000)");
    return;
  }
  if (!curbuf->b_p_ma || curbuf->b_p_ro) {
    api_set_error(err, kErrorTypeException, "Helix buffer is not writable");
    return;
  }
  pos_T previous_start = { 0 };
  pos_T previous_end = { 0 };
  for (size_t i = 0; i < edits.size; i++) {
    Object obj = edits.items[i];
    if (obj.type != kObjectTypeArray || obj.data.array.size != 5
        || obj.data.array.items[4].type != kObjectTypeArray) {
      api_set_error(err, kErrorTypeValidation, "Invalid Helix edit");
      return;
    }
    Array values = obj.data.array;
    pos_T start, end;
    if (!read_position(curbuf, values, 0, &start, err)
        || !read_position(curbuf, values, 2, &end, err)) {
      return;
    }
    if (position_compare(start, end) > 0
        || (i > 0 && (position_compare(start, previous_end) < 0
                      || position_compare(start, previous_start) == 0))) {
      api_set_error(err, kErrorTypeValidation, "Helix edits must be ordered and non-overlapping");
      return;
    }
    Array lines = values.items[4].data.array;
    for (size_t j = 0; j < lines.size; j++) {
      if (lines.items[j].type != kObjectTypeString
          || memchr(lines.items[j].data.string.data, '\n', lines.items[j].data.string.size)
          || memchr(lines.items[j].data.string.data, NUL, lines.items[j].data.string.size)) {
        api_set_error(err, kErrorTypeValidation,
                      "Helix replacement lines must be strings without newlines or NUL");
        return;
      }
    }
    previous_start = start;
    previous_end = end;
  }
  if (edits.size == 0) {
    return;
  }
  if (!join) {
    u_sync(true);
  }
  // Each buffer mutation locks on_bytes callbacks against reentrant edits.
  // No event-loop turn occurs between the edits in this transaction.
  Arena arena = ARENA_EMPTY;
  for (size_t i = edits.size; i > 0; i--) {
    Array edit = edits.items[i - 1].data.array;
    nvim_buf_set_text(LUA_INTERNAL_CALL, curbuf->handle,
                      edit.items[0].data.integer, edit.items[1].data.integer,
                      edit.items[2].data.integer, edit.items[3].data.integer,
                      edit.items[4].data.array, &arena, err);
    if (ERROR_SET(err)) {
      break;
    }
  }
  arena_mem_free(arena_finish(&arena));
}

HelixSnapshot *helix_snapshot(win_T *wp)
{
  if (!helix_enabled(wp)) {
    return NULL;
  }
  if (insert_before && insert_before->window == wp->handle
      && insert_before->buffer == wp->w_buffer->handle) {
    HelixSnapshot *snapshot = insert_before;
    insert_before = NULL;
    return snapshot;
  }
  HelixWindow *hw = window_state(wp, true);
  normalize_selections(wp, hw);
  HelixSnapshot *snapshot = xcalloc(1, sizeof(*snapshot));
  snapshot->window = wp->handle;
  snapshot->buffer = wp->w_buffer->handle;
  snapshot->count = hw->count;
  snapshot->primary = hw->primary;
  snapshot->extending = hw->extending;
  snapshot->items = xcalloc(hw->count, sizeof(*snapshot->items));
  for (size_t i = 0; i < hw->count; i++) {
    snapshot->items[i] = selection_at(wp, hw, i);
  }
  return snapshot;
}

void helix_snapshot_free(HelixSnapshot *snapshot)
{
  if (snapshot) {
    xfree(snapshot->items);
    xfree(snapshot);
  }
}

HelixSnapshot *helix_undo_capture(HelixSnapshot *saved)
{
  if (!saved) {
    return NULL;
  }
  Error err = ERROR_INIT;
  win_T *wp = find_window_by_handle(saved->window, &err);
  api_clear_error(&err);
  return wp && wp->w_buffer == curbuf && curbuf->handle == saved->buffer
         ? helix_snapshot(wp) : NULL;
}

void helix_undo_restore(HelixSnapshot **saved, HelixSnapshot *replacement)
{
  if (!*saved) {
    helix_snapshot_free(replacement);
    return;
  }
  Error err = ERROR_INIT;
  win_T *wp = find_window_by_handle((*saved)->window, &err);
  if (!wp || wp->w_buffer != curbuf || curbuf->handle != (*saved)->buffer) {
    api_clear_error(&err);
    helix_snapshot_free(replacement);
    return;
  }
  HelixWindow *hw = window_state(wp, true);
  store_selections(wp, hw, (*saved)->items, (*saved)->count,
                   (*saved)->primary, (*saved)->extending);
  render_selections(wp, hw);
  helix_snapshot_free(*saved);
  *saved = replacement;
}

static Object call_command(int key, Error *err)
{
  if (!load_commands(err)) {
    return NIL;
  }
  char bytes[MB_MAXBYTES + 1];
  const char *name;
  if (IS_SPECIAL(key) || mod_mask != 0 || key < ' ') {
    name = get_special_key_name(key, mod_mask);
  } else {
    bytes[utf_char2bytes(key, bytes)] = NUL;
    name = bytes;
  }
  Object args[] = { CSTR_AS_OBJ(name) };
  return nlua_call_ref(command_ref, NULL, ((Array){ .items = args, .size = 1 }),
                       kRetObject, NULL, err);
}

static void helix_insert_start(HelixWindow *hw)
{
  hw->saved_cursors = mc_contexts_take();
  ContextVec contexts = KV_INITIAL_VALUE;
  for (size_t i = 0; i < kv_size(hw->contexts); i++) {
    // Resolve selection marks: external edits may have moved them since the last command.
    HelixSelection selection = selection_at(curwin, hw, i);
    kv_A(hw->contexts, i).pos = selection.backward || equalpos(selection.start, selection.end)
                                ? selection.start : previous_position(curbuf, selection.end);
    if (i != hw->primary) {
      kv_push(contexts, kv_A(hw->contexts, i));
      kv_A(hw->contexts, i) = (Context)CONTEXT_INIT;
    }
  }
  mc_contexts_adopt(&contexts, curwin->handle);
  inserting = true;
  insert_window = curwin->handle;
  insert_buffer = curbuf->handle;
}

bool helix_handle_key(int *key)
{
  if (*key == K_LUA || *key == K_COMMAND) {
    return false;
  }
  if (*key == K_EVENT) {
    state_handle_k_event();
    return true;
  }
  if (*key == K_IGNORE || *key == K_NOP) {
    return true;
  }
  HelixSnapshot *before = helix_snapshot(curwin);
  Error err = ERROR_INIT;
  Object result = call_command(*key, &err);
  bool handled = true;
  if (ERROR_SET(&err)) {
    emsg(err.msg);
    api_clear_error(&err);
  } else if (result.type == kObjectTypeString) {
    if (strequal(result.data.string.data, "native")) {
      handled = false;
    } else if (strequal(result.data.string.data, "insert")
               || strequal(result.data.string.data, "native_insert")) {
      if (strequal(result.data.string.data, "insert")) {
        *key = 'i';  // Helix placed each insertion gap before/after its selection.
      }
      helix_insert_start(window_state(curwin, true));
      insert_before = before;
      before = NULL;
      handled = false;  // Native command owns entry, capture, completion and insertion.
    }
  }
  api_free_object(result);
  helix_snapshot_free(before);
  return handled;
}

void helix_insert_end(void)
{
  if (!inserting || mc_replaying()) {
    return;
  }
  ContextVec contexts = mc_contexts_take();
  inserting = false;
  helix_snapshot_free(insert_before);
  insert_before = NULL;
  HelixWindow *hw = windows;
  while (hw && (hw->window != insert_window || hw->buffer != insert_buffer)) {
    hw = hw->next;
  }
  buf_T *buf = handle_get_buffer(insert_buffer);
  if (hw && buf) {
    Error err = ERROR_INIT;
    win_T *wp = find_window_by_handle(insert_window, &err);
    api_clear_error(&err);
    pos_T primary_pos = { .lnum = 1 };
    if (wp && wp->w_buffer == buf) {
      primary_pos = wp->w_cursor;
      if (wp != curwin && primary_pos.col > 0) {
        primary_pos = previous_position(buf, primary_pos);
      }
    } else if (hw->primary < kv_size(hw->contexts)) {
      pos_T end;
      ctx_selection_get(&kv_A(hw->contexts, hw->primary), &primary_pos, &end);
      if (primary_pos.col > 0) {
        primary_pos = previous_position(buf, primary_pos);
      }
    }
    const size_t count = kv_size(contexts) + 1;
    HelixSelection *items = xcalloc(count, sizeof(*items));
    size_t primary = MIN(hw->primary, count - 1);
    for (size_t i = 0; i < count; i++) {
      pos_T pos = i == primary ? primary_pos
                               : kv_A(contexts, i < primary ? i : i - 1).pos;
      // Native Escape shifts cursors only in the current buffer.
      if (i != primary && curbuf != buf && pos.col > 0) {
        pos = previous_position(buf, pos);
      }
      items[i].start = clamp_position(buf, pos);
      items[i].end = next_position(buf, items[i].start);
    }
    clear_contexts(&contexts);
    mc_contexts_adopt(&hw->saved_cursors, 0);
    store_contexts(buf, hw, items, count, primary, false);
    xfree(items);
    if (wp && wp->w_buffer == buf) {
      normalize_selections(wp, hw);
    }
  } else {
    clear_contexts(&contexts);
  }
}

void helix_window_free(win_T *wp)
{
  HelixWindow **link = &windows;
  while (*link) {
    HelixWindow *hw = *link;
    if (hw->window != wp->handle) {
      link = &hw->next;
      continue;
    }
    Error err = ERROR_INIT;
    buf_T *buf = find_buffer_by_handle(hw->buffer, &err);
    if (buf && buf->b_ml.ml_mfp) {
      extmark_clear(buf, hw->decorations, 0, 0, MAXLNUM, MAXCOL);
    }
    api_clear_error(&err);
    Dict(ns_opts) scope = { 0 };
    PUT_KEY(scope, ns_opts, wins, ((Array)ARRAY_DICT_INIT));
    nvim__ns_set(hw->decorations, &scope, &err);
    api_clear_error(&err);
    *link = hw->next;
    clear_contexts(&hw->contexts);
    clear_contexts(&hw->saved_cursors);
    xfree(hw);
  }
}

void helix_buffer_free(buf_T *buf)
{
  HelixWindow **link = &windows;
  while (*link) {
    HelixWindow *hw = *link;
    if (hw->buffer != buf->handle) {
      link = &hw->next;
      continue;
    }
    Error err = ERROR_INIT;
    Dict(ns_opts) scope = { 0 };
    PUT_KEY(scope, ns_opts, wins, ((Array)ARRAY_DICT_INIT));
    nvim__ns_set(hw->decorations, &scope, &err);
    api_clear_error(&err);
    *link = hw->next;
    clear_contexts(&hw->contexts);
    clear_contexts(&hw->saved_cursors);
    xfree(hw);
  }
}

void helix_free_all(void)
{
  while (windows) {
    HelixWindow *hw = windows;
    windows = hw->next;
    clear_contexts(&hw->contexts);
    clear_contexts(&hw->saved_cursors);
    xfree(hw);
  }
  helix_snapshot_free(insert_before);
  insert_before = NULL;
  NLUA_CLEAR_REF(command_ref);
}
