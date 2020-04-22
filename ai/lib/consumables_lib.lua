-- ACE: could've monkey-patched, but would've had to replace essentially the entire thing anyway, so no point
-- added ability to define item quality-based tiers of consumable data

local ConsumablesLib = class()
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local SCRIPTS_CACHE = {}

function ConsumablesLib.use_consumable(consumable, user, target_entity)
   local root, iconic = entity_forms_lib.get_forms(consumable)
   if root then
      consumable = root
   end

   local consumable_data = ConsumablesLib.get_consumable_data(consumable)
   if not consumable_data then
      radiant.verify(false, "Unable to use consumable %s because it has no entity data for consumables", consumable)
      return false
   end

   local use_script = consumable_data.script
   if not SCRIPTS_CACHE[use_script] then
      SCRIPTS_CACHE[use_script] = radiant.mods.load_script(use_script)()
   end
   local script = SCRIPTS_CACHE[use_script]
   if not script then
      radiant.verify(false, "Could not find script %s for consumable %s", use_script, consumable)
      return false
   end
   if not script.use then
      radiant.verify(false, "Could not find function use() for script %s for consumable %s", use_script, consumable)
      return false
   end
   return script.use(consumable, consumable_data, user, target_entity)
end

function ConsumablesLib.get_consumable_data(consumable)
   local root, iconic = entity_forms_lib.get_forms(consumable)
   if root then
      consumable = root
   end

   local consumable_data = radiant.entities.get_entity_data(consumable, 'stonehearth:consumable')

   -- determine if quality-based tiers of consumable data exist, and use the appropriate one
   if consumable_data and consumable_data.consumable_qualities then
      local quality = radiant.entities.get_item_quality(consumable)
      -- assume that we want to use the highest quality data <= to the consumable's quality
      -- e.g., if no masterwork data specified, have a masterwork consumable use excellent data (or fine, etc., whatever's available)
      local quality_data
      for q = quality, 1, -1 do
         quality_data = consumable_data.consumable_qualities[q]
         if quality_data then
            break
         end
      end

      if quality_data then
         quality_data = radiant.shallow_copy(quality_data)
         -- copy in any base data fields (not overriding existing ones)
         for k, v in pairs(consumable_data) do
            if k ~= 'consumable_qualities' and quality_data[k] == nil then
               quality_data[k] = v
            end
         end
         consumable_data = quality_data
      end
   end

   return consumable_data
end

return ConsumablesLib
