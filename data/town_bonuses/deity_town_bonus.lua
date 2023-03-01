-- TODO: move recipes to json like other town bonuses

local RECIPES_TO_UNLOCK = {
   ['stonehearth:jobs:blacksmith'] = {
      'decoration:weathervane_poyo',
      'decoration:lamppost_upscale',
      'decoration:lamppost_upscale_double',
      'decoration:lantern_poyo'
   },
   ['stonehearth:jobs:mason'] = {
      'signage_decoration:fountain_wishing',
   },
   ['stonehearth:jobs:herbalist'] = {
      'decorations:tree_redbloom',
      'decorations:tree_goldrose',
      'decorations:tree_moondrop',
      'decorations:pot_redbloom',
      'decorations:pot_goldrose',
      'decorations:pot_moondrop'
   }
}

local RECIPE_UNLOCK_BULLETIN_TITLES = {
   "i18n(stonehearth:data.gm.campaigns.trader.generosity_tier_2_reached.recipe_unlock_herbalist)",
   "i18n(stonehearth:data.gm.campaigns.trader.generosity_tier_2_reached.recipe_unlock_mason)",
   "i18n(stonehearth:data.gm.campaigns.trader.generosity_tier_2_reached.recipe_unlock_blacksmith)"
}

local BUFF_URI = 'stonehearth:buffs:deity_town_bonus:stat_buff'

local ATTRIBUTE_BONUSES = {
   body = 1,
   mind = 1,
   spirit = 1,
}

local DeityTownBonus = class()

function DeityTownBonus:initialize()
   self._sv.player_id = nil
   self._sv.display_name = 'i18n(stonehearth:data.gm.campaigns.town_progression.shrine_choice.deity.name)'
   self._sv.description = 'i18n(stonehearth:data.gm.campaigns.town_progression.shrine_choice.deity.description)'
end

function DeityTownBonus:create(player_id)
   self._sv.player_id = player_id
end

function DeityTownBonus:activate()
   local population = stonehearth.population:get_population(self._sv.player_id)
   self._citizen_added_listener = radiant.events.listen(population, 'stonehearth:population:citizen_count_changed', self, self._add_buff)
   self:_add_buff()
end

function DeityTownBonus:destroy()
   local population = stonehearth.population:get_population(self._sv.player_id)
   for _, citizen in population:get_citizens():each() do
      radiant.entities.remove_buff(citizen, BUFF_URI)
   end
end

function DeityTownBonus:get_recipe_unlocks()
   return RECIPES_TO_UNLOCK, RECIPE_UNLOCK_BULLETIN_TITLES
end

function DeityTownBonus:_add_buff()
   local population = stonehearth.population:get_population(self._sv.player_id)
   for _, citizen in population:get_citizens():each() do
      radiant.entities.add_buff(citizen, BUFF_URI)
   end
end

function DeityTownBonus:get_citizen_attribute_bonuses()
   return ATTRIBUTE_BONUSES
end

return DeityTownBonus
