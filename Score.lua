-- Score.lua
local jimbosdata = jimbosdata or {}
jimbosdata.tracker_helpers = jimbosdata.tracker_helpers or dofile("Mods/JimbosData/tracker_helpers.lua")
local tracker_helpers = jimbosdata.tracker_helpers

local score_data = {}

local round_dataset_name = "Round"
local hand_dataset_name = "Hand"

-- Helper for shallow copy, needed for storing last round details
local function shallow_copy(original)
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = value
    end
    return copy
end

-- Updated get_card_details for RankSuitEnhEdSeal format
function score_data.get_card_details(cards_table, is_joker_or_consumable)
    local details_array = {}
    
    local value_abbr = { ["10"] = "T", ["Jack"] = "J", ["Queen"] = "Q", ["King"] = "K", ["Ace"] = "A" }
    local suit_abbr = { ["Hearts"] = "H", ["Diamonds"] = "D", ["Clubs"] = "C", ["Spades"] = "S" }
    
    local enhancement_abbr_map = { ["Bonus Card"] = "U", ["Glass Card"] = "A", ["Gold Card"] = "D", ["Lucky Card"] = "L", ["Mult Card"] = "M", ["Steel Card"] = "Z", ["Stone Card"] = "O", ["Wild Card"] = "W" }
    local edition_abbr_map = { ["Foil"] = "F", ["Holographic"] = "H", ["Polychrome"] = "Y", ["Negative"] = "N" }

    if type(cards_table) ~= "table" then
        return "N/A"
    end
    if #cards_table == 0 then return "N/A" end

    for _, card_object in ipairs(cards_table) do
        if card_object then
            local card_str = ""

            if is_joker_or_consumable and card_object.config and card_object.config.center and card_object.config.center.name then
                card_str = card_object.config.center.name
            elseif card_object.base and card_object.base.value and card_object.base.suit then
                local val = value_abbr[card_object.base.value] or card_object.base.value
                local suit_char = suit_abbr[card_object.base.suit] or string.sub(card_object.base.suit, 1, 1)
                card_str = val .. suit_char

                if card_object.ability then
                    local enh_name = card_object.ability.name
                    if enh_name and enh_name ~= 'None' and enh_name ~= 'Default Base' then
                        card_str = card_str .. (enhancement_abbr_map[enh_name] or enh_name:sub(1,1))
                    end
                end

                if card_object.edition then
                    if card_object.edition.foil then card_str = card_str .. edition_abbr_map["Foil"]
                    elseif card_object.edition.holo then card_str = card_str .. edition_abbr_map["Holographic"]
                    elseif card_object.edition.polychrome then card_str = card_str .. edition_abbr_map["Polychrome"]
                    elseif card_object.edition.negative then card_str = card_str .. edition_abbr_map["Negative"]
                    end
                end
                
                if card_object.seal and card_object.seal ~= 'None' then
                    card_str = card_str .. string.sub(card_object.seal, 1, 1) 
                end
            else
                card_str = "???"
            end
            table.insert(details_array, card_str)
        else
            table.insert(details_array, "InvalidObj")
        end
    end
    return table.concat(details_array, ";") 
end

function score_data.get_round_data_from_cache()
    local run_info = tracker_helpers.get_run_info()
    
    return {
        run_id = run_info.run_id,
        ante = jimbosdata.prev_ante_for_log or 0,
        round = jimbosdata.prev_round_for_log or 0,
        blind_name = jimbosdata.prev_blind_name_for_log or "N/A",
        hands_played_in_round = jimbosdata.prev_hands_played_for_log or 0,
        discards_used_in_round = jimbosdata.prev_discards_used_for_log or 0,
        money = jimbosdata.prev_dollars_for_log or 0,
        score_needed = jimbosdata.prev_blind_chips_for_log or 0,
        player_score_at_log = jimbosdata.prev_player_chips_for_log or 0,
        timestamp = tracker_helpers.get_utc_timestamp()
    }
end

function score_data.write_round_csv()
    local round_info = score_data.get_round_data_from_cache()

    -- Ensure ante and round are valid numbers before proceeding
    if type(round_info.ante) ~= "number" or type(round_info.round) ~= "number" or round_info.round == 0 then
        print("⚠️ [JimbosData|Score.lua|write_round_csv] Invalid ante (" .. tostring(round_info.ante) .. ") or round (" .. tostring(round_info.round) .. "). Skipping CSV write.")
        return
    end

    -- Primary duplicate check: exact ante-round combination
    local ante_round_key = round_info.ante .. "-" .. round_info.round
    if jimbosdata.logged_ante_rounds_for_csv and jimbosdata.logged_ante_rounds_for_csv[ante_round_key] then
        return
    end

    -- Secondary duplicate check: specifically for boss blind ante transition duplicates
    if jimbosdata.last_successful_round_details_for_duplicate_check then
        local last_log = jimbosdata.last_successful_round_details_for_duplicate_check
        local is_potential_boss_duplicate = 
            round_info.run_id == last_log.run_id and
            round_info.round == last_log.round and
            round_info.blind_name == last_log.blind_name and
            round_info.blind_name ~= "N/A (Blind Object Missing)" and -- Don't apply this logic if current or last blind name is a generic N/A
            round_info.blind_name ~= "N/A (Fallback)" and
            round_info.blind_name ~= "N/A (Game Over Fallback)" and
            round_info.blind_name ~= "N/A (Name/ID Missing from Object)" and
            round_info.blind_name ~= "N/A (Name/ID Missing from Final Object)" and
            round_info.ante == (last_log.ante + 1) -- Specifically check if current ante is one greater

        if is_potential_boss_duplicate then
            return
        end
    end

    -- The old jimbosdata.last_round_logged check is now superseded by the logged_ante_rounds_for_csv table
    local run_info = tracker_helpers.get_run_info() -- Still needed for run_id in the row
    local date_suffix = tracker_helpers.get_date_suffix()
    
    local dataset_dir = tracker_helpers.ensure_folders(run_info.profile, round_dataset_name)
    local filename = string.format("%s/%s_%s.csv", dataset_dir, round_dataset_name, date_suffix)
    local header = "run_id,ante,round,blind_name,hands_played_in_round,discards_used_in_round,money,score_needed,player_score_at_log,event_tmst\n"
    local file_info = love.filesystem.getInfo(filename)
    local needs_header = not file_info or file_info.size == 0

    local row = string.format( 
        "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", 
        round_info.run_id, round_info.ante, round_info.round, round_info.blind_name,
        round_info.hands_played_in_round, round_info.discards_used_in_round, round_info.money, 
        round_info.score_needed, round_info.player_score_at_log, round_info.timestamp
    )
    if needs_header then
        love.filesystem.write(filename, header .. row)
    else
        love.filesystem.append(filename, row)
    end
    -- Mark this ante-round as logged for the current run
    if jimbosdata.logged_ante_rounds_for_csv then
        jimbosdata.logged_ante_rounds_for_csv[ante_round_key] = true
        -- Store details of this successfully logged round for the next duplicate check
        jimbosdata.last_successful_round_details_for_duplicate_check = shallow_copy(round_info)
    end
end

function score_data.get_hand_data(played_card_objects, remaining_hand_cards_objects, discarded_this_turn_details_str)
    local run_info = tracker_helpers.get_run_info()
    local current_ante = (G.GAME.round_resets and G.GAME.round_resets.ante) or G.GAME.ante or 0
    local current_round_num = G.GAME.round or 0
    
    -- G.GAME.current_round.hands_played is incremented by evaluate_play itself.
    -- So, after original_evaluate_play in the hook, this value is the number of the hand just played.
    local current_hands_played = (G.GAME.current_round and G.GAME.current_round.hands_played) or 0 

    -- If G.GAME.current_round.hands_played is 0-indexed for the *next* hand or similar,
    -- then +1 is needed to make it 1-indexed for the hand just completed.
    local hand_num_in_round_val = current_hands_played + 1
    local run_hand_id_val = string.format("%s-A%s-R%s-H%s", 
        run_info.run_id, current_ante, current_round_num, hand_num_in_round_val)

    return {
        run_id = run_info.run_id,
        run_hand_id = run_hand_id_val,
        ante = current_ante,
        round = current_round_num,
        blind_name = (G.GAME.blind and G.GAME.blind.name) or (G.GAME.last_blind and G.GAME.last_blind.name) or "N/A",
        hand_num_in_round = hand_num_in_round_val,
        poker_hand = G.GAME.current_round.current_hand.handname or "N/A",
        cards_played = score_data.get_card_details(played_card_objects, false),
        cards_discarded_this_turn = discarded_this_turn_details_str or "", 
        cards_remaining_in_hand = score_data.get_card_details(remaining_hand_cards_objects, false),
        base_chips = G.GAME.current_round.current_hand.chips or 0,
        chip_mult = G.GAME.current_round.current_hand.mult or 0,
        total_score = G.GAME.current_round.current_hand.chip_total or G.GAME.chips or 0, 
        money = G.GAME.dollars,
        timestamp = tracker_helpers.get_utc_timestamp()
    }
end

function score_data.write_hand_csv(played_card_objects, remaining_hand_cards_objects, discarded_this_turn_details_str)
    local run_info = tracker_helpers.get_run_info()
    -- Pass played_card_objects directly to get_hand_data
    local hand_info = score_data.get_hand_data(played_card_objects, remaining_hand_cards_objects, discarded_this_turn_details_str)
    local date_suffix = tracker_helpers.get_date_suffix()

    local current_hand_identifier = string.format("%s-%s-%s-%s-%s-%s", 
        run_info.run_id, hand_info.ante, hand_info.round, hand_info.hand_num_in_round, 
        hand_info.poker_hand, hand_info.total_score) -- Uses hand_num_in_round now

    if jimbosdata.last_hand_logged_identifier == current_hand_identifier then return end
    
    -- Check if played_card_objects itself is valid, not just hand_info.cards_in_played_hand string
    if not played_card_objects or #played_card_objects == 0 then
        return
    end

    local dataset_dir = tracker_helpers.ensure_folders(run_info.profile, hand_dataset_name)
    local filename = string.format("%s/%s_%s.csv", dataset_dir, hand_dataset_name, date_suffix)
    local header = "run_id,run_hand_id,ante,round,blind_name,hand_num_in_round,poker_hand,cards_played,cards_discarded_this_turn,cards_remaining_in_hand,base_chips,chip_mult,total_score,money,event_tmst\n"
    local file_info = love.filesystem.getInfo(filename)
    local needs_header = not file_info or file_info.size == 0

    local row = string.format( 
        "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", 
        hand_info.run_id, hand_info.run_hand_id, hand_info.ante, hand_info.round, hand_info.blind_name, 
        hand_info.hand_num_in_round, hand_info.poker_hand, hand_info.cards_played, 
        hand_info.cards_discarded_this_turn, hand_info.cards_remaining_in_hand, 
        hand_info.base_chips, hand_info.chip_mult, hand_info.total_score, hand_info.money, hand_info.timestamp
    )
    if needs_header then
        love.filesystem.write(filename, header .. row)
    else
        love.filesystem.append(filename, row)
    end
    jimbosdata.last_hand_logged_identifier = current_hand_identifier
end

return score_data