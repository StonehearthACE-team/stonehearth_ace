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
         SHIFT_KEY_ACTIVE: false,

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
                        if (self.isDestroyed || self.isDestroying) {
                           return;
                        }
                        radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:confirm'} );
                     });
               }
            });

            var craftInsertDiv = self.$('#craftInsert');
            $(document).on('keyup keydown', function(e){
               self.SHIFT_KEY_ACTIVE = e.shiftKey;
               self._updateCraftInsertShown(craftInsertDiv);
            });

            $('#craftButton').hover(
               function() {
                  self.HOVERING_CRAFT_BUTTON = true;
                  self._updateCraftInsertShown(craftInsertDiv);
               },
               function() {
                  self.HOVERING_CRAFT_BUTTON = false;
                  self._updateCraftInsertShown(craftInsertDiv);
               }
            );
            var tooltip = App.tooltipHelper.createTooltip(
               i18n.t('stonehearth_ace:ui.game.show_workshop.craft_button.title'),
               i18n.t('stonehearth_ace:ui.game.show_workshop.craft_button.description'));
            self.$('#craftButton').tooltipster({
               delay: 1000,
               content: $(tooltip)
            });

            tooltip = App.tooltipHelper.createTooltip(
               i18n.t('stonehearth_ace:ui.game.show_workshop.quality_preference.title'),
               i18n.t('stonehearth_ace:ui.game.show_workshop.quality_preference.description'));
            self.$('#qualityPreference').tooltipster({
               delay: 1000,
               content: $(tooltip)
            });

            self._updateCraftOrderPreference();
         },

         _updateCraftInsertShown: function(div) {
            var self = this;

            if (self.SHIFT_KEY_ACTIVE && self.HOVERING_CRAFT_BUTTON) {
               div.show();
            }
            else {
               div.hide();
            }
         },

         _addExtraCraftOrderConditions: function(recipe, condition) {
            var self = this;

            condition.prefer_high_quality = self.get('prefer_high_quality');
            if (self.SHIFT_KEY_ACTIVE) {
               condition.order_index = 1;
            }
         },

         _setRadioButtons: function (remaining, maintainNumber) {
            var self = this;
            self._super(remaining, maintainNumber);

            self._updateCraftOrderPreference();
         },

         _updateCraftOrderPreference: function() {
            var self = this;
            
            radiant.call('radiant:get_config', 'mods.stonehearth_ace.default_craft_order_prefer_high_quality')
            .done(function(o) {
               if (self.isDestroyed || self.isDestroying) {
                  return;
               }
               var prefer_high_quality = o['mods.stonehearth_ace.default_craft_order_prefer_high_quality'];
               if (prefer_high_quality != false) {
                  prefer_high_quality = true;
               }
               self.set('prefer_high_quality', prefer_high_quality);
            });
         },

         actions: {
            craft: function () {
               var self = this;
      
               if (self.$('#craftButtonLabel').hasClass('disabled')) {
                  // TODO: play a error sound here?
                  return;
               }
               radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:carpenter_menu:confirm'} );
               var recipe = this._getOrCalculateRecipeData(this.currentRecipe.recipe_key);
      
               var condition;
               var type = self.$('input[name=' + self.get('orderTypeName') + ']:checked').val();
               if (type == "maintain") {
                  condition = {
                     type: "maintain",
                     at_least: App.stonehearth.validator.enforceNumRange(self.$('#maintainNumSelector')),
                  };
               } else {
                  condition = {
                     type: "make",
                     amount: App.stonehearth.validator.enforceNumRange(self.$('#makeNumSelector')),
                  };
               }

               // now add the ACE options
               self._addExtraCraftOrderConditions(recipe, condition);

               console.log('craft', recipe, condition)
               radiant.call_obj(this.getOrderList(), 'add_order_command', recipe, condition)
            }
         }
      });
   };
});
