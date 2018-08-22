local rng = _radiant.math.get_default_rng()
local log = radiant.log.create_logger('shakedown_quest')

local ShakeDown = radiant.mods.require('stonehearth.services.server.game_master.controllers.scripts.collection_quest_shakedown')
local AceShakeDown = class()

-- trying to patch the create function doesn't work (probably getting cached along with the destroy function? booo)
AceShakeDown._old__construct = ShakeDown._construct
function AceShakeDown:_construct()
   local ctx = self._sv.ctx
   self:_determine_filler_material(ctx.player_id)
   self:_old__construct()
end

function ShakeDown:_determine_filler_material(player_id)
   local biome = stonehearth.world_generation:get_biome_alias()
   local population = stonehearth.population:get_population(player_id)
   local kingdom = population and population:get_kingdom()
   local filler_material = nil

   -- get the filler material from constants if possible
   local gm_consts = stonehearth.constants.game_master
   local filler_materials = gm_consts and gm_consts.quests and gm_consts.quests.filler_materials
   -- first category is biome; check if there's a kingdom override for it
   if filler_materials and filler_materials[biome] then
      if kingdom and filler_materials[biome][kingdom] then
         filler_material = filler_materials[biome][kingdom]
      else
         filler_material = filler_materials[biome].default
      end
      log:error('found biome filler materials: %s', tostring(filler_material))
   end
   -- if biome keys didn't work out, check for a general kingdom setting
   filler_material = filler_material or (kingdom and filler_materials and filler_materials[kingdom])

   if filler_material then
      -- if we got an array instead of a single item, pick a random one from the array
      if type(filler_material) == 'table' and next(filler_material) then
         filler_material = filler_material[rng:get_int(1, #filler_material)]
      end

      if radiant.resources.load_json(filler_material) then
         self._sv.filler_material = filler_material
      end
   end
end

return AceShakeDown
