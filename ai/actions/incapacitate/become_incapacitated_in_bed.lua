local BecomeIncapacitatedInBed = radiant.class()

BecomeIncapacitatedInBed.name = 'become incapacitated'
BecomeIncapacitatedInBed.does = 'stonehearth_ace:become_incapacitated'
BecomeIncapacitatedInBed.status_text_key = 'stonehearth:ai.actions.status_text.incapacitated'
BecomeIncapacitatedInBed.args = {
   in_bed = 'boolean'
}
BecomeIncapacitatedInBed.priority = 0

function BecomeIncapacitatedInBed:start_thinking(ai, entity, args)
   if args.in_bed then
      ai:set_think_output({})
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(BecomeIncapacitatedInBed)
   :execute('stonehearth:trigger_event', {
      source = ai.ENTITY,
      event_name = 'stonehearth:entity:be_incapacitated',
      synchronous = true,
   })
