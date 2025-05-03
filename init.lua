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

function SMODS.INIT()
    print("🔧 [JimbosData] INIT loading...")
    
    local ok, err = pcall(function() 
        dofile("Mods/JimbosData/JimbosData.lua")
        dofile("Mods/JimbosData/joker_tracker.lua")
    end)
    
    if not ok then
        print("❌ Error loading Jimbos's Data files:", err)
    end
end
    
SMODS.INIT()
