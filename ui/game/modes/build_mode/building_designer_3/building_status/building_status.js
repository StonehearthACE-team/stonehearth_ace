App.StonehearthBuildingStatusView = App.View.extend({
   templateName: 'buildingStatus',
   uriProperty: 'model',

   components: {
      'stonehearth:unit_info': {},
      'stonehearth:build2:building' : '*'
   },

   init: function() {
      var self = this;
      self._expanded = false;
      self._building_service = null;
      self._current_building = null;
      self._super();
      self.set('building', false);

      radiant.call('stonehearth:get_client_service', 'building')
         .done(function(e) {
            self._onServiceReady(e.result);
         })
         .fail(function(e) {
            console.log('error getting building service');
            console.dir(e);
         });
   },

   _controlButtonsEnabled: function() {
      var self = this;

      var player_id = App.stonehearthClient.getPlayerId();
      var controlsEnabled = self.get('model.player_id') == player_id;

      if (controlsEnabled) {
         var buildButton = self.$('#buildButton');
         buildButton.removeClass('disabled');

         // ACE: add tooltip for build button with additional information
         App.tooltipHelper.createDynamicTooltip(buildButton, function () {
            if (buildButton.hasClass('preBuild')) {
               var tooltipString = i18n.t('stonehearth_ace:ui.game.build_mode2.building_status.build_button_description');
               return $(App.tooltipHelper.createTooltip(i18n.t('stonehearth_ace:ui.game.build_mode2.building_status.build_button_title'), tooltipString));
            }
            else {
               return null;
            }
         });

         var destroyButton = $('#buildingSystemMenuContents #destroy');
         destroyButton.removeClass('disabled');
         var tooltipString = destroyButton.attr('tooltip');
         destroyButton.tooltipster('destroy');
         destroyButton.tooltipster({content: tooltipString});
      } else {
         var buildButton = self.$('#buildButton');
         buildButton.addClass('disabled');
         buildButton.tooltipster({content: i18n.t("stonehearth:ui.game.build_mode2.tooltips.disabled.build")});

         var destroyButton = $('#buildingSystemMenuContents #destroy');
         destroyButton.addClass('disabled');
         destroyButton.tooltipster('destroy');
         destroyButton.tooltipster({content: i18n.t("stonehearth:ui.game.build_mode2.tooltips.disabled.destroy")});
      }
   },

   _onServiceReady: function(service) {
      var self = this;

      self._building_service = service;
      self._building_service_trace = radiant.trace(self._building_service).progress(function(change) {
         if (change.current_building != self._current_building) {
            self._current_building = change.current_building;
            self.set('uri', change.current_building);
         } else {
            self._onBuildingChanged();
         }
      });
   },

   _onBuildingChanged: function() {
      var self = this;

      var building = self.get('model');

      if (!building || building['stonehearth:unit_info'] == null) {
         self.$('#buildingName').val('');
         self.$('.itemCount.count').text();
         self._updateCosts({}, {});
         return;
      }

      var buildingName = '';
      if (building['stonehearth:unit_info'].custom_name) {
         buildingName = building['stonehearth:unit_info'].custom_name;
      } else {
         buildingName = i18n.t(building['stonehearth:unit_info'].display_name, {self: building});
      }
      self.$('#buildingName').val(buildingName);

      self._onBuildingStatusChanged();

      self._updateCosts(
         building['stonehearth:build2:building'].resource_cost,
         building['stonehearth:build2:building'].item_cost);

      Ember.run.scheduleOnce('afterRender', self, '_controlButtonsEnabled');
   }.observes('model'),

   _onBuildingStatusChanged: function() {
      var self = this;

      var building = self.get('model');
      var status;

      if (!building || building['stonehearth:build2:building'] == null) {
         status = App.constants.building.building_status.FINISHED;
      } else {
         status = building['stonehearth:build2:building'].building_status;
      }

      Ember.run.scheduleOnce('afterRender', self, '_controlButtonsEnabled');
      self.set('building', status == App.constants.building.building_status.BUILDING);
      self.set('paused', status == App.constants.building.building_status.PAUSED);
      self.set('finished', status == App.constants.building.building_status.FINISHED);
   }.observes('model.stonehearth:build2:building.building_status'),

   _onPlanStatusChanged: function() {
      var self = this;
      var building = self.get('model');

      if (!building) {
         return;
      }

      if (!building['stonehearth:build2:building']) {
         return;
      }

      if (building['stonehearth:build2:building'].plan_job_status == App.constants.building.plan_job_status.PLANNING_ERROR_GENERIC) {
         if (self._last_plan_status != App.constants.building.plan_job_status.PLANNING_ERROR_GENERIC) {
            App.stonehearthClient.showTip(i18n.t('stonehearth:ui.game.build2.plan_job_status.PLANNING_ERROR_GENERIC'), null, {
               timeout: 5000
            });
         }
      }
      self._last_plan_status = building['stonehearth:build2:building'].plan_job_status;
   }.observes('model.stonehearth:build2:building.plan_job_status'),

   _updateCosts: function(resources, items) {
      var self = this;

      var itemCount = 0;
      _.forEach(items, function(count) {
         itemCount += count;
      });
      self.$('.itemCount.count').text(' ' + itemCount);

      var newResList = [];
      _.forEach(resources, function(amount, resource_name) {
         var e = self._buildResourceCostEl(resource_name, amount);
         newResList.push(e);
      });
      self.set('resources', newResList);
   },

   _onResourcesChanged: function() {
      var self = this;

      var building = self.get('model');
      if (!building || !building['stonehearth:build2:building']) {
         return;
      }
      self._updateCosts(
         building['stonehearth:build2:building'].resource_cost,
         building['stonehearth:build2:building'].item_cost);
   }.observes('model.stonehearth:build2:building.resource_cost'),

   _onItemsChanged: function() {
      var self = this;
      var building = self.get('model');
      if (!building || !building['stonehearth:build2:building']) {
         return;
      }
      self._updateCosts(
         building['stonehearth:build2:building'].resource_cost,
         building['stonehearth:build2:building'].item_cost);
   }.observes('model.stonehearth:build2:building.item_cost'),

   _buildResourceCostEl: function(resource_name, amount) {
      var resInfo = App.resourceConstants.resources[resource_name];
      var data = {
         style : "background-image: url(" + (resInfo ? resInfo.builder_icon : "") + ")",
         count : (resInfo ? Math.ceil(amount / resInfo.stacks) : amount)
      };
      return data;
   },

   didInsertElement: function() {
      var self = this;
      this._super();

      self.$('#buildingName').keydown(function (e) {
         if (e.keyCode == 13 && !e.originalEvent.repeat) {  // enter
            $(this).blur();
         } else if (e.keyCode == 27 && !e.originalEvent.repeat) {  // esc
            self._onBuildingChanged();  // Reset name.
            $(this).blur();
            return false;
         }
      });
      self.$('#buildingName').blur(function (e) {
         radiant.call_obj('stonehearth.building', 'set_building_name_command', self.$('#buildingName').val())
            .done(function (r) {
               radiant.call_obj('stonehearth.building', 'save_building_command');
            });
      });

      self.$('#downButton').click(function() {
         if (!self._expanded) {
            self._expanded = true;
            self.$('#buildingStatusRoot').removeClass('unexpanded').addClass('expanded');
            self.$('#costDetails').toggle();
         } else {
            self._expanded = false;
            self.$('#buildingStatusRoot').removeClass('expanded').addClass('unexpanded');
            self.$('#costDetails').toggle();
         }
         radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_cost_tab'});
      });

      // ACE: track shift key status for craft queuing
      $(document).on('keyup keydown', function(e){
         self.SHIFT_KEY_ACTIVE = e.shiftKey;
      });
   },

   _showPlanStatus: function(status_name) {
      if (!status_name) {
         return;
      }
      App.stonehearthClient.showTip(i18n.t('stonehearth:ui.game.build2.plan_job_status.' + status_name), null, {
         timeout: 5000
      });
   },

   actions: {
      build: function() {
         var self = this;
         var building = self.get('model');

         if (!building) {
            return;
         }

         // ACE: pass additional information to the building service about craft queuing
         var isPreBuild = self.$('#buildButton.prebuild') != null;

         radiant.call_obj('stonehearth.building', 'build', isPreBuild && self.SHIFT_KEY_ACTIVE)
            .done(function(r) {
               var result = r.result;

               switch(result) {
                  case App.constants.building.plan_job_status.WORKING:
                  case App.constants.building.plan_job_status.COMPLETE:
                     radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_select_build'});
                     break;

                  default:
                     radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:building_error_notify'});
                     break;
               }

               if (result != App.constants.building.plan_job_status.WORKING) {
                  var key = null;
                  _.forEach(App.constants.building.plan_job_status, function(v, k) {
                     if (v == result) {
                        key = k;
                        return true;
                     }
                  });
                  self._showPlanStatus(key);
               }
            });
      },

      pause: function() {
         var self = this;
         var building = self.get('model');

         if (!building) {
            return;
         }

         radiant.call_obj('stonehearth.building', 'pause_building')
            .done(function(r) {
            });
      },

      resume: function() {
         var self = this;
         var building = self.get('model');

         if (!building) {
            return;
         }

         radiant.call_obj('stonehearth.building', 'resume_building')
            .done(function(r) {
            });
      }
   }
});
