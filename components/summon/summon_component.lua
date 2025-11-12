-- Based on the amazing Summon Component from BrunoSupremo's 'Swamp Biome + Firefly Goblins + Beast Tamer' mod, with permission!
local SummonComponent = class()

function SummonComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._json = json or {}
end

function SummonComponent:post_activate()
	local despawn_function = function ()
		stonehearth.ai:inject_ai(self._entity, {
   			actions = {
      			"stonehearth_ace:actions:combat:despawn_summon"
   			}
		})
	end

	if not self._sv._despawn_timer then
		self._sv._despawn_timer = stonehearth.calendar:set_timer("SummonComponent creating a despawn timer for summon", self._json.despawn_timer or '2h', despawn_function)
		self.__saved_variables:mark_changed()
	end
	
	if self._json.can_talk then
		self._combat_battery_listener = radiant.events.listen(self._entity, 'stonehearth:combat:in_combat_changed', self, self._in_combat_changed)
	end

	local custom_comp = self._entity:get_component('stonehearth:customization')
	if custom_comp then
		custom_comp:generate_custom_appearance()
	end
end

function SummonComponent:_in_combat_changed(context)
	--when out of combat, they should talk with random citizens
	--but when they spawn or while switching targets, they are idle (a 1 frame of no combat)
	--so the timer is just a buffer to skip those frames and avoid trying to talk on those
	if context.in_combat then
		if self._conversation_timer then
			self._conversation_timer:destroy()
			self._conversation_timer = nil
		end
		radiant.entities.set_resource(self._entity, 'social_satisfaction', 99)
	else
		local delayed_function = function ()
			radiant.entities.set_resource(self._entity, 'social_satisfaction', 0)
		end
		self._conversation_timer = stonehearth.calendar:set_timer("SummonComponent delay adding conversation_component", "1m+4m", delayed_function)
	end
end

function SummonComponent:_link_to_summoner(entity)
   	self._sv._summoner_predestroy_listener = radiant.events.listen(entity, 'radiant:entity:pre_destroy', function()
        stonehearth.ai:inject_ai(self._entity, {
   			actions = {
      			"stonehearth_ace:actions:combat:despawn_summon"
   			}
		})
    end)

	self.__saved_variables:mark_changed()
end

function SummonComponent:get_despawn_effect()
	return self._json.despawn_effect or 'stonehearth:effects:spawn_entity'
end

function SummonComponent:destroy()
	if self._sv._despawn_timer then
		self._sv._despawn_timer:destroy()
		self._sv._despawn_timer = nil
	end

	if self._sv._summoner_predestroy_listener then
		self._sv._summoner_predestroy_listener:destroy()
		self._sv._summoner_predestroy_listener = nil
	end

	if self._combat_battery_listener then
		self._combat_battery_listener:destroy()
		self._combat_battery_listener = nil
	end

	if self._conversation_timer then
		self._conversation_timer:destroy()
		self._conversation_timer = nil
	end
end

return SummonComponent