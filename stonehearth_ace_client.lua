
-- Why this is a copy of the server script?
-- Shouldn't this be a client script?
-- Like the one in Rayya or NA mods?
-- Paul: as far as I can tell, the only stuff it was really missing from the stonehearth_client.lua script
--    was the on_server_ready stuff that I just now added. (The other stuff is generic stuff, but if you
--    see something else we should add, by all means, go ahead. I didn't look at RC or NA.)
--    So the thing about the monkey-patches is that if you use a component (like the portal_component below)
--    with both server and client services/scripts, you have to monkey-patch it in both places. The alternative
--    is to replace the file completely in the manifest, but as we know that limits compatibility with other mods.

stonehearth_ace = {}

local service_creation_order = {
   'connection_client',
   'heatmap',
   'gameplay_settings',
}

local monkey_patches = {
   --ace_follow_camera_controller = 'stonehearth.services.client.camera.follow_camera_controller',
   ace_building_client_service = 'stonehearth.services.client.building.building_client_service',
   ace_camera_service = 'stonehearth.services.client.camera.camera_service',
   ace_client_entities = 'radiant.modules.client_entities',
   ace_constants = 'stonehearth.constants',
   ace_csg_lib = 'stonehearth.lib.csg.csg_lib',
   ace_entity_forms_lib = 'stonehearth.lib.entity_forms.entity_forms_lib',
   ace_entity_or_location_selector = 'stonehearth.services.client.selection.entity_or_location_selector',
   ace_expendable_resources_renderer = 'stonehearth.renderers.expendable_resources.expendable_resources_renderer',
   ace_farmer_field_renderer = 'stonehearth.renderers.farmer_field.farmer_field_renderer',
   ace_farming_call_handler = 'stonehearth.call_handlers.farming_call_handler',
   ace_item_placer = 'stonehearth.services.client.build_editor.item_placer',
   ace_mining_call_handler = 'stonehearth.call_handlers.mining_call_handler',
   ace_mining_zone_renderer = 'stonehearth.renderers.mining_zone.mining_zone_renderer',
   ace_new_game_call_handler = 'stonehearth.call_handlers.new_game_call_handler',
   ace_place_item_call_handler = 'stonehearth.call_handlers.place_item_call_handler',
   ace_portal_component = 'stonehearth.components.portal.portal_component',
   ace_portrait_renderer_service = 'stonehearth.services.client.portrait_renderer.portrait_renderer_service',
   ace_presence_renderer = 'stonehearth.renderers.presence.presence_renderer',
   ace_presence_client_service = 'stonehearth.services.client.presence_client.presence_client_service',
   ace_renderer_service = 'stonehearth.services.client.renderer.renderer_service',
   ace_selection_service = 'stonehearth.services.client.selection.selection_service',
   ace_settings_call_handler = 'stonehearth.call_handlers.settings_call_handler',
   ace_shepherd_call_handler = 'stonehearth.call_handlers.shepherd_call_handler',
   ace_sound_service = 'stonehearth.services.client.sound.sound_service',
   ace_storage_renderer = 'stonehearth.renderers.storage.storage_renderer',
   ace_subterranean_view_service = 'stonehearth.services.client.subterranean_view.subterranean_view_service',
   ace_template_placement_tool = 'stonehearth.services.client.building.template_placement_tool',
   ace_terrain = 'radiant.modules.terrain',
   ace_util = 'radiant.lib.util',
   ace_xz_region_selector = 'stonehearth.services.client.selection.xz_region_selector',
   ace_zone_renderer = 'stonehearth.renderers.zone_renderer',
   ace_weather_render_service = 'stonehearth.services.client.weather_render.weather_render_service',
}

local function monkey_patching()
   for from, into in pairs(monkey_patches) do
      local monkey_see = require('monkey_patches.' .. from)
      local monkey_do = radiant.mods.require(into)
      radiant.log.write_('stonehearth_ace', 0, 'ACE client monkey-patching \'' .. from .. '\' => \'' .. into .. '\'')
      if monkey_see.ACE_USE_MERGE_INTO_TABLE then
         -- use merge_into_table to also mixin other values, not just functions
         radiant.util.merge_into_table(monkey_do, monkey_see)
      else
         radiant.mixin(monkey_do, monkey_see)
      end
   end
end

local function create_service(name)
   local path = string.format('services.client.%s.%s_service', name, name)
   local service = require(path)()

   local saved_variables = stonehearth_ace._sv[name]
   if not saved_variables then
      saved_variables = radiant.create_datastore()
      stonehearth_ace._sv[name] = saved_variables
   end

   service.__saved_variables = saved_variables
   service._sv = saved_variables:get_data()
   saved_variables:set_controller(service)
   saved_variables:set_controller_name('stonehearth_ace:' .. name)
   service:initialize()
   stonehearth_ace[name] = service
   radiant.log.write_('stonehearth_ace', 0, 'ACE client service initialized: %s', name)
end

local player_service_trace = nil

function stonehearth_ace:_on_init()
   local vi = self.version_info
   radiant.log.write_('stonehearth_ace', 0, 'Initializing ACE ' .. tostring(vi.branch) .. ' branch version ' .. tostring(vi.version) .. '...')

   local function check_override_ui(players, player_id)
      -- Load ui mod
      if not player_id then
         player_id = _radiant.client.get_player_id()
      end
      
      local client_player = players[player_id]
      if client_player then
         if client_player.kingdom == "stonehearth_ace:kingdoms:mountain_folk" then
            -- hot load stonehearth_ace ui mod
            _radiant.res.apply_manifest("/stonehearth_ace/mountain_folk/manifest.json")
            radiant.events.trigger(radiant, 'stonehearth_ace:client:client_manifest_applied')
         end
      end
   end
   radiant.events.listen(radiant, 'radiant:client:server_ready', function()
      _radiant.call('stonehearth:get_service', 'player')
         :done(function(r)
            local player_service = r.result
            player_service_trace = player_service:trace('stonehearth_ace ui change')
                  :on_changed(function(o)
                        check_override_ui(player_service:get_data().players)
                     end)
                  :push_object_state()
            end)

      for _, name in ipairs(service_creation_order) do
         if stonehearth_ace[name].on_server_ready then
            stonehearth_ace[name]:on_server_ready()
         end
      end

      stonehearth_ace.initialized = true
      radiant.events.trigger(radiant, 'stonehearth_ace:client:init')
      radiant.log.write_('stonehearth_ace', 0, 'ACE client initialized')
   end)

   stonehearth_ace._sv = stonehearth_ace.__saved_variables:get_data()

   self:_run_scripts('pre_ace_services')

   for _, name in ipairs(service_creation_order) do
      create_service(name)
   end
end

function stonehearth_ace:_on_required_loaded()
   monkey_patching()
   
   stonehearth_ace.monkey_patched = true
   radiant.events.trigger(radiant, 'stonehearth_ace:client:required_loaded')
end

function stonehearth_ace:_get_scripts_to_load()
   if not self.load_scripts then
      self.load_scripts = radiant.resources.load_json('stonehearth_ace/scripts/client_load_scripts.json')
   end
   return self.load_scripts
end

function stonehearth_ace:_run_scripts(category)
   local scripts = self:_get_scripts_to_load()
   if category and scripts[category] then
      for script, run in pairs(scripts[category]) do
         if run then
            local s = require(script)
            if s then
               s()
            end
         end
      end
   end
end

function stonehearth_ace:load_version_info()
   self.version_info = radiant.resources.load_json('stonehearth_ace/version.json') or {}
end

stonehearth_ace:load_version_info()
radiant.events.listen(stonehearth_ace, 'radiant:init', stonehearth_ace, stonehearth_ace._on_init)
radiant.events.listen(radiant, 'radiant:required_loaded', stonehearth_ace, stonehearth_ace._on_required_loaded)

return stonehearth_ace
