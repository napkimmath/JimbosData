-- Global Variables/Functions loaded here
local jimbosdata = jimbosdata or {}
jimbosdata.tracker_helpers = jimbosdata.tracker_helpers or dofile("Mods/JimbosData/tracker_helpers.lua")
local tracker_helpers = jimbosdata.tracker_helpers

-- Local Variables specific to run start and end files is loaded here
local jimbos_data = {}
local run_info = tracker_helpers.get_run_info()
local get_date_suffix = tracker_helpers.get_date_suffix()

local dataset_name = "Run_Start"
local dataset_name_end = "Run_End"


-- Getting the end of the run info
-- This includes the cards played, cards discarded, cards purchased, times rerolled,
-- new collection, furthest ante, furthest round, best hand, dollars, and won
function jimbos_data.get_end_run_info()
    local defeated_by = G.GAME.round_resets.blind.name or G.GAME.round_resets.blind.id
    local current_run_id_val = (jimbosdata.ConsumableTracker and jimbosdata.ConsumableTracker.run_info_snapshot and jimbosdata.ConsumableTracker.run_info_snapshot.run_id) or
                               (tracker_helpers and tracker_helpers.get_run_info().run_id) or
                               "UNKNOWN_RUN_ID" -- Fallback

    local defeated_by_val
    local current_ante = G.GAME.ante or (G.GAME.round_resets and G.GAME.round_resets.ante) or 0
    -- G.GAME.round is the round number *within* the current ante.
    -- For checking if we are past Ante 8, G.GAME.ante is more direct.
    local rounds_per_ante = 3 -- Default value
    if G.GAME.config and G.GAME.config.rounds_per_ante then
        rounds_per_ante = G.GAME.config.rounds_per_ante
    end


    if G.GAME.won == true then
        -- Check if we are beyond the standard Ante 8 completion
        if current_ante > 8 then
            -- This means we are in Endless mode, and G.GAME.won is still true from the initial Ante 8 win.
            -- The 'defeated_by' should be the blind that ended the endless run.
            defeated_by_val = (G.GAME.blind and G.GAME.blind.name) or
                              (G.GAME.last_blind and G.GAME.last_blind.name) or
                              (G.GAME.round_resets and G.GAME.round_resets.blind and G.GAME.round_resets.blind.name) or
                              "Endless"
        else
            -- This is the actual Ante 8 win moment (or very close to it, ante hasn't advanced past 8).
            if G.GAME.last_blind and G.GAME.last_blind.name then -- last_blind should be the Ante 8 boss
                defeated_by_val = G.GAME.last_blind.name .. " (Ante 8 Win)"
            else
                defeated_by_val = "Ante 8 Boss (Win)"
            end
        end
    else
        -- Standard loss condition (before Ante 8 or if G.GAME.won was somehow false in endless)
        defeated_by_val = (G.GAME.blind and G.GAME.blind.name) or
                          (G.GAME.last_blind and G.GAME.last_blind.name) or
                          (G.GAME.round_resets and G.GAME.round_resets.blind and G.GAME.round_resets.blind.name) or
                          "Unknown"
    end

    return {
        run_id = current_run_id_val,
        cards_played = G.GAME.round_scores["cards_played"].amt,
        cards_discarded = G.GAME.round_scores["cards_discarded"].amt,
        cards_purchased = G.GAME.round_scores["cards_purchased"].amt,
        times_rerolled = G.GAME.round_scores["times_rerolled"].amt,
        new_collection = G.GAME.round_scores["new_collection"].amt,
        furthest_ante = G.GAME.round_scores["furthest_ante"].amt,
        furthest_round = G.GAME.round_scores["furthest_round"].amt,
        best_hand = G.GAME.round_scores["hand"].amt,
        --most_played_poker_hand = G.GAME.current_round.most_played_poker_hand,
        --most_played_poker_hand_times = G.GAME.round_scores["poker_hand"].amt,
	    dollars = G.GAME.dollars,
	    won = G.GAME.won,
        defeated_by = defeated_by_val
    }
end

-- This is used to write the run info to a CSV file
-- The path is Mods/jimbos-data-logs/<profile>/Run_Start/Run_Start_<YYYY-MM>.csv
-- The timestamp is the current date and time in UTC (when the run started)
function jimbos_data.write_run_csv()
    local dataset_dir = tracker_helpers.ensure_folders(run_info.profile, dataset_name)
    local filename = string.format("%s/%s_%s.csv", dataset_dir, dataset_name, get_date_suffix)
    local file_info = love.filesystem.getInfo(filename)
    local needs_header = not file_info or file_info.size == 0
    
    local row = string.format(
        "%s,%s,%s,%s,%s\n",
        run_info.profile,
        run_info.seed,
        run_info.stake,
        run_info.deck,
        os.date("!%Y-%m-%dT%H:%M:%SZ")
    )

    local success, err_msg
    if needs_header then
        local header_content = "profile,seed,stake,deck,strt_tmst\n"
        success, err_msg = love.filesystem.write(filename, header_content .. row)
    else
        success, err_msg = love.filesystem.append(filename, row)
    end

    if not success then
        print(string.format("🚨 [JimbosData] Error writing Run Start CSV to %s: %s", filename, err_msg or "Unknown error"))
    end
end

-- This is used to write the end run info to a CSV file
-- The path is Mods/jimbos-data-logs/<profile>/Run_End/Run_End_<YYYY-MM>.csv
-- The timestamp is the current date and time in UTC (when the run ended)
function jimbos_data.write_end_run_csv()
    local end_info = jimbos_data.get_end_run_info()
    local dataset_dir_end = tracker_helpers.ensure_folders(run_info.profile, dataset_name_end)
    local filename_end = string.format("%s/%s_%s.csv", dataset_dir_end, dataset_name_end, get_date_suffix)
    local file_info_end = love.filesystem.getInfo(filename_end)
    local needs_header_end = not file_info_end or file_info_end.size == 0
    
    local row_end = string.format(
        "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
        end_info.run_id, -- Use run_id from end_info
        os.date("!%Y-%m-%dT%H:%M:%SZ"),
        end_info.won,
        end_info.best_hand,
        --end_info.most_played_poker_hand,
        --end_info.most_played_poker_hand_times,
        end_info.cards_played,
        end_info.cards_discarded,
        end_info.cards_purchased,
        end_info.times_rerolled,
        end_info.new_collection,
        end_info.furthest_ante,
        end_info.furthest_round,
	    end_info.dollars,
        end_info.defeated_by
    )

    local success, err_msg
    if needs_header_end then
        local header_content_end = "run_id,end_tmst,won,best_hand,cards_played,cards_discarded,cards_purchased,times_rerolled,new_collection,furthest_ante,furthest_round,dollars,defeated_by\n"
        success, err_msg = love.filesystem.write(filename_end, header_content_end .. row_end)
    else
        success, err_msg = love.filesystem.append(filename_end, row_end)
    end

    if not success then
        print(string.format("🚨 [JimbosData] Error writing Run End CSV to %s: %s", filename_end, err_msg or "Unknown error"))
    end
end

return jimbos_data