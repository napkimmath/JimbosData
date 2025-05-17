--[[This is a mod for the game "Balatro" that tracks data about the game.
    Copyright (C) 2025 NapKim Math

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>]]

-- init.lua
jimbosdata = jimbosdata or {}
run_ended = false 
jimbosdata.last_round_logged = "" 
jimbosdata.last_hand_logged_identifier = "" 
jimbosdata.current_turn_discards_details = "" 

jimbosdata.ante_8_win_logged_for_run = false -- Flag to track if Ante 8 win has been logged

-- Variables to store previous round's state for logging
jimbosdata.prev_round_for_log = 0
jimbosdata.prev_ante_for_log = 0
jimbosdata.prev_hands_played_for_log = 0
jimbosdata.prev_discards_used_for_log = 0
jimbosdata.prev_dollars_for_log = 0
jimbosdata.prev_player_chips_for_log = 0
jimbosdata.prev_blind_name_for_log = "N/A"
jimbosdata.prev_blind_chips_for_log = 0
jimbosdata.prev_blind_disabled_for_log = false
jimbosdata.unique_cards_discarded_this_entire_turn_set = {}


function SMODS.INIT()
    print("🔧 [JimbosData] INIT loading...")

    jimbosdata.Score = dofile("Mods/JimbosData/Score.lua")
    if not jimbosdata.Score then
        print("❌ [JimbosData] CRITICAL: Failed to load Score.lua module!")
        return
    end
    print("📝 [JimbosData] Score module loaded successfully.")

    -- Hook Game:start_run
    local start_run_ok, start_run_err = pcall(function()
        local original_start_run = Game.start_run
        function Game:start_run(args)
            local data = original_start_run(self, args)
            jimbosdata.last_round_logged = "" 
            jimbosdata.last_hand_logged_identifier = "" 
            jimbosdata.current_turn_discards_details = ""
            jimbosdata.logged_ante_rounds_for_csv = {} -- Initialize for round CSV duplicate check
            jimbosdata.ante_8_win_logged_for_run = false -- Reset for new run
            jimbosdata.last_successful_round_details_for_duplicate_check = nil -- Reset for new run
            jimbosdata.unique_cards_discarded_this_entire_turn_set = {} -- Reset for new run
            
            -- Initialize prev_log data to indicate no round has been completed yet.
            -- Score.lua will not log if round is 0.
            jimbosdata.prev_round_for_log = 0 
            jimbosdata.prev_ante_for_log = 0   
            
            jimbosdata.prev_hands_played_for_log = 0
            jimbosdata.prev_discards_used_for_log = 0
            jimbosdata.prev_dollars_for_log = G.GAME.dollars or 4 -- Initial dollars
            jimbosdata.prev_player_chips_for_log = G.GAME.chips or 0
            jimbosdata.prev_blind_name_for_log = "N/A (Pre-Run)"
            jimbosdata.prev_blind_chips_for_log = 0
            jimbosdata.prev_blind_disabled_for_log = false


            G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.15, func = function()
                    jimbosdata.jimbos_data_module = dofile("Mods/JimbosData/JimbosData.lua")
                    if not jimbosdata.jimbos_data_module then print("❌ [JimbosData] Failed to load JimbosData.lua module.") return true end
                    jimbosdata.jimbos_data_module.write_run_csv()
                    
                    jimbosdata.ConsumableTracker = dofile("Mods/JimbosData/ConsumableTracker.lua")
                    if not jimbosdata.ConsumableTracker then print("❌ [JimbosData] Failed to load ConsumableTracker.lua.") return true end
                    
                    -- Initialize all trackers in ConsumableTracker at the start of a run
                    if jimbosdata.ConsumableTracker.initialize_run_trackers then
                        jimbosdata.ConsumableTracker.initialize_run_trackers()
                    else
                        print("❌ [JimbosData] ConsumableTracker.initialize_run_trackers not found!")
                    end

                    -- Log any consumables already in the player's possession at the start of the run (e.g. from deck ability)
                    if jimbosdata.ConsumableTracker.update_consumable_tracker_for_all_held then
                        jimbosdata.ConsumableTracker.update_consumable_tracker_for_all_held("run_start_inventory")
                    end
                    
                    -- No round log from start_run anymore, Game:update_new_round handles all rounds including first actual one
                    return true end, }))
            run_ended = false 
            return data 
        end
    end)
    if not start_run_ok then print("❌ [JimbosData] Error hooking Game:start_run:", start_run_err) end

    -- Consumable Tracker Hooks (Unchanged)
    local wrap_tracker_def_ok, wrap_tracker_def_err = pcall(function()
        function jimbosdata.wrap_tracker(original_func, cause)
            return function(card_self, args) -- 'card_self' is the card object passed by the game
                -- CRITICAL NIL CHECK for the card object itself
                if not card_self then
                    print("⚠️ [JimbosData|wrap_tracker] Original function for '" .. tostring(cause) .. "' called with nil card_self. Aborting original call to prevent crash.")
                    -- For add/remove/sell functions, returning nil is often an acceptable way to indicate failure or no action.
                    return nil 
                end

                local card_obj_ref = card_self -- Keep a reference
                
                -- Set joker_change_context BEFORE calling original_func, as its effects might trigger joker updates
                if jimbosdata.ConsumableTracker then
                    jimbosdata.ConsumableTracker.joker_change_context = cause 
                end

                local result
                local success, err_msg = pcall(function()
                    result = original_func(card_obj_ref, args) -- Use card_obj_ref (which is card_self)
                end)

                if not success then
                    print("❌ [JimbosData|wrap_tracker] Error calling original function for '" .. tostring(cause) .. "': " .. tostring(err_msg))
                    if jimbosdata.ConsumableTracker then 
                        jimbosdata.ConsumableTracker.joker_change_context = nil -- Clear context on error
                    end
                    error(err_msg) -- Re-throw to make game errors visible and halt if necessary
                end

                -- Delayed logging using the Event Manager
                G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.5, func = function()
                    if jimbosdata.ConsumableTracker then
                        -- Check if the specific logging function exists before calling
                        if jimbosdata.ConsumableTracker.log_card_event_from_wrapped_method then
                            jimbosdata.ConsumableTracker.log_card_event_from_wrapped_method(card_obj_ref, cause)
                        else
                            print("⚠️ [JimbosData|wrap_tracker] ConsumableTracker.log_card_event_from_wrapped_method not found!")
                            -- Fallback or ensure joker context is cleared if primary logger is missing
                            if jimbosdata.ConsumableTracker.update_joker_tracker then
                                local details_for_joker_check = tracker_helpers.get_card_details(card_obj_ref)
                                if details_for_joker_check and details_for_joker_check.type == "Joker" then
                                     jimbosdata.ConsumableTracker.update_joker_tracker()
                                end
                            end
                            jimbosdata.ConsumableTracker.joker_change_context = nil -- Ensure context is cleared
                        end
                        -- Note: update_joker_tracker and clearing of joker_change_context
                        -- are expected to be handled by log_card_event_from_wrapped_method if the card is a Joker.
                    end
                    return true 
                end }))
                
                return result 
            end
        end
    end)
    if not wrap_tracker_def_ok then print("❌ Error defining wrap_tracker") else
        if jimbosdata.wrap_tracker then
            Card.add_to_deck = jimbosdata.wrap_tracker(Card.add_to_deck, "add") 
            Card.sell_card = jimbosdata.wrap_tracker(Card.sell_card, "sold")  
            Card.remove_from_deck = jimbosdata.wrap_tracker(Card.remove_from_deck, "removed") 
        end
    end

    -- Hook Game:update_game_over for end-of-run data
    local end_run_ok, end_run_err = pcall(function()
        local original_end_run = Game.update_game_over
        function Game:update_game_over(dt)
            local result 
            if not run_ended then 
                local game_over_cache_round = G.GAME.round
                local game_over_cache_ante
                local game_over_cache_blind_name
                local game_over_cache_blind_chips
                local game_over_cache_blind_disabled

                local final_blind_info_source = nil
                -- For game over, G.GAME.last_blind is often the most reliable.
                if G.GAME.last_blind and G.GAME.last_blind.ante ~= nil and G.GAME.last_blind.ante >=1 then
                    final_blind_info_source = G.GAME.last_blind
                elseif G.GAME.blind and G.GAME.blind.ante ~= nil and G.GAME.blind.ante >=1 then
                    final_blind_info_source = G.GAME.blind
                end

                if final_blind_info_source then
                    game_over_cache_ante = final_blind_info_source.ante
                    if final_blind_info_source.name then
                        game_over_cache_blind_name = final_blind_info_source.name
                    elseif final_blind_info_source.id and G.P_BLINDS and G.P_BLINDS[final_blind_info_source.id] and G.P_BLINDS[final_blind_info_source.id].name then
                        game_over_cache_blind_name = G.P_BLINDS[final_blind_info_source.id].name or final_blind_info_source.id .. " (ID)"
                    else
                        game_over_cache_blind_name = "N/A (Final Blind Name Missing)"
                    end
                    game_over_cache_blind_chips = final_blind_info_source.chips or 0
                    game_over_cache_blind_disabled = final_blind_info_source.disabled or false
                else
                    -- Fallback if no reliable blind object found
                    local ante_val_game_over = jimbosdata.prev_ante_for_log -- Start with ante from last completed round
                    if not ante_val_game_over or ante_val_game_over < 1 then
                        if G.GAME.round_resets and G.GAME.round_resets.ante ~= nil and G.GAME.round_resets.ante >= 1 then
                            ante_val_game_over = G.GAME.round_resets.ante
                        elseif G.GAME.ante ~= nil and G.GAME.ante >= 1 then
                            ante_val_game_over = G.GAME.ante
                        else
                            ante_val_game_over = 1 -- Absolute fallback
                        end
                    end
                    game_over_cache_ante = ante_val_game_over

                    -- Try to get a name from G.GAME.round_resets.blind if possible during fallback
                    if G.GAME.round_resets and G.GAME.round_resets.blind then
                        if G.GAME.round_resets.blind.name then
                            game_over_cache_blind_name = G.GAME.round_resets.blind.name
                        elseif G.GAME.round_resets.blind.id and G.P_BLINDS and G.P_BLINDS[G.GAME.round_resets.blind.id] and G.P_BLINDS[G.GAME.round_resets.blind.id].name then
                            game_over_cache_blind_name = G.P_BLINDS[G.GAME.round_resets.blind.id].name
                        else
                            game_over_cache_blind_name = "N/A (Game Over Fallback Name)"
                        end
                    else
                        game_over_cache_blind_name = "N/A (Game Over Critical Fallback)"
                    end
                    game_over_cache_blind_chips = (G.GAME.blind and G.GAME.blind.chips) or (jimbosdata.prev_blind_chips_for_log or 0) -- Try current G.GAME.blind.chips if available
                    game_over_cache_blind_disabled = (G.GAME.blind and G.GAME.blind.disabled) or false
                end

                local game_over_cache_hands = G.GAME.current_round and G.GAME.current_round.hands_played or 0
                local game_over_cache_discards = G.GAME.current_round and G.GAME.current_round.discards_used or 0
                local game_over_cache_dollars = G.GAME.dollars
                local game_over_cache_chips = G.GAME.chips

                result = original_end_run(self, dt) 
                G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.5, func = function()
                        local should_log_game_over_stats = true
                        if G.GAME.won == true and jimbosdata.ante_8_win_logged_for_run == true then
                            local current_ante_at_game_over = G.GAME.ante or (G.GAME.round_resets and G.GAME.round_resets.ante) or 0
                            if current_ante_at_game_over <= 8 then
                                -- Game over happened at or before Ante 8 completion, and Ante 8 win was already logged.
                                -- This implies an immediate quit after winning Ante 8. Don't re-log.
                                print("🏁 [JimbosData] Game over after Ante 8 win (Ante <= 8), already logged by update_new_round. Skipping redundant Run_End log from game_over.")
                                should_log_game_over_stats = false
                            else
                                -- Game over happened in Ante > 8 (Endless mode). Log final stats.
                                print("🏁 [JimbosData] Game over in Endless mode (Ante > 8) after Ante 8 win. Logging final Run_End stats from game_over.")
                            end
                        end

                        if should_log_game_over_stats then
                            if jimbosdata.jimbos_data_module and jimbosdata.jimbos_data_module.write_end_run_csv then
                                jimbosdata.jimbos_data_module.write_end_run_csv()
                            end
                        
                            -- Log the final round's data if it's a game over scenario
                            if jimbosdata.Score and jimbosdata.Score.write_round_csv and game_over_cache_round > 0 then
                                jimbosdata.prev_round_for_log = game_over_cache_round
                                jimbosdata.prev_ante_for_log = game_over_cache_ante
                                jimbosdata.prev_hands_played_for_log = game_over_cache_hands
                                jimbosdata.prev_discards_used_for_log = game_over_cache_discards
                                jimbosdata.prev_dollars_for_log = game_over_cache_dollars
                                jimbosdata.prev_player_chips_for_log = game_over_cache_chips
                                jimbosdata.prev_blind_name_for_log = game_over_cache_blind_name
                                jimbosdata.prev_blind_chips_for_log = game_over_cache_blind_chips
                                jimbosdata.prev_blind_disabled_for_log = game_over_cache_blind_disabled
                                jimbosdata.Score.write_round_csv()
                            end
                        end
                        return true end, }))
                run_ended = true 
                return result 
            else return original_end_run(self, dt) end
        end
    end)
    if not end_run_ok then print("❌ Error hooking Game:update_game_over:", end_run_err) end

    -- Hook Game:update_new_round for Round Data
    local update_new_round_hook_ok, update_new_round_hook_err = pcall(function()
        if Game.update_new_round then 
            local original_update_new_round_func = Game.update_new_round
            function Game:update_new_round(dt) 

                -- Cache state of the round that just FINISHED, BEFORE original function potentially changes it
                jimbosdata.prev_round_for_log = G.GAME.round
                jimbosdata.prev_player_chips_for_log = G.GAME.chips -- Player score *before* it's reset for the new round.
                jimbosdata.prev_dollars_for_log = G.GAME.dollars -- Money *before* payout for the round. (This will be updated after original_update_new_round if that's the desired timing for "money after payout")

                -- Ante Caching
                if G.GAME.blind and G.GAME.blind.ante ~= nil and G.GAME.blind.ante >= 1 then
                    jimbosdata.prev_ante_for_log = G.GAME.blind.ante
                elseif G.GAME.last_blind and G.GAME.last_blind.ante ~= nil and G.GAME.last_blind.ante >= 1 then
                    jimbosdata.prev_ante_for_log = G.GAME.last_blind.ante
                elseif G.GAME.round_resets and G.GAME.round_resets.ante ~= nil and G.GAME.round_resets.ante >= 1 then
                    jimbosdata.prev_ante_for_log = G.GAME.round_resets.ante
                elseif G.GAME.ante ~= nil and G.GAME.ante >=1 then
                    jimbosdata.prev_ante_for_log = G.GAME.ante
                else
                    jimbosdata.prev_ante_for_log = 1 -- Absolute fallback
                end

                -- Blind Name Caching
                if G.GAME.blind and G.GAME.blind.name then
                    jimbosdata.prev_blind_name_for_log = G.GAME.blind.name
                elseif G.GAME.blind and G.GAME.blind.id and G.P_BLINDS and G.P_BLINDS[G.GAME.blind.id] and G.P_BLINDS[G.GAME.blind.id].name then
                    jimbosdata.prev_blind_name_for_log = G.P_BLINDS[G.GAME.blind.id].name
                elseif G.GAME.last_blind and G.GAME.last_blind.name then
                    jimbosdata.prev_blind_name_for_log = G.GAME.last_blind.name
                elseif G.GAME.last_blind and G.GAME.last_blind.id and G.P_BLINDS and G.P_BLINDS[G.GAME.last_blind.id] and G.P_BLINDS[G.GAME.last_blind.id].name then
                    jimbosdata.prev_blind_name_for_log = G.P_BLINDS[G.GAME.last_blind.id].name
                elseif G.GAME.round_resets and G.GAME.round_resets.blind and G.GAME.round_resets.blind.name then
                    jimbosdata.prev_blind_name_for_log = G.GAME.round_resets.blind.name
                elseif G.GAME.round_resets and G.GAME.round_resets.blind and G.GAME.round_resets.blind.id and G.P_BLINDS and G.P_BLINDS[G.GAME.round_resets.blind.id] and G.P_BLINDS[G.GAME.round_resets.blind.id].name then
                     jimbosdata.prev_blind_name_for_log = G.P_BLINDS[G.GAME.round_resets.blind.id].name
                else
                    jimbosdata.prev_blind_name_for_log = "N/A (Name Undetermined)"
                end

                -- Blind Chips Caching
                if G.GAME.blind and G.GAME.blind.chips ~= nil then
                    jimbosdata.prev_blind_chips_for_log = G.GAME.blind.chips
                elseif G.GAME.last_blind and G.GAME.last_blind.chips ~= nil then
                    jimbosdata.prev_blind_chips_for_log = G.GAME.last_blind.chips
                elseif G.GAME.round_resets and G.GAME.round_resets.blind and G.GAME.round_resets.blind.chips ~= nil then
                    jimbosdata.prev_blind_chips_for_log = G.GAME.round_resets.blind.chips
                else
                    jimbosdata.prev_blind_chips_for_log = 0
                end

                -- Blind Disabled Caching (assuming false if not explicitly set)
                if G.GAME.blind and G.GAME.blind.disabled ~= nil then
                    jimbosdata.prev_blind_disabled_for_log = G.GAME.blind.disabled
                elseif G.GAME.last_blind and G.GAME.last_blind.disabled ~= nil then
                    jimbosdata.prev_blind_disabled_for_log = G.GAME.last_blind.disabled
                else
                    jimbosdata.prev_blind_disabled_for_log = false
                end

                -- Safety check for ante value, especially if it's 0 or nil when it shouldn't be.
                -- This check is crucial and acts as a final guard.
                if (jimbosdata.prev_ante_for_log == nil or jimbosdata.prev_ante_for_log < 1) and jimbosdata.prev_round_for_log > 0 then
                    local original_bad_ante = jimbosdata.prev_ante_for_log
                    local corrected_ante_source = "absolute fallback"
                    local corrected_ante = (G.GAME.round_resets and G.GAME.round_resets.ante)
                    if corrected_ante ~= nil and corrected_ante >= 1 then
                        jimbosdata.prev_ante_for_log = corrected_ante
                        corrected_ante_source = "round_resets.ante"
                    else
                        jimbosdata.prev_ante_for_log = 1 -- Absolute fallback
                    end
                    print(string.format("⚠️ [JimbosData|update_new_round] Corrected ante from %s to %s (from %s) for round %s", tostring(original_bad_ante), tostring(jimbosdata.prev_ante_for_log), corrected_ante_source, tostring(jimbosdata.prev_round_for_log)))
                end

                jimbosdata.prev_hands_played_for_log = G.GAME.current_round and G.GAME.current_round.hands_played or 0
                jimbosdata.prev_discards_used_for_log = G.GAME.current_round and G.GAME.current_round.discards_used or 0
                jimbosdata.prev_dollars_for_log = G.GAME.dollars

                local result_update_new_round = original_update_new_round_func(self, dt) 
                
                -- After the original function, G.GAME.dollars should reflect money AFTER payouts
                -- for the round that just finished (jimbosdata.prev_round_for_log).
                -- Update the cached dollars for that completed round before writing the CSV.
                if jimbosdata.prev_round_for_log > 0 then
                    jimbosdata.prev_dollars_for_log = G.GAME.dollars
                end

                if jimbosdata.prev_round_for_log > 0 then 
                    if jimbosdata.Score and jimbosdata.Score.write_round_csv then
                        jimbosdata.Score.write_round_csv() 
                    end
                end

                -- Check for Ante 8 win condition to log Run_End immediately
                if G.GAME.won == true and not jimbosdata.ante_8_win_logged_for_run then
                    -- This means Ante 8 boss was just defeated
                    G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.6, func = function() -- Delay to ensure all game states are settled
                        if jimbosdata.jimbos_data_module and jimbosdata.jimbos_data_module.write_end_run_csv then
                            print("🏆 [JimbosData] Ante 8 win detected by update_new_round. Logging Run_End data.")
                            jimbosdata.jimbos_data_module.write_end_run_csv()
                            jimbosdata.ante_8_win_logged_for_run = true -- Mark as logged
                        end
                        return true
                    end }))
                end
                return result_update_new_round
            end
            print("🔧 [JimbosData] Game:update_new_round hooked.")
        else print("❌ [JimbosData] Could not find Game:update_new_round.") end
    end)
    if not update_new_round_hook_ok then print("❌ Error hooking Game:update_new_round:", update_new_round_hook_err) end
    
    -- Hook for DISCARD ACTION
    local discard_action_hook_ok, discard_action_hook_err = pcall(function()
        if G.FUNCS and G.FUNCS.discard_cards_from_highlighted then
            -- unique_cards_discarded_this_entire_turn_set is now part of jimbosdata
            local original_discard_action = G.FUNCS.discard_cards_from_highlighted

            G.FUNCS.discard_cards_from_highlighted = function(e, hook)
                if jimbosdata.Score and jimbosdata.Score.get_card_details then 
                    if G.hand and G.hand.highlighted and #G.hand.highlighted > 0 then
                        local discarded_cards_temp_objs = {}
                        for _, card_obj in ipairs(G.hand.highlighted) do table.insert(discarded_cards_temp_objs, card_obj) end
                        
                        local new_discards_str = jimbosdata.Score.get_card_details(discarded_cards_temp_objs, false)
                        if new_discards_str and new_discards_str ~= "N/A" and new_discards_str ~= "" then
                            local temp_current_turn_discards_list = {}
                            for card_str in string.gmatch(new_discards_str, "([^;]+)") do
                                -- Add to our global set for this entire turn if not already present
                                if not jimbosdata.unique_cards_discarded_this_entire_turn_set[card_str] then
                                    jimbosdata.unique_cards_discarded_this_entire_turn_set[card_str] = true
                                end
                            end

                            -- Reconstruct jimbosdata.current_turn_discards_details from the unique set
                            jimbosdata.current_turn_discards_details = ""
                            for card_str_unique, _ in pairs(jimbosdata.unique_cards_discarded_this_entire_turn_set) do
                                if jimbosdata.current_turn_discards_details == "" then
                                    jimbosdata.current_turn_discards_details = card_str_unique
                                else
                                    jimbosdata.current_turn_discards_details = jimbosdata.current_turn_discards_details .. ";" .. card_str_unique
                                end
                            end
                        end
                    -- If no cards highlighted, current_turn_discards_details remains unchanged (or empty if first discard action)
                    end
                else print("⚠️ [JimbosData] Score module or get_card_details not available for discard tracking.") end
                return original_discard_action(e, hook) 
            end
        else print("❌ [JimbosData] Could not find G.FUNCS.discard_cards_from_highlighted.") end
    end)
    if not discard_action_hook_ok then print("❌ Error hooking G.FUNCS.discard_cards_from_highlighted:", discard_action_hook_err) end

    -- Hook G.FUNCS.evaluate_play for Hand Data
    local evaluate_play_hook_ok, evaluate_play_hook_err = pcall(function()
        if G.FUNCS and G.FUNCS.evaluate_play then
            local original_evaluate_play = G.FUNCS.evaluate_play
            
            G.FUNCS.evaluate_play = function(e_eval) 
                local played_card_objects_cache = {} -- Cards that were in G.play when evaluate_play was called
                if G.play and G.play.cards then
                     for _, card_obj in ipairs(G.play.cards) do table.insert(played_card_objects_cache, card_obj) end
                end

                local remaining_cards_cache = {} -- Cards in G.hand before evaluate_play (which is before they are moved to discard)
                if G.hand and G.hand.cards then
                    for _, card_obj in ipairs(G.hand.cards) do table.insert(remaining_cards_cache, card_obj) end
                end

                local result_evaluate_play = original_evaluate_play(e_eval) -- Call original to perform scoring

                -- After original_evaluate_play:
                -- G.GAME.current_round.current_hand has final scores {chips, mult, chip_total, handname}
                -- G.GAME.current_round.hands_played is incremented
                -- G.play.cards should still reflect the cards that were evaluated.
                
                if jimbosdata.Score and jimbosdata.Score.write_hand_csv then
                    if #played_card_objects_cache > 0 then
                        -- Log to Score.lua
                        local current_remaining_hand_cards = {}
                        if G.hand and G.hand.cards then
                            for _, card_obj in ipairs(G.hand.cards) do table.insert(current_remaining_hand_cards, card_obj) end
                        end
                        jimbosdata.Score.write_hand_csv(played_card_objects_cache, current_remaining_hand_cards, jimbosdata.current_turn_discards_details)

                    else
                        print("✋ [JimbosData] No cards found in G.play (cached at start of evaluate_play) to log for hand.")
                    end
                    jimbosdata.current_turn_discards_details = ""
                    jimbosdata.unique_cards_discarded_this_entire_turn_set = {} -- Reset for the next turn/hand
                end
                return result_evaluate_play
            end
            print("🔧 [JimbosData] G.FUNCS.evaluate_play hooked.")
        else
            print("❌ [JimbosData] Could not find G.FUNCS.evaluate_play. Hand data may be inaccurate.")
        end
    end)
    if not evaluate_play_hook_ok then
        print("❌ [JimbosData] Error hooking G.FUNCS.evaluate_play:", evaluate_play_hook_err)
    end

    -- Hooks for ConsumableTracker: Shop
    local shop_generate_hook_ok, shop_generate_hook_err = pcall(function()
        if Shop and Shop.generate_cards then
            local original_shop_generate_cards = Shop.generate_cards
            function Shop:generate_cards(type, amount, custom_cards, args)
                print("🎣 [JimbosData|init.lua] HOOK FIRED: Shop:generate_cards - Type: " .. tostring(type) .. ", Amount: " .. tostring(amount))
                local result = original_shop_generate_cards(self, type, amount, custom_cards, args)
                G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.2, func = function()
                    if not jimbosdata.ConsumableTracker then
                        print("⚠️ [JimbosData|init.lua|Shop:generate_cards] ConsumableTracker not available for log_shop_contents!")
                        return true
                    end
                    if jimbosdata.ConsumableTracker.log_shop_contents then
                        jimbosdata.ConsumableTracker.log_shop_contents(G.shop and G.shop.cards or {})
                    end
                    return true
                end }))
                return result
            end
            print("🔧 [JimbosData] Shop:generate_cards hooked for ConsumableTracker.")
        else print("❌ [JimbosData] Could not find Shop:generate_cards.") end
    end)
    if not shop_generate_hook_ok then print("❌ [JimbosData] Error hooking Shop:generate_cards:", shop_generate_hook_err) end

    local shop_buy_card_hook_ok, shop_buy_card_hook_err = pcall(function()
        if Shop and Shop.buy_card then
            local original_shop_buy_card = Shop.buy_card
            function Shop:buy_card(card, slot, from_shop_area)
                print("🎣 [JimbosData|init.lua] HOOK FIRED: Shop:buy_card - Card: " .. (card and card.config and card.config.center_key or "Unknown"))
                local purchased_card_obj_ref = card 
                local original_call_successful_purchase = false
                local success, result_or_err = pcall(function() original_call_successful_purchase = original_shop_buy_card(self, card, slot, from_shop_area) end)

                if success and original_call_successful_purchase then
                    G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.2, func = function()
                        if not jimbosdata.ConsumableTracker then
                            print("⚠️ [JimbosData|init.lua|Shop:buy_card] ConsumableTracker not available for log_shop_purchase!")
                            return true
                        end
                        if jimbosdata.ConsumableTracker.log_shop_purchase then
                            jimbosdata.ConsumableTracker.log_shop_purchase(purchased_card_obj_ref)
                        end
                        return true
                    end }))
                end
                if not success then error(result_or_err) end 
                return original_call_successful_purchase
            end
            print("🔧 [JimbosData] Shop:buy_card hooked for ConsumableTracker.")
        else print("❌ [JimbosData] Could not find Shop:buy_card.") end
    end)
    if not shop_buy_card_hook_ok then print("❌ [JimbosData] Error hooking Shop:buy_card:", shop_buy_card_hook_err) end

    -- Hooks for ConsumableTracker: Consumable Usage
    local function create_consumable_play_hook(func_name, consumable_type_name)
        local pcall_ok, pcall_err = pcall(function()
            if G.FUNCS and G.FUNCS[func_name] then
                local original_func = G.FUNCS[func_name]
                G.FUNCS[func_name] = function(card, area, conf)
                    print("🎣 HOOK FIRED: " .. func_name .. " - Card: " .. (card and card.config and card.config.center_key or "Unknown"))
                    local card_ref = card 
                    local result = original_func(card, area, conf)
                    G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.2, func = function()
                        if jimbosdata.ConsumableTracker and jimbosdata.ConsumableTracker.log_consumable_used_from_play then
                            jimbosdata.ConsumableTracker.log_consumable_used_from_play(card_ref, consumable_type_name .. "_played")
                        end
                        return true
                    end }))
                    return result
                end
                print("🔧 [JimbosData] G.FUNCS." .. func_name .. " hooked for " .. consumable_type_name .. " usage.")
            else
                print("❌ [JimbosData] Could not find G.FUNCS." .. func_name .. " for " .. consumable_type_name .. " usage.")
            end
        end)
        if not pcall_ok then print("❌ [JimbosData] Error hooking G.FUNCS." .. func_name .. ":", pcall_err) end
    end

    create_consumable_play_hook("play_tarot_card", "Tarot")
    create_consumable_play_hook("play_planet_card", "Planet")
    create_consumable_play_hook("play_spectral_card", "Spectral")
    
    -- Hook Card.use_consumeable for detailed modification tracking
    local card_use_consumeable_hook_ok, card_use_consumeable_hook_err = pcall(function()
        if Card and Card.use_consumeable then
            local original_card_use_consumeable = Card.use_consumeable
            function Card:use_consumeable(area, copier)
                local consumable_card_ref = self -- The consumable card being used
                
                -- Capture potential targets (highlighted cards) BEFORE the original function modifies them or clears highlights
                local potential_target_cards_before_effect = {}
                if G.hand and G.hand.highlighted_cards and #G.hand.highlighted_cards > 0 then
                    for _, hc_card in ipairs(G.hand.highlighted_cards) do
                        table.insert(potential_target_cards_before_effect, hc_card)
                    end
                end
                -- Some consumables like Sigil/Ouija affect all G.hand.cards, not just highlighted.
                -- For simplicity, the current log_consumable_used_from_play primarily passes highlighted.
                -- If more complex targeting is needed, this snapshot could be expanded.

                local result = original_card_use_consumeable(self, area, copier) -- Call original function

                G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.5, func = function()
                    if jimbosdata.ConsumableTracker and jimbosdata.ConsumableTracker.log_consumable_used_from_play then
                        -- Pass the consumable itself, a generic method string, and the list of cards that were highlighted before the effect
                        jimbosdata.ConsumableTracker.log_consumable_used_from_play(consumable_card_ref, "card_method_use_consumeable", potential_target_cards_before_effect)
                    end
                    return true
                end }))
                return result
            end
            print("🔧 [JimbosData] Card.use_consumeable hooked for detailed consumable effect tracking.")
        else print("❌ [JimbosData] Could not find Card.use_consumeable to hook.") end
    end)
    if not card_use_consumeable_hook_ok then print("❌ [JimbosData] Error hooking Card.use_consumeable:", card_use_consumeable_hook_err) end

    -- Hook for Booster Pack Opening (Adds Playing Cards and Consumables)
    local handle_pack_contents_hook_ok, handle_pack_contents_hook_err = pcall(function()
        if G.FUNCS and G.FUNCS.handle_pack_contents then
            local original_handle_pack_contents = G.FUNCS.handle_pack_contents
            G.FUNCS.handle_pack_contents = function(e, cards, pack_type)
                print("🎣 HOOK FIRED: G.FUNCS.handle_pack_contents - Pack Type: " .. tostring(pack_type) .. ", Cards received: " .. (#cards or 0))
                local cards_received_ref = cards -- Reference the list of cards received
                local result = original_handle_pack_contents(e, cards, pack_type)
                
                G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.5, func = function()
                    if jimbosdata.ConsumableTracker then
                        local source_details_str = pack_type or "Unknown Pack"
                        for _, card_obj in ipairs(cards_received_ref) do
                            local details = tracker_helpers.get_card_details(card_obj)
                            if details.type == "Playing Card" then
                                jimbosdata.ConsumableTracker.log_playing_card_event(card_obj, "added", "pack_opening", source_details_str)
                            elseif details.type == "Tarot" or details.type == "Planet" or details.type == "Spectral" or details.type == "Voucher" or details.type == "Joker" or details.type == "BoosterPack" then -- Jokers and other consumables/packs can also come from packs/rewards
                                jimbosdata.ConsumableTracker.log_consumable_obtained(card_obj, "pack_opening", source_details_str) -- Also handles jokers for now, might need separate call
                            end
                        end
                    end; return true end, }))
                return result
            end
            print("🔧 [JimbosData] G.FUNCS.handle_pack_contents hooked for ConsumableTracker.")
        else print("❌ [JimbosData] Could not find G.FUNCS.handle_pack_contents.") end
    end)
    if not handle_pack_contents_hook_ok then print("❌ [JimbosData] Error hooking G.FUNCS.handle_pack_contents:", handle_pack_contents_hook_err) end

    print("🔧 [JimbosData] INIT loading sequence complete.")
end

SMODS.INIT()
