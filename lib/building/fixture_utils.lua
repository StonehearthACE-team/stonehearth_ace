local Region2 = _radiant.csg.Region2
local Region3 = _radiant.csg.Region3
local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Color4 = _radiant.csg.Color4

local fixture_json_cache = {}
local MIDDLE_OFFSET = Point3(0.5, 0, 0.5)

local log = radiant.log.create_logger('build.fixture_utils')

local function _get_fixture_json(uri)
   local json = fixture_json_cache[uri]
   if not json then
      json = radiant.resources.load_json(uri)
      fixture_json_cache[uri] = json
   end
   return json
end

-- paulthegreat: this function was actually changed
local function _load_cutter(components)
   local portal = components['stonehearth:portal']
   if not portal or not portal.cutter then
      return Region3()
   end

   local region2 = Region2()
   region2:load(portal.cutter)
   local bounds = region2:get_bounds()

   if portal.horizontal then
      return Region3(Cube3(Point3(bounds.min.x, 0, bounds.min.y),
                           Point3(bounds.max.x, 1, bounds.max.y)))
   else
      return Region3(Cube3(Point3(bounds.min.x, bounds.min.y, 0),
                           Point3(bounds.max.x, bounds.max.y, 1)))
   end
end

local function _get_region_origin(region, rotation, origin)
   if origin then
      origin = Point3(origin.x, origin.y, origin.z)
   else
      local bounds = region:get_bounds()
      origin = Point3((bounds.max.x + bounds.min.x) * 0.5, 0, (bounds.max.z + bounds.min.z) * 0.5)
   end
   return -(origin:rotated(rotation) - MIDDLE_OFFSET):to_closest_int()
end

local fixture_utils = {}

function fixture_utils.rotation_from_direction(direction)
   if direction == -Point3.unit_z then
      return 0
   elseif direction == -Point3.unit_x then
      return 90
   elseif direction == Point3.unit_z then
      return 180
   elseif direction == Point3.unit_x then
      return 270
   end
   return 0
end

function fixture_utils.rotate_region(region, rotation, origin)
   local origin = _get_region_origin(region, rotation, origin)

   return region:rotated(rotation):translated(origin)
end

function fixture_utils.get_placement_from_uri(uri)
   local json = _get_fixture_json(uri)
   local components = json.components
   if not components then
      return false, false, false
   end

   local entity_forms = components['stonehearth:entity_forms']
   if not entity_forms then
      return false, false, false
   end

   local g = entity_forms.placeable_on_ground
   if g == nil then
      g = false
   end

   local w = entity_forms.placeable_on_walls
   if w == nil then
      w = false
   end

   local f = entity_forms.fence
   if f == nil then
      f = false
   end

   return w, g, f
end

function _get_bounds_from_json(json)
   local components = json.components

   if not components then
      return Region3()
   end

   -- Prefer portals over rcs.
   local portal = components['stonehearth:portal']
   local rcs = components['region_collision_shape']
   local mob = components['mob']

   local region
   if portal and portal.cutter then
      region = _load_cutter(components)
   elseif rcs and rcs.region then
      region = Region3()
      region:load(rcs.region)
   elseif mob and mob.mob_collision_type then
      if mob.mob_collision_type == 'tiny' or mob.mob_collision_type == 'clutter' then
         region = Region3(Cube3(Point3(0, 0, 0), Point3(1, 1, 1)))
      else
         region = Region3()
      end
   end

   return region or Region3()
end

function fixture_utils.get_bounds_from_uri(uri, rotation)
   local json = _get_fixture_json(uri)
   local region = _get_bounds_from_json(json)

   if region:empty() then
      return region
   end

   return fixture_utils.rotate_region(region, rotation, json.components['mob'].region_origin)
end

function fixture_utils.get_grid_align_from_uri(uri)
   local json = _get_fixture_json(uri)
   local components = json.components
   if not components then
      return nil
   end

   if not components['mob'] then
      return nil
   end

   return components['mob'].align_to_grid
end

function fixture_utils.get_cutter_from_uri(uri, rotation)
   local json = _get_fixture_json(uri)
   local components = json.components

   if not components then
      return Region3()
   end

   local region = _load_cutter(components)
   if not region then
      return Region3()
   end
   return fixture_utils.rotate_region(region, rotation, components['mob'].region_origin)
end

function fixture_utils.bounds_origin_from_entity(entity)
   local json = _get_fixture_json(entity:get_uri())
   local o = json.components['mob'].region_origin

   if not o then
      local bounds = _get_bounds_from_json(json)
      o = bounds:get_bounds():get_centroid()
   end

   return Point3(o.x, o.y, o.z)
end

function fixture_utils.model_origin_from_entity(entity)
   local json = _get_fixture_json(entity:get_uri())
   local o = json.components['mob'].model_origin

   if not o then
      return Point3(0, 0, 0)
   end

   return Point3(o.x, o.y, o.z)
end

function fixture_utils.bounds_from_entity(entity)
   local json = _get_fixture_json(entity:get_uri())
   return _get_bounds_from_json(json)
end

function fixture_utils.is_portal(uri)
   local json = _get_fixture_json(uri)
   return json.components['stonehearth:portal'] ~= nil
end

function fixture_utils.is_hatch(uri)
	local json = _get_fixture_json(uri)
	local portal = json.components['stonehearth:portal']
	if portal then
		return portal.horizontal
	end
	return false
end


fixture_utils.filter = {}
fixture_utils.filter._ignored_uris = {
   ['stonehearth:ui:entities:selection'] = true,
   ['stonehearth:ui:entities:stabber'] = true,
   ['stonehearth:ui:entities:dragger_anchor'] = true,
   ['stonehearth:debug_shapes:box'] = true,
   ['stonehearth:build2:entities:fixture_widget'] = true,
}

fixture_utils.filter.STOP = 0
fixture_utils.filter.ACCEPT = 1
fixture_utils.filter.IGNORE = 2

local function _is_solid_thing(e)
   if radiant.entities.is_solid_entity(e) then
      return true
   end

   if e:get_uri() == 'stonehearth:build2:entities:structure' then
      return true
   end

   -- Non-fixture blueprints are certainly solid.
   local bp = e:get('stonehearth:build2:blueprint')
   if bp and bp:get_uri() ~= 'stonehearth:build2:entities:fixture_blueprint' then
      return true
   end

   return false
end

local function _is_structure(e)
   local bp = e:get('stonehearth:build2:blueprint')
   if bp and bp:get_uri() ~= 'stonehearth:build2:entities:fixture_blueprint' then
      return true
   end

   -- Fixtures will NOT have any widget entity data on them, but all other structures
   -- will.
   local ed = radiant.entities.get_entity_data(e, 'stonehearth:build2:widget')
   return ed ~= nil
end

function fixture_utils.filter_for_fixture_placement(e, normal, ignore_id, allow_ground, allow_wall)
   if not e or not e:is_valid() then
      -- This covers the case of the ray intersecting a 'temp' object that is a proxy
      -- for other geometry.
      if not allow_ground and normal.y ~= 0.0 then
         return fixture_utils.filter.STOP
      end

      if not allow_wall and normal.y == 0.0 then
         return fixture_utils.filter.STOP
      end

      return fixture_utils.filter.ACCEPT
   end

   local entity_uri = e:get_uri()

   if ignore_id == e:get_id() then
      return fixture_utils.filter.IGNORE
   elseif fixture_utils.filter._ignored_uris[entity_uri] then
      return fixture_utils.filter.IGNORE
   end

   if not allow_ground and normal.y ~= 0.0 then
      return fixture_utils.filter.STOP
   end

   if not allow_wall and normal.y == 0.0 then
      return fixture_utils.filter.STOP
   end

   if _is_solid_thing(e) then
      return fixture_utils.filter.ACCEPT
   end

   local ed = radiant.entities.get_entity_data(e, 'stonehearth:build2:widget')
   if ed then
      local c = e:get(ed.component)
      if stonehearth.building:is_building(c:get_data():get_building_id()) then
         return fixture_utils.filter.IGNORE
      end
      return fixture_utils.filter.ACCEPT
   end

   return fixture_utils.filter.IGNORE
end

-- paulthegreat: this function was actually changed
function fixture_utils.find_fixture_placement(p, entity, is_portal, is_fence, fixture_bounds, region_origin, allow_ground, rotation, allow_wall)
   local results = _radiant.client.query_scene(p.x, p.y)
   local widget_id = entity and entity:get_id() or nil
   local bid = entity and entity:get('stonehearth:build2:fixture_widget'):get_bid() or nil
   local is_hatch = false
   local uri = entity and entity:get_uri()
   if uri then
      is_hatch = fixture_utils.is_hatch(uri)
   end

   for r in results:each_result() do
      local res = fixture_utils.filter_for_fixture_placement(r.entity, r.normal, widget_id, allow_ground, allow_wall)

      if res == fixture_utils.filter.STOP then
         return nil, nil, nil
      end

      if res == fixture_utils.filter.ACCEPT then
         local rot = rotation
         if r.normal.y == 0.0 then
            rot = fixture_utils.rotation_from_direction(r.normal)
         end
         local bounds_w = fixture_utils.rotate_region(fixture_bounds, rot or 0, region_origin):translated(r.brick)
         local support_bounds = Region3(bounds_w:duplicate():get_bounds())

         if not is_hatch and (not is_portal or (allow_ground and r.normal.y == 1)) then
            bounds_w = bounds_w:translated(r.normal)
            support_bounds = support_bounds - support_bounds:translated(r.normal)
         end

         -- The cursor position seems good; now check the support bounds against the world.
         local is_solid = entity and _is_solid_thing(entity) or true

         local es = radiant.terrain.get_entities_in_region(bounds_w, function(e)
               if fixture_utils.filter._ignored_uris[e:get_uri()] then
                  return false
               end
               -- Always ignore us, in either widget or blueprint form.
               if e:get_id() == widget_id then
                  return false
               end
               if e:get('stonehearth:build2:blueprint') then
                  if e:get('stonehearth:build2:blueprint'):get_data():get_bid() == bid then
                     return false
                  end
               end

               if (is_portal or is_hatch) and not is_fence then
                  -- Portals cannot intersect other portals, or solid fixtures,
                  -- but can intersect structures.
                  return not _is_structure(e)
               else
                  if is_fence then
                     -- Fences can intersect other fixtures; all other solid things are a 'no'
                     if e:get('stonehearth:build2:fixture_widget') then
                        return false
                     end
                     local bp = e:get('stonehearth:build2:blueprint')
                     if bp and bp:get_uri() == 'stonehearth:build2:entities:fixture_blueprint' then
                        return false
                     end

                     return _is_solid_thing(e)
                  elseif is_solid then
                     -- Cannot intersect structures, terrain, fixtures.
                     return _is_solid_thing(e)
                  end
               end

               return false
            end)

         local accept = radiant.empty(es)
         if accept then
            support_bounds = _physics:clip_region(support_bounds, _radiant.physics.Physics.CLIP_SOLID, 0)
            local es = radiant.terrain.get_entities_in_region(support_bounds, function(e)
                  return e:get_id() ~= widget_id
               end)
            for _, e in pairs(es) do
               local ed = radiant.entities.get_entity_data(e, 'stonehearth:build2:blueprint')
               if ed and _is_solid_thing(e) then
                  local data = e:get('stonehearth:build2:blueprint'):get_data()
                  support_bounds:subtract_region(data:get_world_shape())
               end
            end

            if support_bounds:get_area() == 0 then
               local e = r.entity and r.entity:is_valid()
               e = e and r.entity or nil
               local brick = r.brick + Point3.zero

               if not is_hatch and (not is_portal or (allow_ground and r.normal.y == 1)) then
                  brick = brick + r.normal
               end
			   
               return brick, e, r.normal
            end
         end
         return nil, nil, nil
      end
   end
   return nil, nil, nil
end


return fixture_utils
