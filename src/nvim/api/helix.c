#include "nvim/api/helix.h"
#include "nvim/api/private/helpers.h"
#include "nvim/helix.h"

#include "api/helix.c.generated.h"

/// Gets native half-open selections for a window.
/// Each selection is [start_row, start_col, end_row, end_col, backward].
/// Rows and byte columns are zero-based. The primary index is one-based.
/// @param win Window handle, or 0 for current window.
/// @param arena Arena for returned data.
/// @param err Error details.
/// @return State including selections, primary, extending and enabled.
Dict nvim_helix_get_state(Window win, Arena *arena, Error *err)
  FUNC_API_SINCE(15)
{
  win_T *wp = find_window_by_handle(win, err);
  return wp ? helix_state(wp, arena) : (Dict)ARRAY_DICT_INIT;
}

/// Sets the native selection collection without changing buffer text.
/// @param win Window handle, or 0 for current window.
/// @param selections Ordered non-overlapping half-open ranges.
/// @param primary One-based primary selection index.
/// @param extending Whether motions extend existing selections.
/// @param err Error details. Validation completes before state is changed.
void nvim_helix_set_selections(Window win, Array selections, Integer primary, Boolean extending,
                               Error *err)
  FUNC_API_SINCE(15)
{
  win_T *wp = find_window_by_handle(win, err);
  if (wp) {
    helix_set_selections(wp, selections, primary, extending, err);
  }
}

/// Applies a simultaneous edit transaction to the current buffer.
/// Edits are [start_row, start_col, end_row, end_col, replacement_lines].
/// Coordinates refer to the buffer before any edits. Ranges must be ordered
/// and non-overlapping. The complete request is validated before mutation.
/// @param edits Array of edits, applied from last to first.
/// @param join Join an active insert transaction instead of starting an undo block.
/// @param err Error details.
void nvim_helix_apply_edits(Array edits, Boolean join, Error *err)
  FUNC_API_SINCE(15) FUNC_API_TEXTLOCK
{
  helix_apply_edits(edits, join, err);
}
