-- Jimbo's Data - Joker Tracker

local csv_path_root = "Mods/jimbos-data-logs"
local dataset = "Joker"
local previous_jokers = {}
local tracked_jokers = {}
local joker_counter = 0
local total_joker_counter = 0
local joker_change_context = nil

-- Utilities to get file name and structure
local function get_date_suffix()
    local t = os.date("*t")
    return string.format("%04d-%02d", t.year, t.month)
end

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

local function ensure_dir(path)
    if not love.filesystem.getInfo(path) then
        love.filesystem.createDirectory(path)
    end
end

local function ensure_folders(profile, dataset)
    local profile_dir = csv_path_root .. "/" .. profile
    local dataset_dir = profile_dir .. "/" .. dataset
    ensure_dir(csv_path_root)
    ensure_dir(profile_dir)
    ensure_dir(dataset_dir)
    return dataset_dir
end

-- Get run info to create a key that can be used to combine data sources
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

-- write the joker actions to a CSV
local function write_joker_csv(joker_data)
    local run_info = get_run_info()
    local dataset_dir = ensure_folders(run_info.profile,dataset)
    local filename = string.format("%s/%s_%s.csv", dataset_dir, dataset, get_date_suffix())
    local existing = love.filesystem.read(filename)
    local needs_header = existing == nil or not existing:find("run_id,run_joker_id,joker_first_available,joker_last_available,joker_in_run,joker_name,joker_change,joker_change_cause,joker_sticker,joker_edition,cost,selling_effect,event_tmst", 1, true)

    local row = string.format(
        "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
        run_info.run_id,
        joker_data.run_joker_id,
        joker_data.joker_first_available,
        joker_data.joker_last_available,
        joker_data.joker_in_run,
        joker_data.joker_name,
        joker_data.joker_change,
        joker_data.joker_change_cause,
        joker_data.joker_sticker,
        joker_data.joker_edition,
        joker_data.cost,
        joker_data.selling_effect,
        os.date("!%Y-%m-%dT%H:%M:%SZ")
    )

    if needs_header then
        love.filesystem.write(filename,
            "run_id,run_joker_id,joker_first_available,joker_last_available,joker_in_run,joker_name,joker_change,joker_change_cause,joker_sticker,joker_edition,cost,selling_effect,event_tmst\n" .. row)
    else
        love.filesystem.append(filename, row)
    end
end

-- get joker sticker information
local function get_joker_sticker(joker)
    if joker.ability then
        if joker.ability.eternal then return "eternal" end
        if joker.ability.perishable then return "perishable" end
        if joker.ability.rental then return "rental" end
    end
    return "None"
end

-- identify why/where the joker was changed
-- todo: may need more clarification or a different name
function get_joker_change_cause()
    local state = G.STATE
    local cause = "unknown"

    if state == G.STATES.SHOP then
        cause = "shop"
    elseif state == G.STATES.SPECTRAL_PACK then
        cause = "riff-raff"
    elseif state == G.STATES.TAROT_PACK then
        cause = "tarot"
    elseif state == G.STATES.PLANET_PACK then
        cause = "planet"
    elseif state == G.STATES.BUFFOON_PACK then
        cause = "buffoon"
    elseif state == G.STATES.NEW_ROUND then
        if G.GAME and G.GAME.current_round and G.GAME.current_round.boss_reward_joker then
            cause = "boss_reward"
        else
            cause = "new_round"
        end
    elseif state == G.STATES.ROUND_EVAL then
        cause = "round_end"
    elseif state == G.STATES.HAND_PLAYED or state == G.STATES.SELECTING_HAND then
        cause = "played_round"
    elseif state == G.STATES.BLIND_SELECT then
        cause = "blind_select"
    elseif state == G.STATES.GAME_OVER then
        cause = "run_end"
    elseif state == G.STATES.SANDBOX then
        cause = "sandbox"
    elseif state == 999 then
        cause = "booster"
    else 
        print("Unknown state: " .. tostring(state))
        cause = "unknown"
    end

    return cause
end

-- get pertinent joker information
local function snapshot_jokers()
    local snapshot = {}
    for i, joker in ipairs(G.jokers.cards or {}) do
        if joker and joker.config then

            local center_key = joker.config.center_key
            local joker_name = G.P_CENTERS[center_key] and G.P_CENTERS[center_key].name or "unknown"
            local joker_id = tostring(joker)

            snapshot[i] = {
                id = joker_id,
                key = center_key,
                name = joker_name,
                edition = joker.edition and joker.edition.type or "None",
                sticker = get_joker_sticker(joker),
                buy_cost = joker.cost,
                sell_cost = joker.sell_cost,
                selling_effect = joker.selling_effect or "None"
            }
        end
    end
    return snapshot
end

-- identify any joker changes
local function joker_changed(prev, curr)
    return prev.name ~= curr.name or prev.edition ~= curr.edition or prev.sticker ~= curr.sticker or prev.sell_cost ~= curr.sell_cost
end

-- function to combine all the joker functions together for one row in the CSV

--todo: test duplicate of the same joker
--todo: selling effect (ex diet cola)
--todo: tie joker_in_run to the original joker_in_run if any modifications or sell/destory
--todo: identify states for riff-raff
--todo: identify cause for judgement (will have when used)
--todo: identify cause for joker destruction (ex gros michel)
function update_joker_tracker()
    if not G or not G.jokers or not G.jokers.cards then return end
    local current = snapshot_jokers()
    local prev_by_id = {}
    local curr_by_id = {}
    local run_info = get_run_info()
    local change_cause = get_joker_change_cause()

    for _, prev in ipairs(previous_jokers or {}) do
        if prev.id then
            prev_by_id[prev.id] = prev
        end
    end
    for _, cur in ipairs(current or {}) do
        if cur.id then
            curr_by_id[cur.id] = cur
        end
    end

    for i, cur in ipairs(current) do
        local prev = tracked_jokers[cur.id]
        if not prev then
            joker_counter = joker_counter + 1
            total_joker_counter = total_joker_counter + 1
            tracked_jokers[cur.id] = cur
            write_joker_csv({
                run_joker_id = run_info.run_id .. "-" .. joker_counter,
                joker_first_available = G.GAME.round_resets.ante .. "-" .. G.GAME.round .. "-" .. change_cause,
                joker_last_available = "",
                joker_in_run = total_joker_counter,
                joker_name = cur.name,
                joker_change = joker_change_context or "add",
                joker_change_cause = change_cause,
                joker_sticker = cur.sticker,
                joker_edition = cur.edition,
                cost = cur.buy_cost,
                selling_effect = cur.selling_effect
            })
        elseif joker_changed(prev, cur) then
            joker_counter = joker_counter + 1
            tracked_jokers[cur.id] = cur
            write_joker_csv({
                run_joker_id = run_info.run_id .. "-" .. joker_counter,
                joker_first_available = G.GAME.round_resets.ante .. "-" .. G.GAME.round .. "-" .. change_cause,
                joker_last_available = "",
                joker_in_run = i,
                joker_name = cur.name,
                joker_change = joker_change_context or "modified",
                joker_change_cause = change_cause,
                joker_sticker = cur.sticker,
                joker_edition = cur.edition,
                cost = cur.buy_cost,
                selling_effect = cur.selling_effect
            })
        end
    end

    for id, prev in pairs(tracked_jokers) do
        if not curr_by_id[id] then
            joker_counter = joker_counter + 1
            write_joker_csv({
                run_joker_id = run_info.run_id .. "-" .. joker_counter,
                joker_first_available = "",
                joker_last_available = G.GAME.round_resets.ante .. "-" .. G.GAME.round .. "-" .. change_cause,
                joker_in_run = "",
                joker_name = prev.name,
                joker_change = joker_change_context or "sold or destroyed",
                joker_change_cause = change_cause,
                joker_sticker = prev.sticker,
                joker_edition = prev.edition,
                cost = prev.sell_cost,
                selling_effect = prev.selling_effect
            })
            tracked_jokers[id] = nil
        end
    end

    previous_jokers = current
end

-- grab any jokers that are at present at the start (useful for challenges)
local original_start_run = Game.start_run
function Game:start_run(args)
    local data = original_start_run(self, args)
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        delay = 0.5,
        func = function()
            get_run_info()
            previous_jokers = snapshot_jokers()
            tracked_jokers = {}
            joker_counter = 0
            total_joker_counter = 0
            update_joker_tracker()
            return true
        end,
    }))
end

-- wrapper for buy/create/sell/destroy joker actions
local function wrap_tracker(func, cause)
    return function(self, args)
        joker_change_context = cause
        local result = func(self, args)
        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0.5,
            func = function()
                update_joker_tracker()
                joker_change_context = nil
                return true
            end,
        }))
        return result
    end
end

Card.add_to_deck = wrap_tracker(Card.add_to_deck, "add")
Card.sell_card = wrap_tracker(Card.sell_card, "sold or destroyed")
Card.remove_from_deck = wrap_tracker(Card.remove_from_deck, "sold or destroyed")
