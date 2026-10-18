#pragma once

#include <stdbool.h>
#include <stddef.h>

#include "nvim/pos_defs.h"
#include "nvim/types_defs.h"

/// Half-open buffer ranges. Direction is independent of range ordering.
typedef struct {
  pos_T start;
  pos_T end;
  bool backward;
} HelixSelection;

/// Selection metadata stored with a native undo header, never document text.
typedef struct {
  handle_T window;
  handle_T buffer;
  size_t count;
  size_t primary;
  bool extending;
  HelixSelection *items;
} HelixSnapshot;
