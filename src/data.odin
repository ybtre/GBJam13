package unlucky_dungeon

import rl "vendor:raylib"

/////////////////////////////////////////////////////////////////////
// CONSTANTS
/////////////////////////////////////////////////////////////////////
C_GREEN      :: rl.Color{ 120, 131, 132, 255 }
C_YELLOW     :: rl.Color{ 245, 233, 191, 255 }
C_ORANGE     :: rl.Color{ 170, 100, 77, 255 }
C_PURPLE     :: rl.Color{ 55, 42, 57, 255 }

CARDS_PER_ROW   :: 3
ROWS            :: 13

/////////////////////////////////////////////////////////////////////
// Data
/////////////////////////////////////////////////////////////////////
game_data :: struct {
  internal_res  : rl.Vector2,
  scaled_res    : rl.Vector2,
  rt            : rl.RenderTexture2D,
}

/////////////////////////////////////////////////////////////////////
row :: struct {
    cards           : [CARDS_PER_ROW]obj,
    selected_card   : int,
    cursed          : bool
}

// Row-scaling knobs (keep tiny and readable)
row_values :: struct {
    enemy_dmg, enemy_gold: int,
    potion_heal, poison_dmg: int,
    chest_gold, mimic_dmg:   int,
    w_enemy, w_potion, w_treasure: f32,
    dice_bias_percent: f32,
    row13_cursed: bool,
}

/////////////////////////////////////////////////////////////////////
game_state :: struct {
    seed                : u64,
    rows                : [ROWS]row,
    card_selected_idx   : int,
    resolve_move        : bool
}

/////////////////////////////////////////////////////////////////////
obj_type :: enum {
  PLAYER,
  ENEMY,
  POTION,
  TREASURE,
}

/////////////////////////////////////////////////////////////////////
obj_vis :: struct {
    src    : rl.Rectangle,
    dest   : rl.Rectangle,
    color  : rl.Color,
    render : bool,
}

/////////////////////////////////////////////////////////////////////
stats_player :: struct {
    hp          : int,
    max_hp      : int,
    gold        : int,
    row_current : int,
}

/////////////////////////////////////////////////////////////////////
stats_card :: struct {
    type        : obj_type,
    row_idx     : int,
    // Interpreted at resolution:
    // Enemy:    value_a = damage, value_b = gold
    // Potion:   value_a = heal,   value_b = poison_dmg_on_unlucky (ref)
    // Treasure: value_a = gold,   value_b = mimic_dmg_on_unlucky   (ref)
    val_a:  int,
    val_b:  int,
    // Snapshots for post-mortem / debug:
    w_enemy:    f32,
    w_potion:   f32,
    w_treasure: f32,

    // rows 10..12 (2→1 downgrade), 0 elsewhere; row 13 handled at gameplay
    dice_bias_percent: f32,
    row13_cursed:      bool,
}

/////////////////////////////////////////////////////////////////////
obj :: struct {
  type         : obj_type,
  visual       : obj_vis,
  stats_player : stats_player,
  stats_card   : stats_card,
}

/////////////////////////////////////////////////////////////////////
// Data arrays/vars
/////////////////////////////////////////////////////////////////////
// 1 obj for player + (13 rows * 3 cards in each row) = 40 total
Objects : [1+(ROWS*CARDS_PER_ROW)]obj

GameData : game_data = {
  rl.Vector2{160, 144},
  rl.Vector2{960, 864},
  rl.RenderTexture2D{},
}

GameState : game_state

/////////////////////////////////////////////////////////////////////
// Global varialbes for execution status and game loop
/////////////////////////////////////////////////////////////////////
is_running          : = false
