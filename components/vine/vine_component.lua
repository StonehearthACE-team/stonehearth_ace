--[[
   vines are complicated enough as cubic entities, we're going to assume that's the only shape they can be
   if someone wants another shape, they'll just have to mod it themselves
   also assume the model is centered at 0.5, 0.5
]]
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3

local VineComponent = class()

local _directions = {
   ['x-'] = Point3(-1, 0, 0),
   ['x+'] = Point3(1, 0, 0),
   ['z-'] = Point3(0, 0, -1),
   ['z+'] = Point3(0, 0, 1),
   ['y-'] = Point3(0, -1, 0),
   ['y+'] = Point3(0, 1, 0)
}

function VineComponent:initialize()
   local json = radiant.entities.get_json(self) or {}
   self._size = json.size or 1
   self._preferred_orientation = json.preferred_orientation
end

function VineComponent:activate()
   self._uri = self._entity:get_uri()
   self._growth_data = stonehearth_ace.vine:get_growth_data(self._uri)
   self._connection_data = self._entity:get_component('stonehearth_ace:connection'):get_connections(self._uri)

   local entity_forms = self._entity:get_component('stonehearth:entity_forms')
   if entity_forms then
      self._added_to_world_trace = radiant.events.listen_once(self._entity, 'stonehearth:on_added_to_world', function()
         self:_set_model_variant()
         self._added_to_world_trace = nil
      end)
   end
end

function VineComponent:destroy()
   if self._added_to_world_trace then
      self._added_to_world_trace:destroy()
      self._added_to_world_trace = nil
   end
end

function VineComponent:set_preferred_orientation(orientation)
   self._preferred_orientation = orientation
end

-- determine what model should be used for the vine, and what its orientation should be
function VineComponent:_set_model_variant()
   local pref = self.preferred_orientation

   -- if it's vertical, treat it as a ladder
   local ladder = self._entity:add_component('stonehearth:ladder')
   ladder:set_desired_height(self._size)
end

-- try to grow another vine of the same type in a random direction; returns the new entity if successful
function VineComponent:try_grow()
   local options = self:_get_growth_options()
   if not next(options) then
      return
   end


end

function VineComponent:_get_growth_options()
   local options = {}
   -- check in each direction, the size of the entity
   for dir, data in pairs(self._growth_data.growth_directions) do
      
      local point_dir = _directions[dir]

   end
end

return VineComponent
