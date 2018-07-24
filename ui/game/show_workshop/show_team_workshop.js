$(top).on('stonehearthReady', function() {
   // Create a proxy for the workshops object, so we know when a new StonehearthTeamCrafterView is created
   // and can then update it with our own logic.
   App.workshopManager.ace_workshops = App.workshopManager.workshops;
   App.workshopManager.workshops = new Proxy(App.workshopManager.ace_workshops, {
      get: function(target, prop) {
         return Reflect.get(target, prop);
      },
      set: function(target, prop, val) {
         App.workshopManager._ace_updateTeamCrafterView(val);
         return Reflect.set(target, prop, val);
      }
   });

   App.workshopManager._ace_updateTeamCrafterView = function(teamCrafterView) {
      teamCrafterView.reopen({
         didInsertElement: function() {
            this._super();
            var self = this;

            // Craft or maintain on click/ctrl+click of right mouse button.
            // Replaces the original in super to incorporate the ability to specify the position of the order.
            this.$('#recipeItems').off('mousedown.craftOrMaintain', '.item');
            this.$('#recipeItems').on('mousedown.craftOrMaintain', '.item', function (e) {
               var orderArgs;
               if (e.button == 2) {
                  if (e.ctrlKey) {
                     orderArgs = { type: "maintain", at_least: 1 };
                  } else {
                     orderArgs = { type: "make", amount: 1 };
                  }
                  if (e.shiftKey) {
                     orderArgs.order_index = 1;
                  }
               }
               if (orderArgs) {
                  var recipe = self._getOrCalculateRecipeData($(this).attr('recipe_key'));
                  radiant.call_obj(self.getOrderList(), 'add_order_command', recipe, orderArgs)
                     .done(function(return_data){
                        radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:confirm'} );
                     });
               }
            });
         }
      });
   };
});
