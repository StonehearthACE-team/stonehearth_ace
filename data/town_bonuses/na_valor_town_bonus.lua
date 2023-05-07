-- TODO: move recipes to json like other town bonuses

local NaValorTownBonus = class()

local RECIPES_TO_UNLOCK = {
   ['stonehearth:jobs:mason'] = {
      'signage_decoration:input_bin_stone_wolf',
      'signage_decoration:output_box_stone_wolf',
      'signage_decoration:wall_mounted_paw',
      'signage_decoration:chest_stone_wolf',
   },
   ['stonehearth:jobs:weaver'] = {
      'decorations:rug_pelt_wolf_recipe',
   },
}

local RECIPE_UNLOCK_BULLETIN_TITLES = {
   "i18n(northern_alliance:data.gm.campaigns.town_progression.shrine_upgrade_valor.recipe_bulletins.recipe_unlock_mason)",
   "i18n(northern_alliance:data.gm.campaigns.town_progression.shrine_upgrade_valor.recipe_bulletins.recipe_unlock_weaver)",
}

local BUFF_URI = 'northern_alliance:buffs:valor_town_bonus:strength_buff'

local ATTRIBUTE_BONUSES = {
   body = 2
}

function NaValorTownBonus:initialize()
   self._sv.player_id = nil
   self._sv.display_name = 'i18n(northern_alliance:entities.decoration.shrine_wolf.shrine_wolf.display_name)'
   self._sv.description = 'i18n(northern_alliance:data.gm.campaigns.town_progression.shrine_choice.valor.description)'
end

function NaValorTownBonus:create(player_id)
   self._sv.player_id = player_id
end

function NaValorTownBonus:activate()
   local population = stonehearth.population:get_population(self._sv.player_id)
   self._citizen_added_listener = radiant.events.listen(population, 'stonehearth:population:citizen_count_changed', self, self._add_buff)
   self:_add_buff()
end

function NaValorTownBonus:destroy()
   local population = stonehearth.population:get_population(self._sv.player_id)
   for _, citizen in population:get_citizens():each() do
      radiant.entities.remove_buff(citizen, BUFF_URI)
   end
end

function NaValorTownBonus:get_recipe_unlocks()
   return RECIPES_TO_UNLOCK, RECIPE_UNLOCK_BULLETIN_TITLES
end

function NaValorTownBonus:_add_buff()
   local population = stonehearth.population:get_population(self._sv.player_id)
   for _, citizen in population:get_citizens():each() do
      radiant.entities.add_buff(citizen, BUFF_URI)
   end
end

function NaValorTownBonus:get_citizen_attribute_bonuses()
   return ATTRIBUTE_BONUSES
end

return NaValorTownBonus