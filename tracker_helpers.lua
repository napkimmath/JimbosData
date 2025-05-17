-- tracker_helpers.lua
local tracker_helpers = {}

-- Root path for log storage, relative to the game's installation/mods directory
tracker_helpers.csv_path_root = "Mods/jimbos-data-logs"

-- Get formatted date string for file naming (YYYY-MM)
function tracker_helpers.get_date_suffix()
    local t = os.date("*t")
    return string.format("%04d-%02d", t.year, t.month)
end

-- Get current UTC timestamp
function tracker_helpers.get_utc_timestamp()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- Get the active profile name
function tracker_helpers.get_profile_name()
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

-- Run identifier used to link all events in the same run
function tracker_helpers.get_run_info()
    local seed = (G.GAME.pseudorandom and G.GAME.pseudorandom.seed) or "UNKNOWN"
    local stake = SMODS.stake_from_index(G.GAME.stake) or "UNKNOWN"
    local profile_str = tracker_helpers.get_profile_name()
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

function tracker_helpers.get_round_info()
    local ante = G.GAME.round_resets.ante
    local round = G.GAME.round
    --local blind = G.GAME.round_resets.blind.name or G.GAME.round_resets.blind.id

    return {
        current_ante = ante,
        current_round = round--,
        --current_blind = blind    
    }
end

-- Make sure a directory exists
function tracker_helpers.ensure_dir(path)
    if not love.filesystem.getInfo(path) then
        love.filesystem.createDirectory(path)
    end
end

-- Create profile- and dataset-specific folders
function tracker_helpers.ensure_folders(profile, dataset)
    local profile_dir = tracker_helpers.csv_path_root .. "/" .. profile
    local dataset_dir = profile_dir .. "/" .. dataset
    tracker_helpers.ensure_dir(tracker_helpers.csv_path_root)
    tracker_helpers.ensure_dir(profile_dir)
    tracker_helpers.ensure_dir(dataset_dir)
    return dataset_dir
end

-- Get detailed information about a card object
-- Expected by ConsumableTracker for shop items, consumables, etc.
function tracker_helpers.get_card_details(card_obj)
    if not card_obj or not card_obj.config or not card_obj.config.center_key then
        -- This block handles cards that might not have a center_key, primarily standard playing cards.
        -- Also handles if card_obj itself is nil.
        if not card_obj then
            return { name = "Nil Card Object", type = "Unknown", cost = 0, unique_game_id = "nil_card_obj" }
        end

        -- Fallback for playing cards if they don't use center_key
        -- This should be the primary path for standard playing cards.
        if card_obj and card_obj.base and card_obj.base.value and card_obj.base.suit then
            local value_abbr = { ["10"] = "T", ["Jack"] = "J", ["Queen"] = "Q", ["King"] = "K", ["Ace"] = "A" }
            local suit_abbr = { ["Hearts"] = "H", ["Diamonds"] = "D", ["Clubs"] = "C", ["Spades"] = "S" }
            local val = value_abbr[card_obj.base.value] or card_obj.base.value
            local suit_char = suit_abbr[card_obj.base.suit] or string.sub(card_obj.base.suit, 1, 1)
            
            local details = {
                name = val .. suit_char,
                type = "Playing Card",
                cost = card_obj.cost or 0,
                unique_game_id = tostring(card_obj),
                edition = card_obj.edition and card_obj.edition.type or "None",
                enhancement = card_obj.ability and card_obj.ability.name or "None",
                seal = card_obj.seal or "None",
                sticker = "None",
                suit = card_obj.base.suit,
                rank = card_obj.base.value,
                value_chips_add = card_obj.PLUS_CHIPS or 0,
                value_mult_add = card_obj.PLUS_MULT or 0
            }
            return details -- Ensure playing card details are returned
        end
        -- If it's not a standard playing card and has no center_key
        return { name = "Unknown Card", type = "Unknown", cost = 0, unique_game_id = tostring(card_obj) }
    end
    
    -- Some playing cards might have a center_key (e.g., 'c_base') AND base properties. Prioritize base properties for them.
    if card_obj and card_obj.base and card_obj.base.value and card_obj.base.suit then
        local value_abbr = { ["10"] = "T", ["Jack"] = "J", ["Queen"] = "Q", ["King"] = "K", ["Ace"] = "A" }
        local suit_abbr = { ["Hearts"] = "H", ["Diamonds"] = "D", ["Clubs"] = "C", ["Spades"] = "S" }
        local val = value_abbr[card_obj.base.value] or card_obj.base.value
        local suit_char = suit_abbr[card_obj.base.suit] or string.sub(card_obj.base.suit, 1, 1)
        local details = {
            name = val .. suit_char, type = "Playing Card", cost = card_obj.cost or 0,
            unique_game_id = tostring(card_obj), edition = card_obj.edition and card_obj.edition.type or "None",
            enhancement = card_obj.ability and card_obj.ability.name or "None", seal = card_obj.seal or "None",
            value_chips_add = card_obj.PLUS_CHIPS or 0, value_mult_add = card_obj.PLUS_MULT or 0,
            sticker = "None", suit = card_obj.base.suit, rank = card_obj.base.value
        }
        return details -- Ensure these details are returned
    end

    -- Proceed with center_config lookup for cards identified primarily by center_key
    local center_config = G.P_CENTERS[card_obj.config.center_key] or G.C_CENTERS[card_obj.config.center_key]
    if not center_config then
        return { name = "Unknown Center Key: " .. card_obj.config.center_key, type = "Unknown", cost = card_obj.cost or 0, unique_game_id = tostring(card_obj) }
    end

    local card_type = "Unknown"
    if center_config.set == "Joker" then card_type = "Joker"
    elseif center_config.set == "Tarot" then card_type = "Tarot"
    elseif center_config.set == "Planet" then card_type = "Planet"
    elseif center_config.set == "Spectral" then card_type = "Spectral"
    elseif center_config.set == "Voucher" then card_type = "Voucher"
    elseif center_config.set == "PlayingCard" or (card_obj.type and card_obj.type == 'PlayingCard') then card_type = "Playing Card"
    elseif center_config.set == "Booster" then card_type = "BoosterPack"
    end
    
    local details = {
        name = center_config.name or "Unnamed Card",
        type = card_type,
        cost = card_obj.cost or (center_config.cost ~= nil and center_config.cost) or 0,
        unique_game_id = tostring(card_obj),
        edition = card_obj.edition and card_obj.edition.type or "None",
        enhancement = card_obj.ability and card_obj.ability.name or "None",
        seal = card_obj.seal or "None",
        sticker = (card_type == "Joker" and jimbosdata.ConsumableTracker and jimbosdata.ConsumableTracker.get_joker_sticker and jimbosdata.ConsumableTracker.get_joker_sticker(card_obj)) or "None",
        item_subtype = (card_type == "BoosterPack" and card_obj.booster_pack_type) or (center_config.set or "N/A") -- For shop, to distinguish consumable types or pack types
    }
    if card_obj.PLUS_CHIPS then details.value_chips_add = card_obj.PLUS_CHIPS end
    if card_obj.PLUS_MULT then details.value_mult_add = card_obj.PLUS_MULT end
    return details -- Crucial: ensure this path also returns the created details
end

-- Get the display name of a poker hand from its key
function tracker_helpers.get_poker_hand_name_from_key(key)
    -- Check if the key is an internal ID in G.P_HAND_GROUPS that has a 'name' attribute
    if G.P_HAND_GROUPS and G.P_HAND_GROUPS[key] and G.P_HAND_GROUPS[key].name then
        return G.P_HAND_GROUPS[key].name
    end
    -- If not found, or if the key itself is already the display name (like "Five of a Kind"),
    -- return the key as is.
    return key
end

return tracker_helpers