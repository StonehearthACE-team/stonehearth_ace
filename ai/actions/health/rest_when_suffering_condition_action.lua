local RestWhenSufferingCondition = radiant.class()
RestWhenSufferingCondition.name = 'rest when injured'
RestWhenSufferingCondition.does = 'stonehearth:rest_when_injured'
RestWhenSufferingCondition.args = {}
RestWhenSufferingCondition.priority = {0, 1}

function RestWhenSufferingCondition:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get(0)
end

local ai = stonehearth.ai
return ai:create_compound_action(RestWhenSufferingCondition)
            :execute('stonehearth_ace:wait_for_special_attention_condition')
            :execute('stonehearth:rest_from_injuries', {
               rest_from_conditions = true,
            })
