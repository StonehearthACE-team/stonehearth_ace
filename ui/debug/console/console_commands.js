function setDebugUIVisible(visible)
{
   $(".debugDock").css("display", visible ? 'block' : 'none');
}

$(document).ready(function(){
   if (App.StonehearthDebugDockView) {
      App.StonehearthDebugDockView.reopen({
         didInsertElement: function() {
            this._super();

            Ember.run.scheduleOnce('afterRender', this, function() {
               stonehearth_ace.getModConfigSetting('debugtools', 'show_debugtools_on_load', function(value) {
                  setDebugUIVisible(value);
               });
            });
         }
      });
   }
   
   //var _buildStatusView;

   radiant.console.register('dump_building', {
      call: function(cmdobj, fn, args) {
         // what a mess this is to get the selected building entity!
         // if/when we adjust the build view stuff, we can make this more accessible
         // if (!_buildStatusView)
         // {
         //    var gmm = App.getGameModeManager();
         //    var buildView = gmm.getView(gmm.modes.BUILD)._buildingDesignerView;
         //    radiant.each(buildView.get('childViews'), function(_, v) {
         //       if (v.templateName == 'buildingStatus') {
         //          _buildStatusView = v;
         //       }
         //    });
         // }

         // if (!_buildStatusView._current_building) {
         //    return false;
         // }

         // return radiant.call('stonehearth_ace:dump_building_command', _buildStatusView._current_building);

         return radiant.call('stonehearth_ace:dump_selected_building');
      },
      description : "Dumps the selected building to a qubicle file.",
      // test: function(entity) {
      //    if (entity.get('stonehearth:build2:building')) {
      //       return true;
      //    }
      //    return false;
      // },
      debugMenuNameOverride: "Dump to QB"
   });

   radiant.console.register('show_debug_ui', {
      parseString: function(string) {
         switch(string.toLowerCase()){
            case "false": case "no": case "0": case null: return false;
            case "true": case "yes": case "1": default: return true;
         }
      },

      call: function(cmdobj, fn, args) {
         var shouldShow = args._.length > 0 ? this.parseString(args._[0]) : false;
         setDebugUIVisible(shouldShow);
      },
      description: "Use to change visibility of the debugtools panel. Usage: show_debug_ui true/false"
   });
});
