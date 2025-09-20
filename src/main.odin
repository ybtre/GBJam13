package unlucky_dungeon

import "core:fmt"
import "core:mem"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

/////////////////////////////////////////////////////////////////////
// DONE;
/////////////////////////////////////////////////////////////////////
//  -Create Player struct/class.
//  -Add HP, Gold, RowIndex, MaxHP.
//  -Add Reset() function.
//  -Enum: Enemy, Potion, Treasure, Cursed.
//  -Map Left/Right arrow (or A/D) → card select.
//  -Map Enter/Space → confirm.
//  -Map R → restart.
//  Define row count = 13.
//  Function: GenerateRow(int rowIndex) returns 3 cards.
//  Apply weight formula (Enemy ↑, Potion ↓).
//  Clamp at least 1 safe card in rows 1–3.
// Enemy
//  Subtract base damage from HP.
//  Add Gold reward (if still alive).
// Potion
//  Add HP (clamped at MaxHP).
// Treasure
//  Add Gold.

/////////////////////////////////////////////////////////////////////
// TO DO:
/////////////////////////////////////////////////////////////////////
//  -Fields: baseValue(s), rowIndex, modifiers.
// Weights per row
//  Allow full enemy rows only after row 8.
// Cursed (Row 13 only)
//  Enemy = extra damage.
//  Potion = poison damage.
//  Treasure = mimic (HP loss).

/////////////////////////////////////////////////////////////////////
compute_row_values :: proc(row_idx: int) -> row_values {
    t := norm_t(row_idx)

    // Weights: Enemy ↑, Potion ↓, Treasure = remainder
    w_enemy  := lerp(0.30, 0.60, t)
    w_potion := lerp(0.50, 0.20, t)
    w_treasure := clamp_f01(1.0 - (w_enemy + w_potion))

    enemy_dmg : int
    if row_idx >= 9 { enemy_dmg = 3 }
    else if row_idx >= 4 { enemy_dmg = 2 }
    else { enemy_dmg = 1 }

    enemy_gold : int
    if row_idx >= 5 { enemy_gold = 2 }
    else { enemy_gold = 1 }
    if row_idx >= 10 { enemy_gold = 3 }

    potion_heal : int
    if row_idx >= 9 { potion_heal = 2 }
    else if row_idx >= 3 { potion_heal = 3 }
    else { potion_heal = 4 }

    poison_dmg : int
    if row_idx >= 12 { poison_dmg = 4 }
    else if row_idx >= 7 { poison_dmg = 3 }
    else { poison_dmg = 2 }

    chest_gold : int
    if row_idx >= 12 { chest_gold = 5 }
    else if row_idx >= 8 { chest_gold = 4 }
    else if row_idx >= 4 { chest_gold = 3 }
    else { chest_gold = 2 }

    mimic_dmg : int
    if row_idx >= 10 { mimic_dmg = 3 }
    else if row_idx >= 5 { mimic_dmg = 2 }
    else { mimic_dmg = 1 }

    // Dice bias (2→1 downgrade chance). Row 13 handled at gameplay (treat as 1).
    dice_bias_percent: f32
    switch row_idx {
    case 10: dice_bias_percent = 0.10
    case 11: dice_bias_percent = 0.15
    case 12: dice_bias_percent = 0.25
    case:    dice_bias_percent = 0.00
    }

    return row_values{
        enemy_dmg, enemy_gold,
        potion_heal, poison_dmg,
        chest_gold, mimic_dmg,
        w_enemy, w_potion, w_treasure,
        dice_bias_percent,
        row_idx == 13,
    }
}


// Weighted pick: 0 Enemy, 1 Potion, 2 Treasure
/////////////////////////////////////////////////////////////////////
pick_weighted_index :: proc(rng: ^Rng, w0, w1, w2: f32) -> int {
    total := w0 + w1 + w2
    if total <= 0.0 { return 0 } // fallback

    r := rng_between_f01(rng) * total

    if r < w0 { return 0 }

    r -= w0
    if r < w1 { return 1 }

    return 2
}

/////////////////////////////////////////////////////////////////////
// Gameplay Functions:
/////////////////////////////////////////////////////////////////////
generate_dungeon :: proc(seed : u64) {
    rng := rng_init(seed)
    GameState.seed = seed

    for row_idx in 0..<ROWS {
        rv := compute_row_values(row_idx)

        non_enemy_count := 0
        for i in 0..<CARDS_PER_ROW {
            idx := pick_weighted_index(&rng, rv.w_enemy, rv.w_potion, rv.w_treasure)
            card_type : obj_type

            if idx == 0 { card_type = obj_type.ENEMY }
            else if idx == 1 { card_type = obj_type.POTION }
            else { card_type = obj_type.TREASURE }

            // Early fairness: rows 1–3 guarantee at least one non-enemy
            if row_idx < 3 && i == CARDS_PER_ROW - 1 && non_enemy_count == 0 {
                // force a non-enemy by relative weight
                if rv.w_potion >= rv.w_treasure { card_type = obj_type.POTION}
                else { card_type = obj_type.TREASURE }
            }

            if card_type != .ENEMY {
                non_enemy_count += 1
            }

            val_a : int
            #partial switch card_type {
                case .ENEMY:    val_a = rv.enemy_dmg
                case .POTION:   val_a = rv.potion_heal
                case .TREASURE: val_a = rv.chest_gold
            }
            val_b : int
            #partial switch card_type {
                case .ENEMY:    val_b = rv.enemy_gold
                case .POTION:   val_b = rv.poison_dmg
                case .TREASURE: val_b = rv.mimic_dmg
            }

            card := stats_card{
                card_type,
                row_idx,

                val_a,
                val_b,

                rv.w_enemy, rv.w_potion, rv.w_treasure,
                rv.dice_bias_percent,
                rv.row13_cursed,
            }

            GameState.rows[row_idx].cursed = false
            if row_idx == 13 {
                GameState.rows[row_idx].cursed = true
            }

            GameState.rows[row_idx].cards[i].type = card_type
            if card_type == .ENEMY {
                GameState.rows[row_idx].cards[i].visual.color = C_ORANGE
                GameState.rows[row_idx].cards[i].visual.render = true
            }
            else if card_type == .POTION {
                GameState.rows[row_idx].cards[i].visual.color = C_GREEN
                GameState.rows[row_idx].cards[i].visual.render = true
            }
            else if card_type == .TREASURE {
                GameState.rows[row_idx].cards[i].visual.color = C_YELLOW
                GameState.rows[row_idx].cards[i].visual.render = true
            }
            GameState.rows[row_idx].cards[i].stats_card = card
        }
    }
}

/////////////////////////////////////////////////////////////////////
resolve_move :: proc() {
    player := &Objects[0]

    card_idx := GameState.card_selected_idx
    row_idx := Objects[0].stats_player.row_current
    card := &GameState.rows[row_idx].cards[card_idx]
    row := GameState.rows[row_idx]

    // Enemy:    value_a = damage, value_b = gold
    // Potion:   value_a = heal,   value_b = poison_dmg_on_unlucky (ref)
    // Treasure: value_a = gold,   value_b = mimic_dmg_on_unlucky   (ref)
    #partial switch card.type {
        case .ENEMY:{
            if !row.cursed
            {
                player.stats_player.hp -= card.stats_card.val_a
                player.stats_player.gold += card.stats_card.val_b
            }
            else
            {

            }
        }
        case .POTION:{
            if !row.cursed
            {
                player.stats_player.hp += card.stats_card.val_a
                if player.stats_player.hp > player.stats_player.max_hp
                {
                    player.stats_player.hp = player.stats_player.max_hp
                }
            }
            else
            {

            }
        }
        case.TREASURE:{
            if !row.cursed
            {
                player.stats_player.gold += card.stats_card.val_a
            }
            else
            {

            }
        }
    }

    GameState.resolve_move = true
}

/////////////////////////////////////////////////////////////////////
reset_player :: proc()
{
    Objects[0].stats_player.max_hp = 10
    Objects[0].stats_player.hp = Objects[0].stats_player.max_hp
    Objects[0].stats_player.gold = 0
    Objects[0].stats_player.row_current = 0
}

/////////////////////////////////////////////////////////////////////
// Main Functions:
// - window setup
// - game setup
// - process_input
// - update
// - render
// - free res
// - main
/////////////////////////////////////////////////////////////////////
window_setup :: proc() {
  using rl

  InitWindow(
    i32(GameData.scaled_res.x),
    i32(GameData.scaled_res.y),
    "Unlucky Forward")

  SetTargetFPS(60)

  // Render to a small offscreen target (the "internal" framebuffer)
  GameData.rt = LoadRenderTexture(
    i32(GameData.internal_res.x),
    i32(GameData.internal_res.y))

  // Important: nearest-neighbor filter so scaled pixels are sharp
  SetTextureFilter(GameData.rt.texture, TextureFilter.POINT)

  SetExitKey(KeyboardKey.Q)
}

/////////////////////////////////////////////////////////////////////
game_setup :: proc() {
  using rl

  //Player visual setup
  Objects[0].type = .PLAYER
  Objects[0].visual.render = true;
  Objects[0].visual.color = C_GREEN
  Objects[0].visual.dest = Rectangle{
    GameData.internal_res.x / 2 - 6,
    GameData.internal_res.y / 2 + 50,
    12, 16}

  GameState.menu_state = .MAIN_MENU
  GameState.selected_menu_btn = 0
  // InitRunState()
}

/////////////////////////////////////////////////////////////////////
InitRunState :: proc()
{
    reset_player()

    GameState.card_selected_idx = 1;

    // choose once per run, record for logs
    run_seed := u64(0xBADC0FFEE)
    GameState.seed = run_seed
    generate_dungeon(GameState.seed)

    GameState.menu_state = .DUNGEON
}

/////////////////////////////////////////////////////////////////////
process_input :: proc() {
    using rl

    switch GameState.menu_state {
    case .MAIN_MENU:
        {
            selected := &GameState.selected_menu_btn

            if IsKeyPressed(.S) || IsKeyPressed(.DOWN){
                selected^ += 1
            }
            if IsKeyPressed(.W) || IsKeyPressed(.UP){
                selected^ -= 1
            }

            if selected^ < 0 { selected^ = 0 }
            if selected^ > 2 { selected^ = 2}

            if IsKeyPressed(.SPACE) || IsKeyPressed(.ENTER)
            {
                if selected^ == 0
                {
                   InitRunState()
                }
                else if selected^ == 1
                {
                    GameState.menu_state = .HOW_TO_PLAY
                }
                else if selected^ == 2
                {
                   CloseWindow()
                }
            }
            if IsKeyPressed(.ESCAPE)
            {
                CloseWindow()
            }
        }
    case .DUNGEON:
        {
            if IsKeyPressed(.A) || IsKeyPressed(.LEFT){
                GameState.card_selected_idx -= 1
            }
            if IsKeyPressed(.D) || IsKeyPressed(.RIGHT){
                GameState.card_selected_idx += 1
            }

            //clamp card selected idx
            if GameState.card_selected_idx < 0 {
                GameState.card_selected_idx = 0
            }
            if GameState.card_selected_idx > 2 {
                GameState.card_selected_idx = 2
            }


            if IsKeyPressed(.SPACE) || IsKeyPressed(.ENTER)
            {
                current_row_idx := Objects[0].stats_player.row_current
                GameState.rows[current_row_idx].selected_card = GameState.card_selected_idx

                resolve_move()
            }
            if IsKeyPressed(.R)
            {
                InitRunState()
            }
        }
    case .VICTORY:
        {
            if IsKeyPressed(.R)
            {
                InitRunState()
            }

            if IsKeyPressed(.ESCAPE)
            {
                GameState.menu_state = .MAIN_MENU
            }
        }
    case .DEFEAT:
        {
            selection := &GameState.selected_menu_btn
            if IsKeyPressed(.UP) || IsKeyPressed(.W) {
                selection^ = 0
            }
            if IsKeyPressed(.DOWN) || IsKeyPressed(.S) {
                selection^ = 1
            }
            if IsKeyPressed(.ENTER) || IsKeyPressed(.SPACE) {
                if selection^ == 0 {
                    InitRunState()
                }
                if selection^ == 1
                {
                    GameState.menu_state = .MAIN_MENU
                }
            }
            if IsKeyPressed(.ESCAPE)
            {
                GameState.menu_state = .MAIN_MENU
            }
        }
    case .HOW_TO_PLAY:
        {
            if IsKeyPressed(.BACKSPACE) ||
                IsKeyPressed(.ESCAPE) ||
                IsKeyPressed(.ENTER) ||
                IsKeyPressed(.SPACE)
            {
                GameState.menu_state = .MAIN_MENU
            }
        }
    }
}

/////////////////////////////////////////////////////////////////////
update :: proc() {

    #partial switch GameState.menu_state {
    case .MAIN_MENU:
        {

        }
    case .DUNGEON:
        {
            player := &Objects[0]

            if player.stats_player.hp <= 0
            {
               GameState.menu_state = .DEFEAT
            }

            if GameState.resolve_move == true {
                next_row := player.stats_player.row_current + 1

                if next_row < ROWS {
                   player.stats_player.row_current = next_row
                }

                GameState.resolve_move = false

                if next_row >= 13
                {
                    GameState.menu_state = .VICTORY
                }
            }

        }
    }
}

/////////////////////////////////////////////////////////////////////
render :: proc() {
    using rl
    using strings

    w := i32(GameData.internal_res.x)
    h := i32(GameData.internal_res.y)

    BeginTextureMode(GameData.rt)

        switch GameState.menu_state {
        case .MAIN_MENU:
            {
                ClearBackground(C_YELLOW)

                font_sz : i32 = 2
                y0 :i32= 48
                gap :i32= 22

                selected := &GameState.selected_menu_btn

                for i in 0..<len(main_menu_options) {
                    label := main_menu_options[i]
                    tw := MeasureText(clone_to_cstring(label, context.temp_allocator), font_sz)

                    // bordered button box around text
                    bx :i32= w/2 - (tw/2) - 6
                    by :i32= y0 + i32(i) * gap - 4
                    bw := tw + 12
                    bh := font_sz + 16

                    active := i == selected^

                    // outline
                    DrawRectangleLines(bx, by, bw, bh, C_PURPLE)

                    if active {
                        DrawRectangle(bx, by, bw, bh, C_GREEN)
                        DrawText(clone_to_cstring(label, context.temp_allocator),
                            bx + 6, by + 4,
                            font_sz, C_YELLOW)
                    } else {
                        DrawText(clone_to_cstring(label, context.temp_allocator),
                            w / 2 - tw / 2,
                            y0 + i32(i) * gap,
                            font_sz, C_PURPLE)
                    }
                }

                // Decorative dice (left/right)
                DrawRectangle(12, 60, 12, 12, C_ORANGE)
                DrawText("1", 15, 62, 8, C_YELLOW)
                DrawRectangle(w-24, 82, 12, 12, C_ORANGE)
                DrawText("6", w-21, 84, 8, C_YELLOW)

                // Footer
                DrawText("ENTER: SELECT   ESC: QUIT",
                    6, h - 14,
                    2, C_PURPLE)

            }
        case .DUNGEON:
            {
                ClearBackground(C_YELLOW)

                current_row_idx := Objects[0].stats_player.row_current
                for i := 0; i < CARDS_PER_ROW; i+=1  {
                    card := &GameState.rows[current_row_idx].cards[i]

                    card.visual.dest = Rectangle{
                        f32(40 * (i + 1) - 6),
                        GameData.internal_res.y / 2 + 28,
                        12, 16
                    }

                    DrawRectangleRec(card.visual.dest, card.visual.color)
                }

                for row_idx := current_row_idx + 1; row_idx < ROWS; row_idx += 1 {
                    for card_idx := 0; card_idx < CARDS_PER_ROW; card_idx += 1  {
                        card := &GameState.rows[row_idx].cards[card_idx]

                        card.visual.dest = Rectangle{
                            f32(40 * (card_idx + 1) - 6),
                            f32(100) - f32((row_idx - current_row_idx) * 24),
                            12, 16
                        }

                        DrawRectangleRec(card.visual.dest, card.visual.color)
                    }
                }

                {
                    sel := GameState.rows[current_row_idx].cards[GameState.card_selected_idx]
                    DrawRectangleLines(
                        i32(sel.visual.dest.x), i32(sel.visual.dest.y),
                        i32(sel.visual.dest.width), i32(sel.visual.dest.height),
                        C_PURPLE
                    )
                }

                y_pos := i32(GameData.internal_res.y - 15)
                text_offset : i32 = 2
                DrawRectangle(0, y_pos, w, 20, C_PURPLE)

                DrawText(TextFormat("HP: %i", Objects[0].stats_player.hp),
                    i32(GameData.internal_res.x - 150),
                    y_pos + text_offset,
                    2, C_ORANGE)
                DrawText(TextFormat("/%i", Objects[0].stats_player.max_hp),
                    i32(GameData.internal_res.x - 120),
                    y_pos + text_offset,
                    2, C_ORANGE)
                DrawText(TextFormat("GOLD: %i", Objects[0].stats_player.gold),
                    i32(GameData.internal_res.x - 50),
                    y_pos + text_offset,
                    2, C_YELLOW)

                DrawRectangleRec(Objects[0].visual.dest, Objects[0].visual.color)
            }
        case .VICTORY:
            {
                ClearBackground(C_YELLOW)

                // Title
                t := "YOU SURVIVED!"
                tsz : i32 = 8
                tw  := MeasureText(clone_to_cstring(t, context.temp_allocator), tsz)
                DrawText(clone_to_cstring(t, context.temp_allocator),
                    w/2 - tw/2, 12,
                    tsz, C_PURPLE)

                // Stats
                font_sz  : i32 = 2
                line_gap : i32 = 20
                y0       : i32 = 48

                row_text    := TextFormat("You cleared Row %d!",
                    Objects[0].stats_player.row_current + 1)
                gold_text   := TextFormat("Final Gold: %d",
                    Objects[0].stats_player.gold)
                restart_txt := "Press R to Restart"

                DrawText(row_text,
                    20, y0,
                    font_sz, C_PURPLE)

                DrawText(gold_text,
                    20, y0 + line_gap,
                    font_sz, C_PURPLE)

                DrawText(clone_to_cstring(restart_txt, context.temp_allocator),
                    20, y0 + 2*line_gap,
                    font_sz, C_PURPLE)

                // Footer
                DrawText("ESC: MAIN MENU",
                    6, h - 14,
                    2, C_PURPLE)
            }
        case .DEFEAT:
            {
                ClearBackground(C_PURPLE)

                // Title
                t := "YOU DIED!"
                tsz : i32 = 20
                tw  := MeasureText(clone_to_cstring(t, context.temp_allocator), tsz)
                DrawText(clone_to_cstring(t, context.temp_allocator),
                    w / 2 - tw / 2, 35,
                    tsz, C_ORANGE)

                // Options
                font_sz : i32 = 2
                y0      : i32 = 72
                gap     : i32 = 22
                sel     := &GameState.selected_menu_btn

                for i in 0..<len(defeat_menu_options) {
                    label := defeat_menu_options[i]
                    tw := MeasureText(clone_to_cstring(label, context.temp_allocator), font_sz)

                    bx := w/2 - (tw/2) - 6
                    by := y0 + i32(i) * gap - 4
                    bw := tw + 12
                    bh := font_sz + 16
                    active := i == sel^

                    DrawRectangleLines(bx, by, bw, bh,C_ORANGE)
                    if active {
                        DrawRectangle(bx, by, bw, bh, C_GREEN)
                        DrawText(clone_to_cstring(label, context.temp_allocator),
                            bx+6, by+4,
                            font_sz, C_YELLOW)
                    } else {
                        DrawText(clone_to_cstring(label, context.temp_allocator),
                            w/2 - tw/2, y0 + i32(i)*gap,
                            font_sz, C_YELLOW)
                    }
                }

                // Footer
                DrawText("ENTER: CONFIRM ESC: MAIN MENU",
                    6, h-14,
                    2, C_YELLOW)
            }
        case .HOW_TO_PLAY:
            {
                ClearBackground(C_YELLOW)
                w := i32(GameData.internal_res.x)
                h := i32(GameData.internal_res.y)

                // Title bar
                DrawRectangle(0, 0, w, 20, C_PURPLE)
                DrawText("HOW TO PLAY", center_x(w, "HOW TO PLAY", 8), 5, 2, C_YELLOW)

                x : i32 = 2
                y : i32 = 28
                fs : i32 = 2   // font size
                lh : i32 = 8  // line height
                ls : i32 = 4   // line spacing

                DrawText("1)Pick ONE of 3 cards each row", x, y, fs, C_PURPLE)
                y += lh
                DrawText("  - Enemy: Lose HP, gain Gold",  x, y, fs, C_PURPLE)
                y += lh
                DrawText("  - Potion: Heal HP",            x, y, fs, C_PURPLE)
                y += lh
                DrawText("  - Treasure: Gain Gold",        x, y, fs, C_PURPLE)
                y += lh
                y += ls

                DrawText("2)Dice of Fate after each pick:", x, y, fs, C_PURPLE)
                y += lh
                DrawText("  - 1 = Unlucky (bad twist)",     x, y, fs, C_PURPLE)
                y += lh
                DrawText("  - 6 = Lucky (big bonus)",       x, y, fs, C_PURPLE)
                y += lh
                DrawText("  - 2-5 = Normal",                x, y, fs, C_PURPLE)
                y += lh
                y += ls

                DrawText("3)Survive to ROW 13.",            x, y, fs, C_PURPLE)
                y += lh
                DrawText("  - On row 13: all rolls = 1.",     x, y, fs, C_PURPLE)
                y += lh

                // Dice
                dice_offset :i32 = 26
                DrawRectangle(w - 24, h - dice_offset, 12, 12, C_ORANGE)
                DrawText("1", w - 21, h - dice_offset, fs, C_YELLOW)
                DrawRectangle(8, h - dice_offset, 10, 12, C_GREEN)
                DrawText("6", 11, h - dice_offset, fs, C_YELLOW)

                // Footer hint
                DrawText("ENTER/ESC: Back", 6, h - 14, 6, C_PURPLE)
            }
        }

        // constant title
        DrawRectangle(0, 0, w, 20, C_PURPLE)
        {
            DrawText("UNLUCKY FORWARD",
                 center_x(w, "UNLUCKY FORWARD", 2),
                 5,
                 2, C_YELLOW)
        }
        // --
    EndTextureMode()

    BeginDrawing()
        src := Rectangle{
            0, 0,
            f32(GameData.internal_res.x),
            -f32(GameData.internal_res.y),
        }
        dst := Rectangle{
            0, 0,
            f32(GameData.scaled_res.x),
            f32(GameData.scaled_res.y),
        }
        origin := Vector2{ 0, 0 }

        DrawTexturePro(GameData.rt.texture, src, dst, origin, 0.0, WHITE)
    EndDrawing()
}

/////////////////////////////////////////////////////////////////////
// Free the memory that has been dynamically allocated by the program
/////////////////////////////////////////////////////////////////////
free_resources :: proc() {
}

/////////////////////////////////////////////////////////////////////
main :: proc() {
  track: mem.Tracking_Allocator
  mem.tracking_allocator_init(&track, context.allocator)
  defer mem.tracking_allocator_destroy(&track)

  context.allocator = mem.tracking_allocator(&track)

  defer {
    for _, leak in track.allocation_map {
      fmt.printf("%v leaked %m\n", leak.location, leak.size)
    }
    for bad_free in track.bad_free_array {
      fmt.printf(
        "%v allocation %p was freed badly\n",
        bad_free.location,
        bad_free.memory,
      )
    }
  }

  /////////////////////////////////////////////////////////

  window_setup()

  game_setup()

  for !rl.WindowShouldClose() {
    process_input()
    update()
    render()

    free_all(context.temp_allocator)
  }

  free_resources()

  rl.CloseWindow()
}
