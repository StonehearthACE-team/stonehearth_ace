local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'

local GloryTownBonus = class()

local NET_WORTH_PER_GLORY_LEVEL = 100
local WAVES = {
   [1] = {
      npc_player_id = "undead",
      members = {
         {from_population = {role = "zombie",       min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:easy"},
      }
   },
   [2] = {
      npc_player_id = "undead",
      members = {
         {from_population = {role = "skeleton",     min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:medium"},
			{from_population = {role = "mummy",     min=0, max=1},  tuning = "stonehearth_ace:monster_tuning:undead:easy_mummy"},
      }
   },
   [4] = {
      npc_player_id = "undead",
      members = {
         {from_population = {role = "zombie",       min=0, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:medium"},
         {from_population = {role = "skeleton",     min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:easy"},
         {from_population = {role = "wolf_skeleton", min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:wolf_skeleton"},
			{from_population = {role = "mummy",     min=0, max=1},  tuning = "stonehearth_ace:monster_tuning:undead:medium_mummy"},
      }
   },
   [8] = {
      npc_player_id = "undead",
      members = {
         {from_population = {role = "necromancer", min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:necromancer"},
         {from_population = {role = "zombie_giant", min=1, max=2},  tuning = "stonehearth:monster_tuning:undead_glory:hard"},
			{from_population = {role = "mummy",     min=1, max=1},  tuning = "stonehearth_ace:monster_tuning:undead:medium_mummy"},
      }
   },
   [16] = {
      npc_player_id = "undead",
      members = {
         {from_population = {role = "necromancer", min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:necromancer"},
         {from_population = {role = "zombie_giant", min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:hard"},
         {from_population = {role = "skeleton_giant", min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:skeleton_giant"},
			{from_population = {role = "mummy",     min=0, max=2},  tuning = "stonehearth_ace:monster_tuning:undead:medium_mummy"},
      }
   },
   [32] = {
      npc_player_id = "undead",
      members = {
         {from_population = {role = "necromancer", min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:necromancer"},
         {from_population = {role = "zombie_giant", min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:very_hard"},
         {from_population = {role = "skeleton_giant", min=1, max=2},  tuning = "stonehearth:monster_tuning:undead_glory:skeleton_giant"},
			{from_population = {role = "mummy",     min=1, max=2},  tuning = "stonehearth_ace:monster_tuning:undead:insane_mummy"},
      }
   },
   [64] = {
      npc_player_id = "undead",
      members = {
         {from_population = {role = "necromancer", min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:necromancer"},
         {from_population = {role = "wolf_skeleton", min=1, max=2},  tuning = "stonehearth:monster_tuning:undead_glory:wolf_skeleton"},
         {from_population = {role = "zombie_giant", min=2, max=3},  tuning = "stonehearth:monster_tuning:undead_glory:very_hard"},
         {from_population = {role = "skeleton",     min=2, max=3},  tuning = "stonehearth:monster_tuning:undead_glory:very_hard"},
         {from_population = {role = "skeleton_giant", min=2, max=3},  tuning = "stonehearth:monster_tuning:undead_glory:skeleton_giant"},
			{from_population = {role = "mummy",     min=1, max=3},  tuning = "stonehearth_ace:monster_tuning:undead:epic_mummy"},
      }
   },
   [128] = {
      npc_player_id = "undead",
      members = {
         {from_population = {role = "necromancer", min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:necromancer"},
         {from_population = {role = "zombie_giant", min=3, max=5},  tuning = "stonehearth:monster_tuning:undead_glory:very_hard"},
         {from_population = {role = "skeleton",     min=3, max=5},  tuning = "stonehearth:monster_tuning:undead_glory:very_hard"},
         {from_population = {role = "skeleton_giant", min=3, max=5},  tuning = "stonehearth:monster_tuning:undead_glory:skeleton_giant"},
			{from_population = {role = "mummy",     min=2, max=4},  tuning = "stonehearth_ace:monster_tuning:undead:epic_mummy"},
      }
   },
   [256] = {
      npc_player_id = "undead",
      members = {
         {from_population = {role = "necromancer", min=1, max=1},  tuning = "stonehearth:monster_tuning:undead_glory:necromancer"},
         {from_population = {role = "zombie_giant", min=5, max=8},  tuning = "stonehearth:monster_tuning:undead_glory:very_hard"},
         {from_population = {role = "skeleton",     min=5, max=8},  tuning = "stonehearth:monster_tuning:undead_glory:very_hard"},
         {from_population = {role = "skeleton_giant", min=5, max=8},  tuning = "stonehearth:monster_tuning:undead_glory:skeleton_giant"},
			{from_population = {role = "mummy",     min=3, max=6},  tuning = "stonehearth_ace:monster_tuning:undead:epic_mummy"},
      }
   },
}

function GloryTownBonus:initialize()
   self._sv.player_id = nil
   self._sv.display_name = 'i18n(stonehearth:data.gm.campaigns.town_progression.hearth_choice.glory.name)'
   self._sv.description = 'i18n(stonehearth:data.gm.campaigns.town_progression.hearth_choice.glory.description)'
   self._sv.glory_level = 0
   self._sv.current_wave = nil  -- When a wave is in progress, a table of wave members still alive, keyed by their entity ID.
   self._sv.summon_source_entity = nil  -- A reference to the entity that initiated the last wave (expected to always be the Glory Hearth).
   
   self.current_wave_abandoned = false
end

function GloryTownBonus:create(player_id)
   self._sv.player_id = player_id
end

function GloryTownBonus:initialize_bonus()
   self._sv.glory_level = 1  -- Start at 1 so we get a small bonus immediately, and indexing WAVES is simpler.
end

function GloryTownBonus:activate()
   if self._sv.current_wave then
      for _, member in pairs(self._sv.current_wave) do
         radiant.events.listen(member, 'radiant:entity:pre_destroy', function()
               self:_on_wave_member_died(member)
            end)
      end
      self._sv.summon_source_entity:get_component('stonehearth:commands'):remove_command('stonehearth:commands:spawn_glory_wave')
      self._sv.summon_source_entity:get_component('stonehearth:commands'):add_command('stonehearth:commands:abandon_glory_wave')
   end
end

function GloryTownBonus:get_net_worth_bonus()
   return self._sv.glory_level * NET_WORTH_PER_GLORY_LEVEL
end

-- Returns whether a wave was summoned (i.e. another isn't in progress, and there are more levels to go).
function GloryTownBonus:spawn_next_wave(source_entity)
   if self._sv.current_wave then
      return false  -- Wave already in progress
   end
   
   -- Remember the hearth.
   self._sv.summon_source_entity = source_entity
   source_entity:get_component('stonehearth:commands'):remove_command('stonehearth:commands:spawn_glory_wave')
   source_entity:get_component('stonehearth:commands'):add_command('stonehearth:commands:abandon_glory_wave')

   -- Do we need any location finding here?
   local origin = radiant.entities.get_world_grid_location(source_entity)

   -- Spawn the wave combo.
   self._sv.current_wave = self:_spawn_wave(self._sv.glory_level, origin)
   
   self.current_wave_abandoned = false

   return true
end

function GloryTownBonus:abandon_current_wave(source_entity)
   if not self._sv.current_wave then
      return false
   end
   
   self.current_wave_abandoned = true
   
   for _, member in pairs(self._sv.current_wave) do
      if member:is_valid() then
         local proxy = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = 'running death effect' })
         local location = radiant.entities.get_world_grid_location(member)
         radiant.terrain.place_entity(proxy, location)

         local effect = radiant.effects.run_effect(proxy, "stonehearth:effects:fire_effect")
         effect:set_finished_cb(function()
            radiant.entities.destroy_entity(proxy)
            effect:set_finished_cb(nil)
            effect = nil
         end)

         radiant.entities.destroy_entity(member)
      end
   end
end

function GloryTownBonus:_spawn_wave(level, origin)
   -- From https://stackoverflow.com/a/25594410/181765
   local function bit_and(a, b)
       local p, c = 1, 0
       while a > 0 and b > 0 do
           local ra, rb=a % 2, b % 2
           if ra + rb > 1 then c = c + p end
           a, b, p= (a - ra) / 2, (b - rb) / 2, p * 2
       end
       return c
   end

   local result = {}
   for mask, wave in pairs(WAVES) do
      if bit_and(mask, level) > 0 then
         local population = stonehearth.population:get_population(wave.npc_player_id)
         for _, member_spec in ipairs(wave.members) do
            --set some defaults to reduce overhead in making waves
            if not member_spec.from_population.range then
               member_spec.from_population.range=10
            end
            if not member_spec.from_population.location then
               member_spec.from_population.location = { x = 0, z = 0 }
            end
      
            if not member_spec.from_population.max then
               member_spec.from_population.max = member_spec.from_population.min or 1
            end
      
            local members = game_master_lib.create_citizens(population, member_spec, origin, { player_id = self._sv.player_id })
            for _, member in ipairs(members) do
               local effect = radiant.effects.run_effect(member, "stonehearth:effects:spawn_entity")
               result[member:get_id()] = member
               radiant.events.listen(member, 'radiant:entity:pre_destroy', function()
                     self:_on_wave_member_died(member)
                  end)
            end
         end
      end
   end

   return result
end

function GloryTownBonus:_on_wave_member_died(entity)
   if self._sv.current_wave[entity:get_id()] then
      self._sv.current_wave[entity:get_id()] = nil
   end

   if self._sv.current_wave and not next(self._sv.current_wave) then
      -- Everyone defeated! Go to next level.
      if not self.current_wave_abandoned then
         self._sv.glory_level = self._sv.glory_level + 1

         stonehearth.bulletin_board:post_bulletin(self._sv.player_id)
            :set_data({title = "i18n(stonehearth:data.commands.spawn_glory_wave.glory_level_achieved_bulletin)"})
            :add_i18n_data("glory_level", self._sv.glory_level)
            :set_close_on_handle(true)
            :set_active_duration("2h")
      end
      self._sv.current_wave = nil
      self._sv.summon_source_entity:get_component('stonehearth:commands'):remove_command('stonehearth:commands:abandon_glory_wave')
      self._sv.summon_source_entity:get_component('stonehearth:commands'):add_command('stonehearth:commands:spawn_glory_wave')
      self._sv.summon_source_entity = nil
   end
end

return GloryTownBonus
