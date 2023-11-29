App.StonehearthBuildingSystemMenuView = App.View.extend({
   templateName: 'buildingSystemMenu',

   init: function() {
      var self = this;
      self._super();

   },

   didInsertElement: function() {
      var self = this;
      this._super();
      Ember.run.scheduleOnce('afterRender', self, '_updateSystemMenuTooltips');
   },

   _updateSystemMenuTooltips: function() {
      var self = this;

      self.$('.systemTool').each(function() {
         if (!$(this).hasClass('disabled')) {
            var tooltipString = $(this).attr('tooltip');
            $(this).tooltipster({content: tooltipString});
         }
      });
   },

   actions: {
      newBuilding: function() {
         var self = this;

         var doNewBuilding = function() {
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_button'});
            radiant.call_obj('stonehearth.building', 'new_building_command')
               .done(function(r) {
                  // building_service will select that new building for us.
               })
               .fail(function(e) {
                  console.assert(false, e);
               });
         };

         App.gameView.addView(App.StonehearthConfirmView,
            {
               title : i18n.t('stonehearth:ui.game.build2.new_building_confirm.title'),
               message : i18n.t('stonehearth:ui.game.build2.new_building_confirm.message'),
               buttons : [
                  {
                     id: 'confirmNewBuilding',
                     label: i18n.t('stonehearth:ui.game.build2.new_building_confirm.yes'),
                     click: doNewBuilding
                  },
                  {
                     label: i18n.t('stonehearth:ui.game.build2.new_building_confirm.no')
                  }
               ]
            });
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_button'});
      },

      templateList: function() {
         var self = this;
         _.forEach(self.get('childViews'), function(v) {
            if (v.templateName == 'templateList') {
               if (!v.visible()) {
                  v.show();
               } else {
                  v.hide();
               }

               return true;
            }
         });
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_menu'});
      },

      saveBuilding: function() {
         var self = this;
         App.stonehearthClient.showTip(i18n.t('stonehearth:ui.game.build2.saving_building'));

         var doSaveBuilding = function () {
         radiant.call_obj('stonehearth.building', 'save_building_command')
            .done(function(r) {
               // building_service will select that new building for us.
               App.stonehearthClient.showTip(i18n.t('stonehearth:ui.game.build2.success_saving_building'), null, {
                  timeout: 2500
               });
            })
            .fail(function(e) {
               App.stonehearthClient.showTip(i18n.t('stonehearth:ui.game.build2.error_saving_building'), {
                  timeout: 2500
               });
            });
         };

         App.gameView.addView(App.StonehearthConfirmView,
            {
               title : i18n.t('stonehearth:ui.game.build2.save_building_confirm.title'),
               message : i18n.t('stonehearth:ui.game.build2.save_building_confirm.message'),
               buttons : [
                  {
                     id: 'confirmSaveBuilding',
                     label: i18n.t('stonehearth:ui.game.build2.save_building_confirm.yes'),
                     click: doSaveBuilding
                  },
                  {
                     label: i18n.t('stonehearth:ui.game.build2.save_building_confirm.no'),
                     click: function() {
                        App.stonehearthClient.hideTip();
                     }
                  }
               ]
            });

         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_button'});
      },

      loadTemplate: function(fileName) {
         var self = this;
         radiant.call_obj('stonehearth.building', 'do_tool_command', 'load_building_command', false, fileName)
            .done(function(r) {
               // building_service will select that new building for us.
            })
            .fail(function(e) {
            });
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_button'});
      },

      destroy: function() {
         var self = this;

         var destroyButton = self.$('#destroy');
         if (destroyButton && destroyButton.hasClass('disabled')) {
            return;
         }

         var doDestroyBuilding = function(restore_terrain) {
            // TODO: destory building sound?
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_button'});
            radiant.call_obj('stonehearth.building', 'destroy_building_command', restore_terrain)
               .done(function(r) {
               })
               .fail(function(e) {
                  console.assert(false, e);
               });
         };

         var normalDestroy = function() { doDestroyBuilding(true); };
         var destroyWithoutTerrain = function() { doDestroyBuilding(false); };

         // query the build status view via the build mode view via the game mode manager
         // to see if the current building is more than just a blueprint
         var buildView = App.getCurrentGameModeView();
         var buildingDesginerView = buildView && buildView.getBuildingDesignerView();
         var buildingStatusView = buildingDesginerView && buildingDesginerView.getBuildingStatusView();
         if (buildingStatusView && buildingStatusView.isActiveBuildingBlueprint()) {
            // do a simpler confirmation dialog that doesn't talk about terrain
            App.gameView.addView(App.StonehearthConfirmView,
               {
                  title : i18n.t('stonehearth_ace:ui.game.build2.destroy_building_blueprint_confirm.title'),
                  message : i18n.t('stonehearth_ace:ui.game.build2.destroy_building_blueprint_confirm.message'),
                  buttons : [
                     {
                        id: 'confirmDestroyBuilding',
                        label: i18n.t('stonehearth_ace:ui.game.build2.destroy_building_blueprint_confirm.yes'),
                        click: normalDestroy
                     },
                     {
                        label: i18n.t('stonehearth_ace:ui.game.build2.destroy_building_blueprint_confirm.no'),
                        click: function() {
                           App.stonehearthClient.hideTip();
                        }
                     }
                  ]
               });
         }
         else {
            App.gameView.addView(App.StonehearthConfirmView,
               {
                  title : i18n.t('stonehearth:ui.game.build2.destroy_building_confirm.title'),
                  message : i18n.t('stonehearth:ui.game.build2.destroy_building_confirm.message'),
                  buttons : [
                     {
                        id: 'normalDestroy',
                        label: i18n.t('stonehearth_ace:ui.game.build2.destroy_building_confirm.very_yes'),
                        tooltip: i18n.t('stonehearth_ace:ui.game.build2.destroy_building_confirm.very_yes_description'),
                        click: normalDestroy
                     },
                     {
                        id: 'destroyWithoutTerrain',
                        label: i18n.t('stonehearth_ace:ui.game.build2.destroy_building_confirm.yes'),
                        tooltip: i18n.t('stonehearth_ace:ui.game.build2.destroy_building_confirm.yes_description'),
                        click: destroyWithoutTerrain
                     },
                     {
                        label: i18n.t('stonehearth:ui.game.build2.destroy_building_confirm.no'),
                        tooltip: i18n.t('stonehearth_ace:ui.game.build2.destroy_building_confirm.no_description'),
                        click: function() {
                           App.stonehearthClient.hideTip();
                        }
                     }
                  ]
               });
         }
      }
   }
});
