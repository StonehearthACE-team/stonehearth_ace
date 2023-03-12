local constants = require 'stonehearth.constants'

local RestockTaskGroup = class()
RestockTaskGroup.name = 'restock'
RestockTaskGroup.does = 'stonehearth:top'
RestockTaskGroup.priority = {0.1, 0.12}
RestockTaskGroup.sunk_cost_boost = 0.15

return stonehearth.ai:create_task_group(RestockTaskGroup)
         :work_order_tag("haul")
         :declare_permanent_task('stonehearth:execute_restock_errand', { type_id = constants.inventory.restock_director.types.RESTOCK }, {0, 0.8})
         :declare_permanent_task('stonehearth:execute_restock_errand', { type_id = constants.inventory.restock_director.types.INPUT_BIN }, {0.5, 1})
