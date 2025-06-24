--[[
   This ACE encounter creates an "egg hunt" for the Firstbloom event
]]

local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local rng = _radiant.math.get_default_rng()

local EggHunt = class()

function EggHunt:initialize()
   self._sv.ctx = nil
   self._sv._info = nil
   self._sv.bulletin_data = {}
   self._sv.bulletin = nil
   self._sv.eggs = {}
   self._sv.score = nil
   self._sv.already_finished = nil
   self._sv.resolved_out_edge = nil
end

function EggHunt:start(ctx, info)
   self._sv.ctx = ctx
   self._sv._info = info
   self._sv.score = 0

   if info.eggs then
      self:start_hunt(info.eggs, info.duration or '16h')
   end

   self.__saved_variables:mark_changed()
end

function EggHunt:create_bulletin(bulletin, score)
   self._sv.bulletin = nil

   local bulletin_data = {
      title = bulletin.title,
      notification_closed_callback = '_on_closed'
   }
   
   self._sv.bulletin = stonehearth.bulletin_board:post_bulletin(self._sv.ctx.player_id)
         :set_callback_instance(self)
         :set_type(bulletin.type or "quest")
         :set_sticky(true)
         :set_data(bulletin_data)

   self.__saved_variables:mark_changed()
end

function EggHunt:start_hunt(eggs, duration)
   local amount = eggs.amount

   while amount > 0 do
      local egg = self:_create_egg(eggs.uri, eggs.hidden_uris or nil)
      table.insert(self._sv.eggs, amount, egg)
      amount = amount - 1
      egg = nil
   end

   self._listener = radiant.events.listen(stonehearth.game_master, 'firstbloom:egg_hunt', self, self._resolve_interaction)

   self._sv.duration = stonehearth.calendar:set_persistent_timer('egg hunt duration', duration, radiant.bind(self, '_end_hunt'))

   if self._sv._info.bulletins and self._sv._info.bulletins.start then
      self:create_bulletin(self._sv._info.bulletins.start)
   end

   self.__saved_variables:mark_changed()
end

function EggHunt:_resolve_interaction(options)
   if not options.entity then
      return
   end

   for pos, existing_egg in pairs(self._sv.eggs) do
      if existing_egg == options.entity then
         if options.transformed_form then
            table.remove(self._sv.eggs, pos)
            table.insert(self._sv.eggs, pos, options.transformed_form)
            self.__saved_variables:mark_changed()
         else
            table.remove(self._sv.eggs, pos)
            self._sv.score = self._sv.score + 1
            if options.citizen then  
               options.citizen:add_component('stonehearth_ace:statistics'):increment_stat('totals', 'firstbloom_eggs_collected')
            end
            self.__saved_variables:mark_changed()  
            if self._sv.score == self._sv._info.eggs.amount then
               self:_destroy_duration()
               self:_end_hunt()
            end
         end
         return
      end
   end
end

function EggHunt:_create_egg(uri, hidden_uris)
   local found = nil
   local egg, location, adjusted_location

   while not found do
      local placement = rng:get_int(1,6)
      if placement < 4 then
         egg = radiant.entities.create_entity(uri)
         local population = stonehearth.population:get_population(self._sv.ctx.player_id)
         local citizens = {}
         for _, citizen in population:get_citizens():each() do
            table.insert(citizens, citizen)
         end
         if #citizens > 0 then
            local random_citizen = citizens[rng:get_int(1, #citizens)]
            location = radiant.entities.get_world_grid_location(random_citizen)
         end
         adjusted_location = location and radiant.terrain.find_placement_point(location, 1, 70)
      elseif placement < 6 then
         if hidden_uris.town then
            egg = radiant.entities.create_entity(hidden_uris.town[rng:get_int(1, #hidden_uris.town)])
         else
            egg = radiant.entities.create_entity(uri)
         end
         local town = stonehearth.town:get_town(self._sv.ctx.player_id)
         location = town:get_landing_location()
         adjusted_location = location and radiant.terrain.find_placement_point(location, 15, 120)
      else
         if hidden_uris.wild then
            egg = radiant.entities.create_entity(hidden_uris.wild[rng:get_int(1, #hidden_uris.wild)])
         else
            egg = radiant.entities.create_entity(uri)
         end
         local bounds = stonehearth.terrain:get_territory(self._sv.ctx.player_id):get_region():get_bounds()
         local x = rng:get_int(bounds.min.x, bounds.max.x)
         local z = rng:get_int(bounds.min.y, bounds.max.y)
         adjusted_location = radiant.terrain.get_point_on_terrain(Point3(x, 0, z))       
      end

      adjusted_location = radiant.terrain.find_closest_standable_point_to(adjusted_location, 10, egg, true)

      local search_cube = Cube3(adjusted_location - Point3(1, 2, 1), adjusted_location + Point3(1, 2, 1))
      local is_in_water = next(radiant.terrain.get_entities_in_cube(search_cube, function(e)
                        return e:get_component('stonehearth:water') ~= nil
                        end)) ~= nil
      local is_close_to_other_eggs = false
      for _, existing_egg in ipairs(self._sv.eggs) do
         if radiant.entities.distance_between(existing_egg, adjusted_location) <= 15 then
            is_close_to_other_eggs = true
         end
      end
      if is_in_water or is_close_to_other_eggs then
         radiant.entities.destroy_entity(egg)
         egg = nil
      else
         found = true
      end
   end

   radiant.terrain.place_entity(egg, adjusted_location)
   return egg
end

function EggHunt:_end_hunt()
   if self._sv.already_finished then
      return
   end

   self._sv.already_finished = true
   self._sv.resolved_out_edge = self:_resolve_out_edge()

   self._sv.ctx.encounter:stop_encounter_music()

	for _, egg in pairs(self._sv.eggs) do
		if radiant.entities.exists(egg) then
         radiant.entities.destroy_entity(egg)
		end
	end

   if self._sv._info.bulletins and self._sv._info.bulletins.finish then
      self:create_bulletin(self._sv._info.bulletins.finish)
   end

   self._sv.ctx.arc:trigger_next_encounter(self._sv.ctx)
   self.__saved_variables:mark_changed()
end

function EggHunt:_resolve_out_edge()
   local amount = self._sv._info.eggs.amount
   local tier_data = self._sv._info.tiers
   local resolved_out_edge = tier_data[1]  -- default to the first tier
   local tiers = #tier_data

   if amount and amount > 0 and tiers > 0 then
      local score = self._sv.score / amount
      score = math.max(0, math.min(1, score)) -- making sure score is never higher than 1; should be impossible but who knows 

      if tiers == 1 then
         return resolved_out_edge
      elseif score == 1 then
         -- Only a perfect score gets the last tier
         resolved_out_edge = tier_data[tiers]
      else
         -- Split (0, 1) into (tiers - 1) windows
         local window = 1 / (tiers - 1)
         for i = 1, tiers - 1 do
            if score < i * window then
               resolved_out_edge = tier_data[i]
               break
            end
         end
      end
   end

   return resolved_out_edge
end

function EggHunt:get_out_edge()
   return self._sv.resolved_out_edge
end

function EggHunt:_destroy_duration()
   if self._sv.duration then
      self._sv.duration:destroy()
      self._sv.duration = nil
   end
end

function EggHunt:destroy()
   if self._sv.bulletin then
      self._sv.bulletin:destroy()
      self._sv.bulletin = nil
   end

   if self._sv.duration then
      self:_destroy_duration()
   end

   if self._listener then
      self._listener:destroy()
      self._listener = nil
   end

   if self._sv.eggs then
      self._sv.eggs = {}
      self._sv.eggs = nil
   end

   if self._sv.already_finished then
      self._sv.already_finished = nil
   end
end

return EggHunt

--[[
<StonehearthEditor>
{
   "type": "encounter",
   "encounter_type": "firstbloom:egg_hunt",
   "in_edge": "start",
   "firstbloom:egg_hunt_info": {
   "duration": "6h",
      "eggs": {
         "amount": 6,
         "uri": "stonehearth_ace:gizmos:firstbloom:hunt_egg",
         "hidden_uris": {
            "town": [
               "stonehearth_ace:gizmos:firstbloom:hunt_egg:basket"
            ]
         }
      },
      "tiers": {
         "tier_1": "out_edge_reward_1",
         "tier_2": "out_edge_reward_2"
      },
      "bulletins": {
         "start": {
            "title": "Good luck! Look for the eggs now!"
         },
         "finish": {
            "title": "Good job getting all these eggs!"
         }
      }
   }
}

</StonehearthEditor>
<StonehearthEditorSchema>
{
   "$schema": "http://json-schema.org/draft-04/schema#",
   "id": "http://stonehearth.net/schemas/encounters/egg_hunt.json",
   "title": "An encounter that conducts an egg-hunt type of event for the Firstbloom festival.",
   "allOf": [
      { "$ref": "encounter.json" },
      {
         "type": "object",
         "properties": {
            "encounter_type": { "enum": ["egg_hunt"] },
            "egg_hunt_info":  {
               "type": "object",
               "properties": {
                  "duration": { "$ref": "elements/display_string.json" },
                  "eggs": {
                     "type": "object",
                     "properties": {
                        "amount": { "type": "number" },
                        "uri": { "$ref": "elements/file.json" },
                        "hidden_uris": {
                           "type": "object",
                           "town": {
                              "type": "array",
                              "items": {
                                 "type": "object",
                                 { "$ref": "elements/file.json" }
                              }
                           },
                           "wild": {
                              "type": "array",
                              "items": {
                                 "type": "object",
                                 { "$ref": "elements/file.json" }
                              }
                           }
                        }
                     }
                  },
                  "tiers": {
                     "type": "array",
                     "items": {
                        "type": "object",
                        "anyOf": [
                           { "$ref": "elements/out_edge_spec.json" }
                        ]
                     }
                  },
                  "bulletins": {
                     "type": "object",
                     "properties": {
                        "start": {
                           "type": "object",
                           "properties": {
                              "title": { "type": "string" },
                              "type": { "type": "string" }
                           }
                        },
                        "finish": {
                           "type": "object",
                           "properties": {
                              "title": { "type": "string" },
                              "type": { "type": "string" }
                           }
                        }
                     }
                  }
               },
               "required": ["duration", "eggs", "tiers"]
            }
         },
         "required": ["type", "encounter_type", "in_edge", "egg_hunt_info"]
      }
   ]
}
</StonehearthEditorSchema>
]]
