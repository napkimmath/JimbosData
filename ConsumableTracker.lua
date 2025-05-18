-- ConsumableTracker.lua
-- Unified tracker for Jokers, Shop items, Consumables, Playing Cards, and Poker Hands

-- Singleton Guard: If the main ConsumableTracker instance already exists 
-- in the global jimbosdata table and is properly marked, return it. 
-- This prevents re-execution of the entire file and resetting of its state 
-- (like counters) if dofile() is called multiple times on this file.
if _G.jimbosdata and _G.jimbosdata.ConsumableTracker and _G.jimbosdata.ConsumableTracker._isJimbosConsumableTracker_Marker then
    return _G.jimbosdata.ConsumableTracker
end

-- Global Variables/Functions loaded here
local jimbosdata = jimbosdata or {}
jimbosdata.tracker_helpers = jimbosdata.tracker_helpers or dofile("Mods/JimbosData/tracker_helpers.lua")
local tracker_helpers = jimbosdata.tracker_helpers

-- Function to get current blind, ante, and round consistently
local function getCurrentRunContext()
    local round_info = tracker_helpers.get_round_info() -- Call it each time to get fresh ante/round
    return round_info.current_ante, round_info.current_round
end


local ConsumableTracker = {
    run_info_snapshot = nil, -- Will be set by initialize_run_trackers
    _isJimbosConsumableTracker_Marker = true, -- Marker to identify this specific table structure as fully initialized by this script.

    -- Joker Tracking
    previous_jokers = {},
    tracked_jokers = {},
    joker_counter = 0,       -- Counter for unique joker events within a run
    joker_change_context = nil, -- Stores context like "add", "sold or destroyed"

    -- Shop Tracking
    -- shop_instance_counter is used for unique shop view instances (rerolls, initial)
    shop_instance_counter = 0, -- Increments for each new shop view (initial, reroll)
    current_shop_items = {},   -- Stores details of items currently in shop { slot = item_details }
    
    -- Consumable Tracking (Tarot, Planet, Spectral, Voucher)
    consumable_instance_counter = 0,
    tracked_consumables = {}, -- Stores active consumables { instance_id = consumable_data }

    -- Poker Hand Level Tracking
    previous_poker_hand_levels = {},
    poker_hand_event_counter = 0, -- Counter for unique poker hand level change events

    -- Playing Card Tracking
    playing_card_instance_counter = 0,
    tracked_playing_cards = {}, -- { game_object_id_string = {our_instance_id, last_known_state} }
                                -- This helps in assigning a persistent mod-specific ID

    -- Persistent Counters for unique ID (UID) generation across events for the same item instance
    total_joker_counter = 0,       -- For joker_in_run_uid (J_#)
    total_consumable_counter = 0,  -- For consumable_in_run_uid (C_#)
    total_playing_card_counter = 0,-- For card_in_run_uid (PC_#)
    total_poker_hand_counter = 0,-- For poker_hand_in_run_uid (PH_#) (may not be needed since poker hands are consistent)
    
    -- Dataset Names
    joker_dataset = "Joker",
    shop_dataset = "Shop",
    consumable_dataset = "Consumable",
    poker_hand_level_dataset = "Poker_Hand_Level",
    playing_card_dataset = "Playing_Card"
}

-- =================================================================================
-- INITIALIZATION (Called at the start of each run)
-- =================================================================================
function ConsumableTracker.initialize_run_trackers()
    ConsumableTracker.run_info_snapshot = tracker_helpers.get_run_info() -- Get fresh info for the current run
    print("🔧 [JimbosData] Initializing ConsumableTracker for new run: " .. (ConsumableTracker.run_info_snapshot and ConsumableTracker.run_info_snapshot.run_id or "UNKNOWN_RUN_ID"))
    local run_id = ConsumableTracker.run_info_snapshot.run_id
    local current_ante, current_round = getCurrentRunContext()

    -- Reset Joker trackers
    ConsumableTracker.previous_jokers = ConsumableTracker.snapshot_jokers()
    ConsumableTracker.tracked_jokers = {}
    ConsumableTracker.joker_counter = 0
    ConsumableTracker.total_joker_counter = 0
    ConsumableTracker.joker_change_context = nil
    ConsumableTracker.update_joker_tracker("run_start") -- Log initial jokers if any (from challenges)

    -- Reset Shop trackers
    ConsumableTracker.shop_instance_counter = 0
    ConsumableTracker.current_shop_items = {}

    -- Reset Consumable trackers
    ConsumableTracker.poker_hand_event_counter = 0
    ConsumableTracker.consumable_instance_counter = 0
    ConsumableTracker.total_consumable_counter = 0 -- Reset persistent counter for the new run
    ConsumableTracker.tracked_consumables = {}
    -- Initial consumables (from deck ability, etc.) will be logged by update_consumable_tracker_for_all_held called in init.lua

    -- Reset Poker Hand Level trackers
    ConsumableTracker.previous_poker_hand_levels = ConsumableTracker.snapshot_poker_hand_levels()
    ConsumableTracker.update_poker_hand_level_tracker("run_start") -- Log initial levels

    -- Reset Playing Card trackers
    ConsumableTracker.playing_card_instance_counter = 0
    ConsumableTracker.total_playing_card_counter = 0 -- Reset persistent counter BEFORE logging initial deck
    ConsumableTracker.tracked_playing_cards = {}
    ConsumableTracker.log_initial_deck_playing_cards() -- Log starting deck
    print("🔧 [JimbosData] ConsumableTracker initialized.")
end


-- =================================================================================
-- JOKER TRACKING
-- =================================================================================

-- get joker sticker information
function ConsumableTracker.get_joker_sticker(joker)
    if joker.ability then
        if joker.ability.eternal then return "eternal" end
        if joker.ability.perishable then return "perishable" end
        if joker.ability.rental then return "rental" end
    end
    return ""
end

function ConsumableTracker.determine_event_location(hint)
    if hint then return hint end -- Prioritize explicit hint if it exists (like from riff-raff)

    local state = G.STATE
    local where_cause = "unknown"
    
    if state == G.STATES.SHOP then
        where_cause = "shop"
    elseif state == G.STATES.SPECTRAL_PACK then
        where_cause = "spectral pack"
    elseif state == G.STATES.TAROT_PACK then
        where_cause = "tarot pack"
    elseif state == G.STATES.PLANET_PACK then
        where_cause = "planet pack"
    elseif state == G.STATES.BUFFOON_PACK then
        where_cause = "buffoon pack"
    elseif state == G.STATES.NEW_ROUND then
        if G.GAME and G.GAME.current_round and G.GAME.current_round.boss_reward_joker then
            where_cause = "boss_reward"
        else
            where_cause = "new_round"
        end
    elseif state == G.STATES.ROUND_EVAL then
        where_cause = "round_end"
    elseif state == G.STATES.HAND_PLAYED or state == G.STATES.SELECTING_HAND then
        where_cause = "played_round"
    elseif state == G.STATES.BLIND_SELECT then
        where_cause = "blind_select"
    elseif state == G.STATES.GAME_OVER then
        where_cause = "run_end"
    elseif state == G.STATES.SANDBOX then
        where_cause = "sandbox"
    elseif state == 999 then
        where_cause = "booster"
    elseif state == 3 then
        where_cause = "round_start"
    elseif state == 6 then
        where_cause = "consumable_used"
    else 
        print("Unknown state: " .. tostring(state))
        where_cause = "unknown"
    end
    return where_cause
end

function ConsumableTracker.write_joker_csv(joker_event_data)
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData] write_joker_csv: ConsumableTracker.run_info_snapshot not initialized!")
        return
    end
    local dataset_dir = tracker_helpers.ensure_folders(ConsumableTracker.run_info_snapshot.profile, ConsumableTracker.joker_dataset)
    local filename = string.format("%s/%s_%s.csv", dataset_dir, ConsumableTracker.joker_dataset, tracker_helpers.get_date_suffix())
    local header = "run_id,run_joker_id,joker_in_run_uid,run_joker_event_id,joker_name,joker_event,joker_event_cause,joker_event_details,joker_sticker,joker_edition,cost,selling_effect,event_tmst\n"
    local file_info = love.filesystem.getInfo(filename)
    local needs_header = not file_info or file_info.size == 0

    local row = string.format(
        "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
        joker_event_data.run_id,                        -- Overall Run ID
        joker_event_data.run_joker_id,                  -- run_id-J_# (unique log entry ID for Joker Event)
        joker_event_data.joker_in_run_uid or "",        -- J_# (persistent joker instance ID)
        joker_event_data.run_joker_event_id,            -- ante-round-cause (context string)
        joker_event_data.joker_name,
        joker_event_data.joker_event,                   -- "added", "modified", "removed"
        joker_event_data.joker_event_cause,             -- "shop_purchase", "sold", etc.
        joker_event_data.joker_event_details or "",     -- e.g. "Riff-Raff"
        joker_event_data.joker_sticker,
        joker_event_data.joker_edition,
        joker_event_data.cost,
        joker_event_data.selling_effect or "None",
        tracker_helpers.get_utc_timestamp()
    )

    local success, err_msg
    if needs_header then
        success, err_msg = love.filesystem.write(filename, header .. row)
    else
        success, err_msg = love.filesystem.append(filename, row)
    end

    if not success then
        print(string.format("🚨 [JimbosData] Error writing Joker CSV to %s: %s", filename, err_msg or "Unknown error"))
    end
end

function ConsumableTracker.snapshot_jokers()
    local snapshot = {}
    if not G or not G.jokers or not G.jokers.cards then return snapshot end
    for i, joker in ipairs(G.jokers.cards) do
        if joker and joker.config then

            local center_key = joker.config.center_key
            local joker_name = G.P_CENTERS[center_key] and G.P_CENTERS[center_key].name or "unknown"
            local joker_id = tostring(joker)

            snapshot[joker_id] = { 
                unique_game_id = joker_id,
                name = joker_name,
                edition = joker.edition and joker.edition.type or "",
                sticker = ConsumableTracker.get_joker_sticker(joker),
                cost = joker.cost, -- Buy cost
                sell_cost = joker.sell_cost,
                selling_effect = joker.selling_effect or "", -- Specific to jokers
                center_key = center_key,
                joker = joker -- Store the actual joker object for deeper inspection if needed
            }
        end
    end
    return snapshot
end

function ConsumableTracker.joker_changed(prev_joker_details, current_joker_details)
    if not prev_joker_details or not current_joker_details then return true end -- One is nil, so it's a change (add/remove)
    return prev_joker_details.name ~= current_joker_details.name or
           prev_joker_details.edition ~= current_joker_details.edition or
           prev_joker_details.sticker ~= current_joker_details.sticker or
           prev_joker_details.cost ~= current_joker_details.cost or         -- Original buy cost
           prev_joker_details.sell_cost ~= current_joker_details.sell_cost or -- Sell cost (e.g., for Egg)
           prev_joker_details.selling_effect ~= current_joker_details.selling_effect -- e.g., Perishable status
end

-- `event_source_details` can be a table like { type="joker_effect", name="Riff-Raff" } or { type="key_append", value="rif" }
function ConsumableTracker.update_joker_tracker(event_hint, event_source_details)
    if not G or not G.jokers or not G.jokers.cards then return end

    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData] update_joker_tracker: ConsumableTracker.run_info_snapshot not initialized!")
        return
    end
    local run_id = ConsumableTracker.run_info_snapshot.run_id
    local current_ante, current_round = getCurrentRunContext()
    local current_jokers_snapshot = ConsumableTracker.snapshot_jokers() -- keyed by unique_game_id
    local how_event_happened_cause = ConsumableTracker.joker_change_context or event_hint or "unknown_update" -- This is the "HOW"
    local where_event_happened_location = ConsumableTracker.determine_event_location(event_hint) -- This is the "WHERE"
    local event_details_str = ""

    if event_source_details then
        -- Prioritize event_source_details for more specific cause naming
        if event_source_details.type == "spectral_card_effect" then
            event_cause_str = "spectral_card_effect"
            event_details_str = event_source_details.name or ""
        elseif event_source_details.type == "tarot_card_effect" then
            event_cause_str = "tarot_card_effect"
            event_details_str = event_source_details.name or ""
        elseif event_source_details.type == "voucher_effect" then
            event_cause_str = "voucher_effect"
            event_details_str = event_source_details.name or ""
        elseif event_source_details.type == "key_append" then
            event_cause_str = "generated_by_key_append"
            event_details_str = event_source_details.value or ""
        elseif event_source_details.type == "joker_effect" then
            event_cause_str = "joker_effect"
            event_details_str = event_source_details.name or ""
        -- Add more types as needed
        end
    end


    -- Check for added or modified jokers
    for game_id, cur_joker in pairs(current_jokers_snapshot) do
        local tracked_joker_info = ConsumableTracker.tracked_jokers[game_id]

        if not tracked_joker_info then -- New joker
            ConsumableTracker.total_joker_counter = ConsumableTracker.total_joker_counter + 1
            local run_joker_uid = "J_" .. ConsumableTracker.total_joker_counter -- Persistent ID for this joker instance in this run
            
            ConsumableTracker.tracked_jokers[game_id] = {
                details = cur_joker,
                run_joker_uid = run_joker_uid, -- Store the UID
                first_seen_ante = current_ante,
                first_seen_round = current_round,
                first_seen_cause = event_cause_str
            }
            ConsumableTracker.joker_counter = ConsumableTracker.joker_counter + 1
            ConsumableTracker.write_joker_csv({
                run_id = run_id,
                run_joker_id = run_id .. "-J_" .. ConsumableTracker.joker_counter, -- Joker Event Counter
                joker_in_run_uid = run_joker_uid,
                run_joker_event_id = current_ante .. "-" .. current_round .. "-" .. where_event_happened_location, -- WHERE
                joker_name = cur_joker.name,
                joker_event = "added",
                joker_event_cause = how_event_happened_cause, -- HOW
                joker_event_details = event_details_str,
                joker_sticker = cur_joker.sticker,
                joker_edition = cur_joker.edition,
                cost = cur_joker.cost,
                selling_effect = cur_joker.selling_effect
            })
        else -- Existing joker, check if it was modified
            local prev_details = tracked_joker_info.details
            if ConsumableTracker.joker_changed(prev_details, cur_joker) then
                local actual_event_cause_for_modification = how_event_happened_cause -- Start with the "HOW"
                -- If the event_cause_str is still generic like "add" or "sold..." 
                -- and this is clearly a modification, use a more appropriate generic modification cause.
                if actual_event_cause_for_modification == "add" or actual_event_cause_for_modification == "sold or destroyed" or actual_event_cause_for_modification == "unknown_update" then
                    actual_event_cause_for_modification = "attributes_changed_in_play"
                end
                local log_this_modification_to_csv = false
                
                -- Check for structural changes (name, edition, sticker)
                local structural_change = prev_details.name ~= cur_joker.name or
                                          prev_details.edition ~= cur_joker.edition or
                                          prev_details.sticker ~= cur_joker.sticker

                if structural_change then
                    log_this_modification_to_csv = true
                else
                    -- No structural change. Log if sell_cost changed AND it wasn't JUST an increase in sell cost
                    -- No need to track that every change for egg or via gift card
                    -- This will still track sell_cost goes down (like from clearance sale voucher)
                    if prev_details.sell_cost ~= cur_joker.sell_cost then
                        if not (cur_joker.sell_cost > prev_details.sell_cost) then
                            log_this_modification_to_csv = true
                        end
                    end
                end

                if log_this_modification_to_csv then
                    ConsumableTracker.joker_counter = ConsumableTracker.joker_counter + 1
                    ConsumableTracker.write_joker_csv({
                        run_id = run_id,
                        run_joker_id = run_id .. "-J_" .. ConsumableTracker.joker_counter,
                        joker_in_run_uid = tracked_joker_info.run_joker_uid,
                        run_joker_event_id = current_ante .. "-" .. current_round .. "-" .. where_event_happened_location, -- WHERE
                        joker_name = cur_joker.name,
                        joker_event = "modified",
                        joker_event_cause = actual_event_cause_for_modification,
                        joker_event_details = event_details_str,
                        joker_sticker = cur_joker.sticker,
                        joker_edition = cur_joker.edition,
                        cost = cur_joker.sell_cost, -- For "modified" events, log the sell_cost when modification occurs
                        selling_effect = cur_joker.selling_effect
                    })
                end
                ConsumableTracker.tracked_jokers[game_id].details = cur_joker -- Always update internal tracking
            end
        end
    end

    -- Check for removed jokers
    -- Iterate over a copy of keys, as we might modify the table
    local prev_joker_ids = {}
    for id, _ in pairs(ConsumableTracker.tracked_jokers) do table.insert(prev_joker_ids, id) end

    for _, game_id in ipairs(prev_joker_ids) do
        if not current_jokers_snapshot[game_id] then
            local removed_joker_info = ConsumableTracker.tracked_jokers[game_id]
            ConsumableTracker.joker_counter = ConsumableTracker.joker_counter + 1
            ConsumableTracker.write_joker_csv({
                run_id = run_id,
                run_joker_id = run_id .. "-J_" .. ConsumableTracker.joker_counter,
                joker_in_run_uid = removed_joker_info.run_joker_uid,
                run_joker_event_id = current_ante .. "-" .. current_round .. "-" .. where_event_happened_location, -- WHERE
                joker_name = removed_joker_info.details.name,
                joker_event = "removed", -- Or "sold", "destroyed" based on context
                joker_event_cause = how_event_happened_cause, -- HOW
                joker_event_details = event_details_str,
                joker_sticker = removed_joker_info.details.sticker,
                joker_edition = removed_joker_info.details.edition,
                cost = removed_joker_info.details.sell_cost, 
                selling_effect = removed_joker_info.details.selling_effect
            })
            ConsumableTracker.tracked_jokers[game_id] = nil -- Remove from tracked list
        end
    end
    ConsumableTracker.joker_change_context = nil -- Reset context
end


-- =================================================================================
-- SHOP TRACKING [Currently not exporting to a CSV -- on TODO list]
-- =================================================================================
function ConsumableTracker.write_shop_csv(shop_item_data)
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData|ConsumableTracker|write_shop_csv] run_info_snapshot is nil. Cannot write shop data.")
        return
    end
    print("📦 [JimbosData|ConsumableTracker|write_shop_csv] Attempting to write shop item: " .. (shop_item_data.item_name or "Unknown Item") .. " for shop_instance_id: " .. tostring(shop_item_data.shop_instance_id))
    print("➡️ [JimbosData|ConsumableTracker] Entered: write_shop_csv. Item: " .. (shop_item_data and shop_item_data.item_name or "N/A"))
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData] write_shop_csv: ConsumableTracker.run_info_snapshot not initialized!")
        return
    end
    local dataset_dir = tracker_helpers.ensure_folders(ConsumableTracker.run_info_snapshot.profile, ConsumableTracker.shop_dataset)
    local filename = string.format("%s/%s_%s.csv", dataset_dir, ConsumableTracker.shop_dataset, tracker_helpers.get_date_suffix())
    local header = "run_id,ante,round,shop_instance_id,item_slot,item_name,item_type,item_subtype,edition,enhancement,seal,sticker,price,is_purchased,event_tmst\n"
    local file_info = love.filesystem.getInfo(filename)
    local needs_header = not file_info or file_info.size == 0

    local row = string.format(
        "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
        shop_item_data.run_id,
        shop_item_data.ante,
        shop_item_data.round,
        shop_item_data.shop_instance_id,
        shop_item_data.item_slot,
        shop_item_data.item_name,
        shop_item_data.item_type,
        shop_item_data.item_subtype or "N/A",
        shop_item_data.edition or "None",
        shop_item_data.enhancement or "None",
        shop_item_data.seal or "None",
        shop_item_data.sticker or "None",
        shop_item_data.price,
        tostring(shop_item_data.is_purchased or false),
        tracker_helpers.get_utc_timestamp()
    )
    local success, err_msg
    if needs_header then
        success, err_msg = love.filesystem.write(filename, header .. row)
    else
        success, err_msg = love.filesystem.append(filename, row)
    end
    if not success then
        print(string.format("🚨 [JimbosData] Error writing Shop CSV to %s: %s", filename, err_msg or "Unknown error"))
    end
end

-- Call this function whenever the shop is entered or rerolled
-- `shop_cards` is assumed to be a table/list of card objects currently in the shop
function ConsumableTracker.log_shop_contents(shop_cards_table)
    print("🛒 [JimbosData|ConsumableTracker|log_shop_contents] Logging shop contents. Number of items: " .. tostring(shop_cards_table and #shop_cards_table or 0))
    if not shop_cards_table then print("🚨 [JimbosData] log_shop_contents: shop_cards_table is nil") return end
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData] log_shop_contents: ConsumableTracker.run_info_snapshot not initialized!")
        return
    end
    local run_id = ConsumableTracker.run_info_snapshot.run_id
    local current_ante, current_round = getCurrentRunContext()
    ConsumableTracker.shop_instance_counter = ConsumableTracker.shop_instance_counter + 1
    local shop_instance_id = run_id .. "_SHOP_" .. current_ante .. "_" .. current_round .. "_" .. ConsumableTracker.shop_instance_counter
    
    ConsumableTracker.current_shop_items = {} -- Clear previous shop items for this instance

    for i, item_card_obj in ipairs(shop_cards_table) do
        if item_card_obj and item_card_obj.config then
            local details = tracker_helpers.get_card_details(item_card_obj)
            local item_type = details.type
            local item_subtype = details.item_subtype or "N/A" -- get_card_details should provide this

            -- Ensure item_type is correctly identified for boosters if not already by get_card_details
            if item_card_obj.booster_pack_type and item_type ~= "BoosterPack" then
                 item_type = "BoosterPack"
                 item_subtype = item_card_obj.booster_pack_type
            elseif (item_type == "Tarot" or item_type == "Planet" or item_type == "Spectral" or item_type == "Voucher") and item_subtype == "N/A" then
                -- If get_card_details didn't set subtype for these, use item_type itself as subtype
                item_subtype = item_type
            end
            
            local shop_item_data = {
                run_id = run_id,
                ante = current_ante,
                round = current_round,
                shop_instance_id = shop_instance_id,
                item_slot = i,
                item_name = details.name,
                item_type = item_type,
                item_subtype = item_subtype,
                edition = details.edition,
                enhancement = details.enhancement,
                seal = details.seal, -- Playing cards in shop might have seals
                sticker = details.sticker, -- Jokers in shop
                price = details.cost, -- Cost to buy
                is_purchased = false, -- Default to not purchased
                unique_game_id = details.unique_game_id -- Store game ID to track purchase
            }
            ConsumableTracker.write_shop_csv(shop_item_data)
            ConsumableTracker.current_shop_items[details.unique_game_id] = shop_item_data -- Store by game ID
        end
    end
end

-- Call this after an item is successfully purchased from the shop
function ConsumableTracker.log_shop_purchase(purchased_card_obj)
    if not purchased_card_obj then return end
    local game_id = tracker_helpers.get_card_details(purchased_card_obj).unique_game_id -- Use consistent ID
    
    if ConsumableTracker.current_shop_items[game_id] then
        local shop_item_data = ConsumableTracker.current_shop_items[game_id]
        shop_item_data.is_purchased = true
        -- This may not be necessary since we log purchases in other CSVs
        -- Since this isn't exporting yet, we can keep it for now until we focus on getting it working
        
        local current_ante, current_round = getCurrentRunContext()
        local purchase_log_data = shallow_copy(shop_item_data) -- Avoid modifying the original table in current_shop_items
        purchase_log_data.is_purchased = true 
        -- Update timestamp for this specific event
        -- We can add an 'event_type' to shop log: 'stocked', 'purchased'
        -- For now, just re-log with 'is_purchased' true.
        ConsumableTracker.write_shop_csv(purchase_log_data)

        -- Trigger updates for other relevant trackers
        local details = tracker_helpers.get_card_details(purchased_card_obj)
        local source_context = { type = "shop_purchase", name = details.name }

        -- Trigger updates for other relevant trackers based on the purchased item type
        if details.type == "Joker" then
            ConsumableTracker.update_joker_tracker("shop_purchase_joker", source_context)
        elseif details.type == "Tarot" or details.type == "Planet" or details.type == "Spectral" or details.type == "Voucher" then
            ConsumableTracker.log_consumable_obtained(purchased_card_obj, "shop_purchase", details.name)
        elseif details.type == "Playing Card" then
             ConsumableTracker.log_playing_card_event(purchased_card_obj, "added", "shop_purchase", details.name)
        elseif details.type == "BoosterPack" then
            -- Handled by pack opening logic
        end
    else
        -- Item was not in the last logged shop (like from High Priestess or The Emperor)
        -- We should still log its acquisition
        -- This will need work (not currently logging) since they aren't from the shop
        local details = tracker_helpers.get_card_details(purchased_card_obj)
        local source_context = { type = "shop_purchase_direct", name = details.name }
         if details.type == "Joker" then
            ConsumableTracker.update_joker_tracker("shop_purchase_direct_joker", source_context)
        elseif details.type == "Tarot" or details.type == "Planet" or details.type == "Spectral" or details.type == "Voucher" or details.type == "BoosterPack" then -- Also log consumables/packs obtained directly
            ConsumableTracker.log_consumable_obtained(purchased_card_obj, "shop_purchase_direct", details.name)
        elseif details.type == "Playing Card" then
             ConsumableTracker.log_playing_card_event(purchased_card_obj, "added", "shop_purchase_direct", details.name)
        end
    end
end

-- =================================================================================
-- CONSUMABLE TRACKING (Tarot, Planet, Spectral, Voucher)
-- =================================================================================
function ConsumableTracker.write_consumable_csv(consumable_event_data)
    -- This function might be called outside of a full run context initialization
    -- So, ensure we have a valid run_info_snapshot, or fetch current if not.
    local current_run_info = ConsumableTracker.run_info_snapshot or tracker_helpers.get_run_info()
    if not current_run_info then print("🚨 [JimbosData] write_consumable_csv: Could not get run info!") return end

    local dataset_dir = tracker_helpers.ensure_folders(current_run_info.profile, ConsumableTracker.consumable_dataset)
    local filename = string.format("%s/%s_%s.csv", dataset_dir, ConsumableTracker.consumable_dataset, tracker_helpers.get_date_suffix())
    local header = "run_id,run_consumable_id,consumable_in_run_uid,run_consumable_event_id,event_type,consumable_name,consumable_type,ante,round,method,details,target_card_game_id,outcome_summary,event_tmst\n"
    local file_info = love.filesystem.getInfo(filename)
    local needs_header = not file_info or file_info.size == 0
    
    local row = string.format(
        "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
        consumable_event_data.run_id, 
        consumable_event_data.run_consumable_id,        -- run_id-C_# (unique log entry ID)
        consumable_event_data.consumable_in_run_uid or "N/A", -- C_# (persistent consumable instance ID)
        consumable_event_data.run_consumable_event_id,  -- ante-round-WHERE (context string)
        consumable_event_data.event_type, -- "obtained", "used"
        consumable_event_data.consumable_name,
        consumable_event_data.consumable_type, -- Tarot, Planet, Spectral, Voucher
        consumable_event_data.ante,
        consumable_event_data.round,
        consumable_event_data.method, -- "HOW": shop_purchase, pack_opening, manual_use, voucher_auto_apply
        consumable_event_data.details or "", -- pack name, joker name, etc.
        consumable_event_data.target_card_game_id or "", -- if used on a card
        consumable_event_data.outcome_summary or "", -- "Leveled_Up_High_Card"
        tracker_helpers.get_utc_timestamp()
    )
    local success, err_msg
    if needs_header then
        success, err_msg = love.filesystem.write(filename, header .. row)
    else
        success, err_msg = love.filesystem.append(filename, row)
    end
    if not success then
        print(string.format("🚨 [JimbosData] Error writing Consumable CSV to %s: %s", filename, err_msg or "Unknown error"))
    end
end

-- Call when a consumable is obtained (purchased, from pack, generated)
-- `source_details` could be the name of the pack, joker, or "shop_purchase", "key_append:xyz"
function ConsumableTracker.log_consumable_obtained(consumable_card_obj, obtained_method, source_details_str)
    if not consumable_card_obj or not consumable_card_obj.config then return end
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData] log_consumable_obtained: ConsumableTracker.run_info_snapshot not initialized!")
        return
    end
    local run_id = ConsumableTracker.run_info_snapshot.run_id
    local current_ante, current_round = getCurrentRunContext()
    local details = tracker_helpers.get_card_details(consumable_card_obj)

    if not (details.type == "Tarot" or details.type == "Planet" or details.type == "Spectral" or details.type == "Voucher") then
        return
    end
    
    local game_id_str = tostring(consumable_card_obj)
    local tracked_consumable_info = ConsumableTracker.tracked_consumables[game_id_str]
    local consumable_in_run_uid_val

    if not tracked_consumable_info then -- First time seeing this specific consumable object
        ConsumableTracker.total_consumable_counter = ConsumableTracker.total_consumable_counter + 1
        consumable_in_run_uid_val = "C_" .. ConsumableTracker.total_consumable_counter -- Persistent C_#
        ConsumableTracker.tracked_consumables[game_id_str] = { consumable_in_run_uid = consumable_in_run_uid_val, name = details.name, type = details.type }
    else
        consumable_in_run_uid_val = tracked_consumable_info.consumable_in_run_uid
    end
    
    ConsumableTracker.consumable_instance_counter = ConsumableTracker.consumable_instance_counter + 1
    local where_event_happened_location = ConsumableTracker.determine_event_location() -- Use obtained_method as hint for WHERE if applicable


    ConsumableTracker.write_consumable_csv({
        run_id = run_id,
        run_consumable_id = run_id .. "-C_" .. ConsumableTracker.consumable_instance_counter, -- Unique log entry ID
        consumable_in_run_uid = consumable_in_run_uid_val,
        run_consumable_event_id = current_ante .. "-" .. current_round .. "-" .. where_event_happened_location, -- WHERE
        event_type = "obtained",
        consumable_name = details.name,
        consumable_type = details.type,
        ante = current_ante,
        round = current_round,
        method = obtained_method, -- HOW
        details = source_details_str,
        target_card_game_id = "", -- Not applicable for "obtained"
        outcome_summary = ""      -- Not applicable for "obtained"
    })
end

-- Call when a consumable is used/activated
-- `target_card_obj` is the card it was used on (if any)
-- `target_cards_list` can be a list of card objects if the consumable affects multiple.
-- `outcome_summary` is a string describing what happened
function ConsumableTracker.log_consumable_used(consumable_card_obj, used_method, target_card_obj_or_list, outcome_summary)
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData|ConsumableTracker|log_consumable_used] run_info_snapshot is nil. Aborting.")
        return
    end
    if not consumable_card_obj then return end
    local game_id_str = tostring(consumable_card_obj)
    local tracked_info = ConsumableTracker.tracked_consumables[game_id_str]
    
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData] log_consumable_used: ConsumableTracker.run_info_snapshot not initialized!")
        return
    end
    local run_id = ConsumableTracker.run_info_snapshot.run_id

    local consumable_details_for_log
    if not tracked_info then
        -- Still log its use, but with less context
        consumable_details_for_log = tracker_helpers.get_card_details(consumable_card_obj)
        --ConsumableTracker.consumable_instance_counter = ConsumableTracker.consumable_instance_counter + 1
        local temp_run_consumable_id_for_event = run_id .. "-C_" .. ConsumableTracker.consumable_instance_counter
        -- Assign a new C_# for this "use" event as it was never tracked as obtained.
        ConsumableTracker.total_consumable_counter = ConsumableTracker.total_consumable_counter + 1
        local new_uid_for_untracked_use = "C_" .. ConsumableTracker.total_consumable_counter

         tracked_info = { -- Create a temporary tracked_info for logging this event
            consumable_in_run_uid = new_uid_for_untracked_use,
            name = consumable_details_for_log.name,
            type = consumable_details_for_log.type,
         }
    else
        consumable_details_for_log = { -- Use details from when it was tracked
            name = tracked_info.name,
            type = tracked_info.type
            -- any other relevant fields from tracked_info.details if stored
        }
    end
    
    local current_ante, current_round = getCurrentRunContext()
    local where_event_happened_location = ConsumableTracker.determine_event_location() -- Use used_method as hint for WHERE
    ConsumableTracker.consumable_instance_counter = ConsumableTracker.consumable_instance_counter + 1 -- Increment for unique log entry ID

    ConsumableTracker.write_consumable_csv({
        run_id = run_id,
        run_consumable_id = run_id .. "-C_" .. ConsumableTracker.consumable_instance_counter, -- Unique log entry ID
        consumable_in_run_uid = tracked_info.consumable_in_run_uid, -- Use the persistent C_#
        run_consumable_event_id = current_ante .. "-" .. current_round .. "-" .. where_event_happened_location, -- WHERE
        event_type = "used",
        consumable_name = consumable_details_for_log.name,
        consumable_type = consumable_details_for_log.type,
        ante = current_ante,
        round = current_round,
        method = used_method, -- HOW
        target_card_game_id = target_card_obj_or_list and type(target_card_obj_or_list) ~= 'table' and tostring(target_card_obj_or_list) or "Multiple/None", -- Simplified for single target
        outcome_summary = outcome_summary or "Effect applied",
        details = target_card_obj_or_list and type(target_card_obj_or_list) ~= 'table' and ("Target: " .. tracker_helpers.get_card_details(target_card_obj_or_list).name) or ""
    })
    
    -- Remove from active tracked consumables after use
    ConsumableTracker.tracked_consumables[game_id_str] = nil

    -- If a planet card was used, trigger poker hand level update
    if consumable_details_for_log.type == "Planet" then
        ConsumableTracker.update_poker_hand_level_tracker("planet_card_used", consumable_details_for_log.name)
    end
    -- Handle single or multiple targets for playing card modification logging
    local targets_to_process = {}
    if target_card_obj_or_list then
        if type(target_card_obj_or_list) == 'table' then
            targets_to_process = target_card_obj_or_list
        else
            table.insert(targets_to_process, target_card_obj_or_list)
        end
    end
    for _, target_obj in ipairs(targets_to_process) do
        if target_obj then
            local target_details = tracker_helpers.get_card_details(target_obj)
            if target_details.type == "Playing Card" then
                ConsumableTracker.log_playing_card_event(target_obj, "modified", "consumable_effect", consumable_details_for_log.name)
            end
        end
    end
end

-- Specific wrapper for consumables played from hand/area
-- `target_card_objs_list` is a list of card objects that were potentially targeted
function ConsumableTracker.log_consumable_used_from_play(consumable_card_obj, used_method_prefix, target_card_objs_list)    if not consumable_card_obj then return end
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData|ConsumableTracker|log_consumable_used_from_play] run_info_snapshot is nil. Aborting.")
        return
    end
    local details = tracker_helpers.get_card_details(consumable_card_obj) -- Details of the consumable itself
    local outcome = details.name .. " effect"
    
    -- For planet cards, the outcome is leveling a poker hand
    if details.type == "Planet" then
        outcome = "Poker hand leveled up by " .. details.name
    end

    -- If only one target, pass it directly. If multiple, pass the list.
    local target_param_for_log_consumable_used = target_card_objs_list
    if target_card_objs_list and #target_card_objs_list == 1 then
        target_param_for_log_consumable_used = target_card_objs_list[1]
    end
    ConsumableTracker.log_consumable_used(consumable_card_obj, used_method_prefix or "played_from_hand", target_param_for_log_consumable_used, outcome)
end


-- Helper to iterate through G.consumeables.cards (or similar) and log them if not already tracked.
-- Useful for start of run or after loading a save.
function ConsumableTracker.update_consumable_tracker_for_all_held(reason_for_check)
    if G.consumeables and G.consumeables.cards then -- Assuming this is where held consumables are
        for _, cons_card_obj in ipairs(G.consumeables.cards) do
            if cons_card_obj and not ConsumableTracker.tracked_consumables[tostring(cons_card_obj)] then
                ConsumableTracker.log_consumable_obtained(cons_card_obj, reason_for_check or "inventory_check", "N/A")
            end
        end
    end
end


-- =================================================================================
-- POKER HAND LEVEL TRACKING
-- =================================================================================
function ConsumableTracker.write_poker_hand_level_csv(poker_hand_event_data)
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData] write_poker_hand_level_csv: ConsumableTracker.run_info_snapshot not initialized!")
        return
    end
    local dataset_dir = tracker_helpers.ensure_folders(ConsumableTracker.run_info_snapshot.profile, ConsumableTracker.poker_hand_level_dataset)
    local filename = string.format("%s/%s_%s.csv", dataset_dir, ConsumableTracker.poker_hand_level_dataset, tracker_helpers.get_date_suffix())
    local header = "run_id,run_poker_hand_id,run_poker_hand_event_id,ante,round,poker_hand_name,old_level,new_level,level_change,change_cause_type,change_cause_name,event_tmst\n"
    local file_info = love.filesystem.getInfo(filename)
    local needs_header = not file_info or file_info.size == 0

    local row = string.format(
        "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
        poker_hand_event_data.run_id,
        poker_hand_event_data.run_poker_hand_id,        -- run_id-PH_# (unique log entry ID)
        poker_hand_event_data.run_poker_hand_event_id,  -- ante-round-cause (context string)
        poker_hand_event_data.ante,
        poker_hand_event_data.round,
        poker_hand_event_data.poker_hand_name,
        poker_hand_event_data.old_level,
        poker_hand_event_data.new_level,
        poker_hand_event_data.level_change,
        poker_hand_event_data.change_cause_type, -- "HOW": "Planet Card", "Joker Effect", "Spectral Card"
        poker_hand_event_data.change_cause_name, -- "Mars", "Burnt Joker", "Black Hole", etc.
        tracker_helpers.get_utc_timestamp()
    )
    local success, err_msg
    if needs_header then
        success, err_msg = love.filesystem.write(filename, header .. row)
    else
        success, err_msg = love.filesystem.append(filename, row)
    end
    if not success then
        print(string.format("🚨 [JimbosData] Error writing Poker Hand Level CSV to %s: %s", filename, err_msg or "Unknown error"))
    end
end

function ConsumableTracker.snapshot_poker_hand_levels()
    local snapshot = {}
    if G.GAME and G.GAME.hands then
        for hand_key, hand_data in pairs(G.GAME.hands) do
            if hand_data and hand_data.level ~= nil then -- Check for nil explicitly
                local hand_name = tracker_helpers.get_poker_hand_name_from_key(hand_key)
                snapshot[hand_name] = hand_data.level
            end
        end
    else
        print("⚠️ [JimbosData] Could not find G.GAME.hands to snapshot poker hand levels.")
    end
    return snapshot
end

-- `cause_type` e.g., "Planet Card", "Joker Effect". `cause_name` e.g., "Mars", "Burnt Joker".
function ConsumableTracker.update_poker_hand_level_tracker(cause_type, cause_name)
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData] update_poker_hand_level_tracker: ConsumableTracker.run_info_snapshot not initialized!")
        return
    end
    local run_id = ConsumableTracker.run_info_snapshot.run_id
    local current_ante, current_round = getCurrentRunContext()
    local current_levels = ConsumableTracker.snapshot_poker_hand_levels()
    local where_event_happened_location = ConsumableTracker.determine_event_location() -- Use cause_type as hint for WHERE

    for hand_name, new_level in pairs(current_levels) do
        local old_level = ConsumableTracker.previous_poker_hand_levels[hand_name]
        if new_level ~= old_level or cause_type == "run_start" then -- Log initial levels too
            ConsumableTracker.poker_hand_event_counter = ConsumableTracker.poker_hand_event_counter + 1

            ConsumableTracker.write_poker_hand_level_csv({
                run_id = run_id,
                run_poker_hand_id = run_id .. "-PH_" .. ConsumableTracker.poker_hand_event_counter, -- Unique log entry ID
                poker_hand_in_run_uid = hand_name, -- The hand name itself is its UID
                run_poker_hand_event_id = current_ante .. "-" .. current_round .. "-" .. where_event_happened_location, -- WHERE
                ante = current_ante,
                round = current_round,
                poker_hand_name = hand_name,
                old_level = old_level,
                new_level = new_level, -- old_level can be nil if first time, CSV should handle
                level_change = new_level - old_level,
                change_cause_type = cause_type or "Unknown",
                change_cause_name = cause_name or "Unknown details"
            })
        end
    end
    ConsumableTracker.previous_poker_hand_levels = current_levels -- Update for next check
end

-- =================================================================================
-- PLAYING CARD TRACKING
-- =================================================================================
function ConsumableTracker.write_playing_card_csv(card_event_data)
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData] write_playing_card_csv: ConsumableTracker.run_info_snapshot not initialized!")
        -- Allow logging even without run_info_snapshot for potential edge cases, but warn
    end
    local dataset_dir = tracker_helpers.ensure_folders(ConsumableTracker.run_info_snapshot.profile, ConsumableTracker.playing_card_dataset)
    local filename = string.format("%s/%s_%s.csv", dataset_dir, ConsumableTracker.playing_card_dataset, tracker_helpers.get_date_suffix())
    local header = "run_id,run_card_id,card_in_run_uid,run_card_event_id,ante,round,event_type,suit,rank,edition,enhancement,seal,value_mult_add,value_chips_add,change_cause_type,change_cause_name,details,event_tmst\n"
    local file_info = love.filesystem.getInfo(filename)
    local needs_header = not file_info or file_info.size == 0

    local row = string.format(
        "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
        card_event_data.run_id,
        card_event_data.run_card_id,            -- run_id-PC_# (unique log entry ID)
        card_event_data.card_in_run_uid,        -- PC_# (persistent card instance ID)
        card_event_data.run_card_event_id,      -- ante-round-cause (context string)
        card_event_data.ante,
        card_event_data.round,
        card_event_data.event_type, -- "initial_deck", "added", "modified", "destroyed", "played", "discarded"
        card_event_data.suit,
        card_event_data.rank,
        card_event_data.edition or "",
        card_event_data.enhancement or "",
        card_event_data.seal or "",
        card_event_data.value_mult_add or 0,
        card_event_data.value_chips_add or 0,
        card_event_data.change_cause_type or "Unknown", -- "HOW"
        card_event_data.change_cause_name or "Unknown details", -- Specifics of HOW
        card_event_data.details_for_event or "", -- e.g. "edition_to_foil", "seal_added_gold"
        tracker_helpers.get_utc_timestamp()
    )
    local success, err_msg
    if needs_header then
        success, err_msg = love.filesystem.write(filename, header .. row)
    else
        success, err_msg = love.filesystem.append(filename, row)
    end
    if not success then
        print(string.format("🚨 [JimbosData] Error writing Playing Card CSV to %s: %s", filename, err_msg or "Unknown error"))
    end
end

-- Helper to get or create a persistent mod instance ID for a playing card object
function ConsumableTracker.get_or_assign_playing_card_in_run_uid(card_obj)
    local game_id_str = tostring(card_obj)
    if ConsumableTracker.tracked_playing_cards[game_id_str] then
        return ConsumableTracker.tracked_playing_cards[game_id_str].card_in_run_uid
    else
        ConsumableTracker.total_playing_card_counter = ConsumableTracker.total_playing_card_counter + 1
        local new_card_in_run_uid_val = "PC_" .. ConsumableTracker.total_playing_card_counter
        -- Store initial state or reference for future comparison for "modified" events
        ConsumableTracker.tracked_playing_cards[game_id_str] = {
            card_in_run_uid = new_card_in_run_uid_val,
            last_known_details = tracker_helpers.get_card_details(card_obj) -- Store initial details
        }
        return new_card_in_run_uid_val
    end
end


-- Call for various playing card events: "initial_deck", "added", "modified", "destroyed", "played", "discarded"
-- `card_obj`: The playing card object itself.
-- `event_type`: String describing the event.
-- `cause_type`: e.g., "Shop Purchase", "Tarot Effect", "Deck Edit", "key_append:foo"
-- `cause_name_or_details`: Specifics like "The Empress", "Standard Pack", or the actual key_append value.
-- `modification_details_str`: For "modified" events, a string like "edition_foil_to_holographic;seal_gold_added"
function ConsumableTracker.log_playing_card_event(card_obj, event_type, cause_type, cause_name_or_details, modification_details_str)
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData|ConsumableTracker|log_playing_card_event] run_info_snapshot is nil. Aborting.")
        return
    end
    if not card_obj or not card_obj.config then print("🚨 log_playing_card_event: Invalid card_obj") return end
    if not ConsumableTracker.run_info_snapshot then
        print("🚨 [JimbosData] log_playing_card_event: ConsumableTracker.run_info_snapshot not initialized!")
        return
    end
    local run_id = ConsumableTracker.run_info_snapshot.run_id
    local current_ante, current_round = getCurrentRunContext()
    local game_id_str = tostring(card_obj) -- Get the game object ID string early for checks
    local card_details = tracker_helpers.get_card_details(card_obj) -- Get current details

    -- Defensive check for nil card_details
    if not card_details then
        print("🚨 [JimbosData|ConsumableTracker] CRITICAL: tracker_helpers.get_card_details returned nil for card_obj. Aborting log_playing_card_event.")
        print("Card Object: " .. serpent.block(card_obj, {nocode = true, comment = false, sortkeys = true}))
        print("Event Type: " .. tostring(event_type) .. ", Cause Type: " .. tostring(cause_type) .. ", Cause Name: " .. tostring(cause_name_or_details))
        return
    end

    local allowed_event_types = { initial_deck = true, added = true, modified = true, destroyed = true, removed = true }
    if card_details.type ~= "Playing Card" or not allowed_event_types[event_type] then
        -- This function is specifically for playing cards.
        -- print("ℹ️ [JimbosData] log_playing_card_event: Not a playing card, skipping. Type: " .. card_details.type .. ", Name: " .. card_details.name)
        return
    end

    -- For "removed" or "destroyed" events, check if we've already processed this card's removal.
    if event_type == "destroyed" or event_type == "removed" then
        if not ConsumableTracker.tracked_playing_cards[game_id_str] then
            -- This card object is not in our active tracking (entry is nil),
            -- meaning it was likely already logged as removed/destroyed, or was never tracked as "added".
            return
        end
    end
    
    local card_in_run_uid_val
    if event_type == "initial_deck" or event_type == "added" then
        -- For "initial_deck" and "added" events, always generate a new PC_# using the total counter
        ConsumableTracker.total_playing_card_counter = ConsumableTracker.total_playing_card_counter + 1
        card_in_run_uid_val = "PC_" .. ConsumableTracker.total_playing_card_counter
        -- Still track this new UID against the game object ID for future modifications/removals of *this specific card*
        ConsumableTracker.tracked_playing_cards[game_id_str] = {
            card_in_run_uid = card_in_run_uid_val,
            last_known_details = tracker_helpers.get_card_details(card_obj)
        }
    else
        -- For "modified", "removed", "destroyed", use the existing UID if the card was tracked
        card_in_run_uid_val = ConsumableTracker.get_or_assign_playing_card_in_run_uid(card_obj) -- This will retrieve existing or assign new if somehow missed
    end

    ConsumableTracker.playing_card_instance_counter = ConsumableTracker.playing_card_instance_counter + 1 -- For unique log entry ID
    local run_card_id_val = run_id .. "-PC_" .. ConsumableTracker.playing_card_instance_counter -- Unique log entry ID
    local where_event_happened_location = ConsumableTracker.determine_event_location() -- Use cause_type as hint for WHERE

    
    -- For "modified" events, try to determine what changed.
    local details_for_event_str = modification_details_str or ""
    if event_type == "modified" and not modification_details_str then
        if ConsumableTracker.tracked_playing_cards[game_id_str] then
            local previous_details_snapshot = ConsumableTracker.tracked_playing_cards[game_id_str].last_known_details
            
            if previous_details_snapshot then
                local changes = {}
                -- `card_details` was fetched at the start of this function, representing the state *after* modification.
                if previous_details_snapshot.edition ~= card_details.edition then table.insert(changes, "edition:"..tostring(previous_details_snapshot.edition).."->"..tostring(card_details.edition)) end
                if previous_details_snapshot.enhancement ~= card_details.enhancement then table.insert(changes, "enhancement:"..tostring(previous_details_snapshot.enhancement).."->"..tostring(card_details.enhancement)) end
                if previous_details_snapshot.seal ~= card_details.seal then table.insert(changes, "seal:"..tostring(previous_details_snapshot.seal).."->"..tostring(card_details.seal)) end
                
                -- Compare PLUS_CHIPS/MULT directly from the card_obj (current state) vs. snapshot
                local current_plus_chips = card_obj.PLUS_CHIPS or 0
                local current_plus_mult = card_obj.PLUS_MULT or 0
                local prev_chips_add = previous_details_snapshot.value_chips_add or 0
                local prev_mult_add = previous_details_snapshot.value_mult_add or 0

                if prev_chips_add ~= current_plus_chips then table.insert(changes, "chips_add:"..tostring(prev_chips_add).."->"..tostring(current_plus_chips)) end
                if prev_mult_add ~= current_plus_mult then table.insert(changes, "mult_add:"..tostring(prev_mult_add).."->"..tostring(current_plus_mult)) end
                
                -- Compare rank/suit if they can change (e.g., Strength tarot, suit changing tarots)
                if previous_details_snapshot.rank ~= card_details.rank then table.insert(changes, "rank:"..tostring(previous_details_snapshot.rank).."->"..tostring(card_details.rank)) end
                if previous_details_snapshot.suit ~= card_details.suit then table.insert(changes, "suit:"..tostring(previous_details_snapshot.suit).."->"..tostring(card_details.suit)) end

                if #changes > 0 then
                    details_for_event_str = table.concat(changes, "; ")
                else
                    -- No detectable changes compared to last known state.
                    -- To prevent logging an empty modification, we can return here.
                    -- However, it might be that the "modified" event is valid even if our snapshot didn't catch the specific change.
                    -- For now, let's allow it to log with an empty details_for_event_str if no changes are found by this comparison.
                    details_for_event_str = "No specific changes detected by tracker"
                end
            else
                 details_for_event_str = "Unknown prior state for modification (snapshot missing)"
            end
            -- Update last known state AFTER logging modification, using the most current details
            ConsumableTracker.tracked_playing_cards[game_id_str].last_known_details = tracker_helpers.get_card_details(card_obj) -- Re-fetch to ensure it's current
        else
            details_for_event_str = "Modified (no prior tracked instance)"
            -- Ensure it's in tracked_playing_cards and its details are stored
            -- get_or_assign_playing_card_in_run_uid already does this if called, and it was.
            -- ConsumableTracker.tracked_playing_cards[game_id_str].last_known_details = tracker_helpers.get_card_details(card_obj)
        end
        -- Update last known state after logging modification
        if ConsumableTracker.tracked_playing_cards[game_id_str] then
            ConsumableTracker.tracked_playing_cards[game_id_str].last_known_details = card_details
        end
    elseif event_type == "added" then
         -- Update last known state when added
        local game_id_str = tostring(card_obj)
        if ConsumableTracker.tracked_playing_cards[game_id_str] then
             ConsumableTracker.tracked_playing_cards[game_id_str].last_known_details = card_details
        end
    end


    ConsumableTracker.write_playing_card_csv({
        run_id = run_id,
        run_card_id = run_card_id_val,
        card_in_run_uid = card_in_run_uid_val,
        run_card_event_id = current_ante .. "-" .. current_round .. "-" .. where_event_happened_location, -- WHERE
        unique_game_id = card_details.unique_game_id,
        ante = current_ante,
        round = current_round,
        event_type = event_type,
        suit = card_details.suit,
        rank = card_details.rank,
        edition = card_details.edition,
        enhancement = card_details.enhancement,
        seal = card_details.seal,
        value_mult_add = card_details.value_mult_add or 0, -- Fetched by get_card_details
        value_chips_add = card_details.value_chips_add or 0, -- Fetched by get_card_details
        change_cause_type = cause_type, -- HOW
        change_cause_name = cause_name_or_details, -- Specifics of HOW
        details_for_event = details_for_event_str
    })
    if event_type == "destroyed" or event_type == "removed" then -- Also remove from tracking if just removed from deck
        -- This is where we mark it as removed. The check above ensures we only do this once per game_id_str.
        ConsumableTracker.tracked_playing_cards[game_id_str] = nil -- Remove from active tracking
    end
end

-- Call at the start of a run to log all cards in the initial deck
function ConsumableTracker.log_initial_deck_playing_cards()
    local player_deck_cards = {}
    if G.playing_cards and G.playing_cards.cards then 
        player_deck_cards = G.playing_cards.cards
    elseif G.deck and G.deck.cards then
        player_deck_cards = G.deck.cards
    else
        print("⚠️ [JimbosData] Could not find initial deck (G.playing_cards.cards or G.deck.cards) to log.")
        return
    end

    for _, card_obj in ipairs(player_deck_cards) do
        -- tracker_helpers.get_card_details will determine if it's a playing card
        -- The log_playing_card_event function itself has a check for card_details.type
        if card_obj and card_obj.config then -- Basic check for a valid card object
            ConsumableTracker.log_playing_card_event(card_obj, "initial_deck", "game_start", G.GAME.selected_deck and G.GAME.selected_deck.name or "Default Deck")
        end
    end
end

-- Generic function called by the wrap_tracker in init.lua for Card methods (add_to_deck, sell_card, remove_from_deck)
function ConsumableTracker.log_card_event_from_wrapped_method(card_obj, cause_from_wrapper)
    if not card_obj then 
        print("🚨 [ConsumableTracker] log_card_event_from_wrapped_method: Received nil card_obj. Cause: " .. tostring(cause_from_wrapper)) 
        if ConsumableTracker.joker_change_context then ConsumableTracker.joker_change_context = nil end -- Clear context if set
        return 
    end

    local details = tracker_helpers.get_card_details(card_obj)
    if not details then 
        print("🚨 [ConsumableTracker] log_card_event_from_wrapped_method: Could not get card details for obj. Cause: " .. tostring(cause_from_wrapper)) 
        if ConsumableTracker.joker_change_context then ConsumableTracker.joker_change_context = nil end -- Clear context if set
        return 
    end

    if details.type == "Playing Card" then
        local event_type = "unknown"
        local effective_cause_name = cause_from_wrapper -- Default
        if cause_from_wrapper == "add" then 
            event_type = "added"
            effective_cause_name = "add_to_deck" -- More specific for playing cards from this generic hook
        elseif cause_from_wrapper == "sold" then 
            event_type = "destroyed" -- "sold" implies destruction from player's active set
        elseif cause_from_wrapper == "removed" then 
            event_type = "removed"   -- "removed" from deck (e.g. by an effect, not necessarily sold)
        end
        
        if event_type ~= "unknown" then
            ConsumableTracker.log_playing_card_event(card_obj, event_type, "card_method_hook", effective_cause_name)
        else
             print("⚠️ [ConsumableTracker] log_card_event_from_wrapped_method: Unhandled playing card event cause: " .. tostring(cause_from_wrapper))
        end
    elseif details.type == "Joker" then
        -- The joker_change_context was set by the wrapper in init.lua.
        -- update_joker_tracker will use this context and then clear it.
        ConsumableTracker.update_joker_tracker() 
    else
        -- Ensure context is cleared if it was set and not handled by Joker logic
        if ConsumableTracker.joker_change_context then ConsumableTracker.joker_change_context = nil end
    end
    -- Note: ConsumableTracker.update_joker_tracker() is responsible for clearing ConsumableTracker.joker_change_context.
end

-- Helper for shallow copy if needed
function shallow_copy(original)
    local copy = {}
    for key, value in pairs(original) do
        copy[key] = value
    end
    return copy
end

-- Make ConsumableTracker globally accessible within the mod's scope
-- This assignment ensures that _G.jimbosdata.ConsumableTracker (and the local jimbosdata alias if it points to the global)
-- will hold the instance created by this file's execution.
jimbosdata.ConsumableTracker = ConsumableTracker
return ConsumableTracker
