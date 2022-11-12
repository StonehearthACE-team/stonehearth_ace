App.StonehearthBuildingStatusView.reopen({
   didInsertElement: function() {
      var self = this;
      this._super();

      $(document).on('keyup keydown', function(e){
         self.SHIFT_KEY_ACTIVE = e.shiftKey;
      });
   },

   _controlButtonsEnabled: function() {
      var self = this;

      var player_id = App.stonehearthClient.getPlayerId();
      var controlsEnabled = self.get('model.player_id') == player_id;

      if (controlsEnabled) {
         var buildButton = self.$('#buildButton');
         buildButton.removeClass('disabled');

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

   actions: {
      build: function() {
         var self = this;
         var building = self.get('model');

         if (!building) {
            return;
         }

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
      }
   }
});
