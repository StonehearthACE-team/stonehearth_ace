$(document).ready(function(){
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
      stringToString: function(string) {
         switch(string.toLowerCase()){
            case "true": case "yes": case "1": return "block";
            case "false": case "no": case "0": case null: return "none";
            default: return "block";
         }
      },

      call: function(cmdobj, fn, args) {
         var shouldShow = args._.length > 0 ? this.stringToString(args._[0]) : "block";
         $(".debugDock").css("display", shouldShow);
      },
      description: "Use to change visibility of the debugtools panel. Usage: show_debug_ui true/false"
   });
});
