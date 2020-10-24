local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local ChangeJobUsingTalismanAction = radiant.class()

ChangeJobUsingTalismanAction.name = 'change job using talisman'
ChangeJobUsingTalismanAction.does = 'stonehearth:change_job'
ChangeJobUsingTalismanAction.status_text_key = 'stonehearth:ai.actions.status_text.promote'
ChangeJobUsingTalismanAction.args = {
   job_uri = 'string',
}
ChangeJobUsingTalismanAction.priority = 0

local make_talisman_filter_fn = function(player_id, uri)
   if radiant.util.is_string(uri) then
      uri = { uri }
   end
   table.sort(uri)
   local uris = {}
   local key = player_id
   for _, each_uri in ipairs(uri) do
      uris[each_uri] = true
      key = key .. ':' .. each_uri
   end
   local is_owned_by_another_player = radiant.entities.is_owned_by_another_player

   return stonehearth.ai:filter_from_key('stonehearth:pickup_item_with_uri', key, function (entity)
         if is_owned_by_another_player(entity, player_id) then
            -- player does not own this item
            return false
         end

         local root, iconic = entity_forms_lib.get_forms(entity)
         if root and iconic then
            -- if this is an object with entity forms

            -- if we found the iconic forms item, we can check for if it matches
            -- DO NOT pick up items that are the root. Otherwise we will
            -- try to undeploy items that the user has specifically placed!
            if entity == iconic then
               -- if we are specifically looking for the iconic uri, then we're good
               if uris[entity:get_uri()] then
                  return true
               end

               -- else if we are looking for the root's uri and it matches, then good.
               if uris[root:get_uri()] then
                  return true
               end
            end
         elseif uris[entity:get_uri()] then
            return true
         end
         return false
      end)
end

function ChangeJobUsingTalismanAction:start_thinking(ai, entity, args)
   local player_id = radiant.entities.get_player_id(entity)
   local job_controller = stonehearth.job:get_jobs_controller(player_id)
   local kingdom_job_data = job_controller:get_job_description(args.job_uri)
   local json = radiant.resources.load_json(kingdom_job_data, true)
   local talisman_uri = json.talisman_uri

   if talisman_uri then
      ai:set_think_output({
         player_id = player_id,
            talisman_filter_fn = make_talisman_filter_fn(player_id, talisman_uri),
            trigger_fn = function(info, trigger_args)
               if info.event == "change_outfit" then
                  entity:add_component('stonehearth:job')
                      :promote_to(args.job_uri, {talisman = trigger_args.talisman})
                  radiant.effects.run_effect(entity, 'stonehearth:effects:level_up')
               elseif info.event == "remove_talisman" then
                  -- TODO: for now destroy the talisman. Eventually store it in the talisman component so we can bring it back when the civ is demoted
                  radiant.entities.remove_carrying(entity)
                  radiant.entities.destroy_entity(trigger_args.talisman)
               elseif info.event == "effect_canceled" then
                  -- If the effect was cancelled, but we've already changed jobs, always destroy the talisman.
                  if entity:add_component('stonehearth:job'):get_job_uri() == args.job_uri then
                     radiant.entities.remove_carrying(entity)
                     radiant.entities.destroy_entity(trigger_args.talisman)
                  end
               end
            end
         })
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(ChangeJobUsingTalismanAction)
            :execute('stonehearth:drop_carrying_now')
            :execute('stonehearth:pickup_item_type', {
               filter_fn = ai.BACK(2).talisman_filter_fn,
               description = 'job talisman',
               owner_player_id = ai.BACK(2).player_id,
            })
            :execute('stonehearth:run_effect', {
               effect = 'promote',
               trigger_fn = ai.BACK(3).trigger_fn,
               args = { talisman = ai.PREV.item }
            })
