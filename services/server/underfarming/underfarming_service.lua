local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

UnderfarmingService = class()

function UnderfarmingService:__init()
   self._undercrop_details = {}
   self:_load_initial_undercrops()
end

--- Track the undercrops currently available to each community
--  Start the town with a certain number of undercrops
function UnderfarmingService:initialize()
   self._data = {
      -- we probably want different undercrop inventories per town, but right now there's
      -- at most one town per player (and only 1 player.  ha!).  until we get that
      -- straightend out, let's just assume a player can use all the undercrops in all
      -- his towns
      player_undercrops = {}
   }

   self.__saved_variables = radiant.create_datastore(self._data)
   self.__saved_variables:mark_changed()

end

function UnderfarmingService:restore()
end

function UnderfarmingService:create_new_underfield(session, location, size)
   -- A little sanitization: what we get from the client isn't exactly a Point3
   location = Point3(location.x, location.y, location.z)
   local entity = radiant.entities.create_entity('stonehearth_ace:mountain_folk:grower:underfield', { owner = session.player_id })
   radiant.terrain.place_entity(entity, location)

   self:_add_region_components(entity, size)

   local town = stonehearth.town:get_town(session.player_id)

   local grower_underfield = entity:get_component('stonehearth_ace:grower_underfield')
   grower_underfield:on_underfield_created(town, size)

   return entity
end

--TODO: revisit when we gate farmables by seeds that people start with
function UnderfarmingService:_load_initial_undercrops()
   -- local player_id = session.player_id
   -- local kingdom = stonehearth.population:get_population(player_id)
   --                                              :get_kingdom()

   local all_undercrops_data = radiant.resources.load_json('stonehearth_ace:mountain_folk:grower:all_undercrops')
   local undercrop_data = radiant.resources.load_json('stonehearth_ace:mountain_folk:grower:initial_undercrops')

   self._all_undercrops = all_undercrops_data.undercrops

   -- local player_undercrops = {}
   -- for undercrop, data in pairs(all_undercrops) do
   --    player_undercrops[undercrop] = data
   --    if undercrop_data.undercrops_by_kingdom[undercrop] then
   --       player_undercrops[undercrop].is_initial_undercrop = true
   --    else
   --       player_undercrops[undercrop].is_initial_undercrop = false
   --    end
   -- end

   -- self._all_undercrops = player_undercrops

   self._initial_undercrops = undercrop_data.undercrops_by_kingdom

   --Pre-load the details for the non-undercrop "substrate"
   self._undercrop_details['substrate'] = undercrop_data.data.substrate
end

--- Given a new undercrop type, record some important things about it
function UnderfarmingService:get_undercrop_details(undercrop_type)
   local details = self._undercrop_details[undercrop_type]
   if not details then
      local catalog_data = stonehearth.catalog:get_catalog_data(undercrop_type)
      details = {}
      details.uri = undercrop_type
      details.name = catalog_data.display_name
      details.description = catalog_data.description
      details.icon = catalog_data.icon
      local json = radiant.resources.load_json(undercrop_type)
      if json and json.components and json.components['stonehearth:growing'] and json.components['stonehearth:growing'].preferred_seasons then
         local biome_uri = stonehearth.world_generation:get_biome_alias()
         local seasons = stonehearth.seasons:get_seasons()
         if biome_uri and seasons then  -- Hacky protection against races; should never happen in theory.
            local preferred_seasons = json.components['stonehearth:growing'].preferred_seasons[biome_uri]
            details.preferred_seasons = {}
            if preferred_seasons then
               for _, season_id in ipairs(preferred_seasons) do
                  if seasons[season_id] then
                     table.insert(details.preferred_seasons, seasons[season_id].display_name)
                  end
               end
            end
         end
      end
      self._undercrop_details[undercrop_type] = details
   end
   return details
end

--- Get the undercrop types available to a player. Start with a couple if there are none so far.
function UnderfarmingService:get_all_undercrop_types(session)
   return self:_get_undercrop_list(session)
end

--Returns true if the player/kingdom combination has the undercrop in question,
--false otherwise
function UnderfarmingService:has_undercrop_type(session, undercrop_type_name)
   for i, undercrop_data in ipairs(self:_get_undercrop_list(session)) do
      if undercrop_data.undercrop_type == undercrop_type_name then
         return true
      end
   end
   return false
end

--- Add a new undercrop type to a specific player
function UnderfarmingService:add_undercrop_type(session, new_undercrop_type, quantity)
   for i, undercrop_data in ipairs(self:_get_undercrop_list(session)) do
      if undercrop_data.undercrop_type == new_undercrop_type then
         -- ideally we would do this, but no one uses quantity and there are
         -- some errors in writing it (sometimes undercrop_data.quantity is nil...)
         -- undercrop_data.quantity = undercrop_data.quantity + quantity
         return
      end
   end

   local undercrop_list = self:_get_undercrop_list(session)
   local undercrop_data = {
            undercrop_type = new_undercrop_type,
            undercrop_info = self:get_undercrop_details(new_undercrop_type),
            quantity = quantity
         }
   table.insert(undercrop_list, undercrop_data)
   return undercrop_list
end

function UnderfarmingService:_add_region_components(entity, size)
   local shape = Cube3(Point3.zero, Point3(size.x, 1, size.y))

   entity:add_component('region_collision_shape')
            :set_region_collision_type(_radiant.om.RegionCollisionShape.NONE)
            :set_region(_radiant.sim.alloc_region3())
            :get_region():modify(function(cursor)
                  cursor:add_unique_cube(shape)
               end)

   entity:add_component('destination')
            :set_auto_update_adjacent(true)
            :set_region(_radiant.sim.alloc_region3())
            :get_region():modify(function(cursor)
                  cursor:add_unique_cube(shape)
               end)

end

function UnderfarmingService:_get_undercrop_list(session)
   local player_id = session.player_id
   local undercrop_list = self._data.player_undercrops[player_id]
   if not undercrop_list then
      -- xxx: look this up from the player info when that is avaiable
      local kingdom = stonehearth.population:get_population(player_id)
                                                :get_kingdom()

      -- start out with the default undercrops for this player's kingdom.
      undercrop_list = {}
      local all_undercrops = self._all_undercrops
      local kingdom_undercrops = self._initial_undercrops[kingdom]
      if kingdom_undercrops and all_undercrops then
         for key, undercrop in pairs(all_undercrops) do
            undercrop_list[key] = {
               undercrop_key = key,
               undercrop_type = undercrop.undercrop_type,
               undercrop_info = self:get_undercrop_details(undercrop.undercrop_type),
               undercrop_level_requirement = undercrop.level_requirement,
               ordinal = undercrop.ordinal,
               initial_undercrop = kingdom_undercrops[key]
            }
         end
      end
      self._data.player_undercrops[player_id] = undercrop_list
   end
   return undercrop_list
end

function UnderfarmingService:harvest_undercrops(session, substrate_plots)
   if not substrate_plots[1] then
      return false
   end
   local town = stonehearth.town:get_town(session.player_id)
   for i, plot in ipairs(substrate_plots) do
      local plot_component = plot:get_component('stonehearth_ace:substrate_plot')
      local underplant = plot_component:get_contents()
      if underplant then
         town:harvest_undercrop(underplant)
      end
   end
   return true
end

-- Passed to find_best_reachable_entity_by_type to choose which underfield to work on.
function UnderfarmingService.rate_underfield(underfield_layer, entity)
   local underfield = underfield_layer:get_component('stonehearth_ace:grower_underfield_layer'):get_grower_underfield()
   local underfarming = stonehearth.constants.farming
   local competition_score = 1 - math.min(underfarming.MAX_RELEVANT_FARMERS, underfield:get_worker_count(entity)) / underfarming.MAX_RELEVANT_FARMERS
   
   local distance = radiant.entities.distance_between_entities(underfield_layer, entity)
   local distance_score = 1 - math.min(underfarming.MAX_RELEVANT_DISTANCE, distance) / underfarming.MAX_RELEVANT_DISTANCE
   
   return competition_score * underfarming.COMPETITION_WEIGHT + distance_score * underfarming.DISTANCE_WEIGHT
end

return UnderfarmingService
