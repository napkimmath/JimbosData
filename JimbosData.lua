local csv_path_root = "Mods/jimbos-data-logs"
local dataset_name = "Run_Start"
local dataset_name_end = "Run_End"
local run_ended = false

-- Utility to get current date as "YYYY-MM"
-- This is used to create the filename for the CSV files
-- The date is formatted as "YYYY-MM" to group the CSV files by month and year
local function get_date_suffix()
    local t = os.date("*t")
    return string.format("%04d-%02d", t.year, t.month)
end

-- Get the user profile name so that different profiles are stored separately
local function get_profile_name()
    if G.SETTINGS then
        if G.SETTINGS.profile_name and G.SETTINGS.profile_name ~= "" then
            return G.SETTINGS.profile_name
        end
        if G.SETTINGS.profile and G.PROFILES then
            local profile_data = G.PROFILES[G.SETTINGS.profile]
            if profile_data and type(profile_data) == "table" and profile_data.name then
                return profile_data.name
            elseif type(profile_data) == "string" then
                return profile_data
            end
        end
    end
    return "profile_" .. tostring(G.PROFILE_NUMBER or "unknown")
end

-- Getting the start of the run info
-- This includes the profile name, seed, stake, and deck
local function get_run_info()
    local seed = (G.GAME.pseudorandom and G.GAME.pseudorandom.seed) or "UNKNOWN"
    local stake = SMODS.stake_from_index(G.GAME.stake) or "UNKNOWN"
    local profile_str = get_profile_name()
    local deck_str = G.GAME.selected_back.name
    local run_id = profile_str .. "_" .. seed .. "_" .. deck_str .. "_" .. stake

    return {
        run_id = run_id,
        profile = profile_str,
        seed = seed,
        stake = stake,
        deck = deck_str
    }
end

-- Getting the end of the run info
-- This includes the cards played, cards discarded, cards purchased, times rerolled,
-- new collection, furthest ante, furthest round, best hand, dollars, and won
local function get_end_run_info()
    local defeated_by = G.GAME.round_resets.blind.name or G.GAME.round_resets.blind.id

    return {
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
        defeated_by = defeated_by
    }
end

-- Ensure the directory exists
-- If it doesn't, create it
-- This is used to create the directory for the CSV files
-- The path is Mods/jimbos-data-logs/
local function ensure_dir(path)
    if not love.filesystem.getInfo(path) then
        love.filesystem.createDirectory(path)
    end
end

-- Ensure the folders for the CSV files exist
-- This is used to create the directory for the CSV files
-- The path is Mods/jimbos-data-logs/<profile>/<dataset>
-- The dataset is the name of the dataset (like Run_Start or Run_End)
local function ensure_folders(profile, dataset)
    local profile_dir = csv_path_root .. "/" .. profile
    local dataset_dir = profile_dir .. "/" .. dataset
    ensure_dir(csv_path_root)
    ensure_dir(profile_dir)
    ensure_dir(dataset_dir)
    return dataset_dir
end

-- This is used to write the run info to a CSV file
-- The path is Mods/jimbos-data-logs/<profile>/Run_Start/Run_Start_<YYYY-MM>.csv
-- The timestamp is the current date and time in UTC (when the run started)
local function write_run_csv()
    local info = get_run_info()
    local dataset_dir = ensure_folders(info.profile, dataset_name)
    local filename = string.format("%s/%s_%s.csv", dataset_dir, dataset_name, get_date_suffix())
    local existing = love.filesystem.read(filename)
    local needs_header = existing == nil or not existing:find("profile,seed,stake,deck,strt_tmst", 1, true)

    local row = string.format(
        "%s,%s,%s,%s,%s\n",
        info.profile,
        info.seed,
        info.stake,
        info.deck,
        os.date("!%Y-%m-%dT%H:%M:%SZ")
    )

    if needs_header then
        love.filesystem.write(filename, "profile,seed,stake,deck,strt_tmst\n" .. row)
    else
        love.filesystem.append(filename, row)
    end
end

-- This is used to write the end run info to a CSV file
-- The path is Mods/jimbos-data-logs/<profile>/Run_End/Run_End_<YYYY-MM>.csv
-- The timestamp is the current date and time in UTC (when the run ended)
local function write_end_run_csv()
    local info = get_run_info()
    local end_info = get_end_run_info()
    local dataset_dir_end = ensure_folders(info.profile, dataset_name_end)
    local filename_end = string.format("%s/%s_%s.csv", dataset_dir_end, dataset_name_end, get_date_suffix())
    local existing_end = love.filesystem.read(filename_end)
    local needs_header_end = existing_end == nil or not existing_end:find("run_id,end_tmst,won,best_hand,cards_played,cards_discarded,cards_purchased,times_rerolled,new_collection,furthest_ante,furthest_round,dollars,defeated_by", 1, true)

    local row_end = string.format(
        "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
        info.run_id,
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

    if needs_header_end then
        love.filesystem.write(filename_end, "run_id,end_tmst,won,best_hand,cards_played,cards_discarded,cards_purchased,times_rerolled,new_collection,furthest_ante,furthest_round,dollars,defeated_by\n" .. row_end)
    else
        love.filesystem.append(filename_end, row_end)
    end
end

-- Hook into Game:start_run
-- This is called when the game starts a new run
-- It captures the run info and writes it to a CSV file
-- The path is Mods/jimbos-data-logs/<profile>/Run_Start/Run_Start_<YYYY-MM>.csv
local original_start_run = Game.start_run
function Game:start_run(args)
    local data = original_start_run(self, args)
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay = 0.5,
        func = function()
            print("📦 Jimbo's Data: capturing beginning run info...")
            write_run_csv()
	    return true
        end,
    }))
    run_ended = false
end

-- Hook into Game:update_game_over
-- This is called when the game ends
-- It captures the end run info and writes it to a CSV file
-- The path is Mods/jimbos-data-logs/<profile>/Run_End/Run_End_<YYYY-MM>.csv
local original_end_run = Game.update_game_over
function Game:update_game_over(dt)
    if not run_ended then
        print("🎯 Jimbo's Data: detected end screen, capturing end run")
        local data = original_end_run(self, dt)

        G.E_MANAGER:add_event(Event({
            trigger = 'immediate',
            delay = 0,
            func = function()
                write_end_run_csv()
                return true
            end,
        }))
        run_ended = true
    end
end
