local BecomeIncapacitatedOutOfBed = radiant.class()

BecomeIncapacitatedOutOfBed.name = 'become incapacitated'
BecomeIncapacitatedOutOfBed.does = 'stonehearth_ace:become_incapacitated'
BecomeIncapacitatedOutOfBed.status_text_key = 'stonehearth:ai.actions.status_text.incapacitated'
BecomeIncapacitatedOutOfBed.args = {
   in_bed = 'boolean'
}
BecomeIncapacitatedOutOfBed.priority = 0

function BecomeIncapacitatedOutOfBed:start_thinking(ai, entity, args)
   if not args.in_bed then
      ai:set_think_output({})
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(BecomeIncapacitatedOutOfBed)
   :execute('stonehearth:clear_carrying_now')
   :execute('stonehearth:run_effect', { effect = 'goto_knockout' })
   :execute('stonehearth:trigger_event', {
      source = ai.ENTITY,
      event_name = 'stonehearth:entity:be_incapacitated',
      synchronous = true,
   })
