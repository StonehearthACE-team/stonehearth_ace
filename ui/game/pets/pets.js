let pets_list = [];
let mainView = null;

App.StonehearthAcePetsView = App.View.extend({
   templateName: 'petsView',
   uriProperty: 'model',
   classNames: ['flex', 'exclusive'],
   closeOnEsc: true,
   skipInvisibleUpdates: true,
   hideOnCreate: false,
   components: {
      'stonehearth:unit_info': {},
      'stonehearth:attributes' : {},
      'stonehearth:expendable_resources' : {},
      'stonehearth:pet' : {}
   },

   init: function() {
      var self = this;
      this._super();
      mainView = this;
      //Trace town pets on init
      this._traceTownPets();
      
   },
   
   _traceTownPets: function() {
      var playerId = App.stonehearthClient.getPlayerId()
      var self = this;
      radiant.call_obj('stonehearth.town', 'get_town_entity_command', playerId)
         .done(function (response) {
            var components = {
               town_pets: {
                 '*': {
                     'stonehearth:commands': {
                        'commands': {},
                     },
                     'stonehearth:pet': {},
                     'stonehearth:unit_info': {},
                     "stonehearth:ai": {
                        "status_text_data": {},
                     },
                     'stonehearth:buffs' : {
                        'buffs' : {
                           '*' : {}
                        }
                     },
                     'stonehearth:expendable_resources': {},
                  },
               },
            };
            var town = response.town;
            self._petTraces = new StonehearthDataTrace(town, components)
               .progress(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  var town_pets = response.town_pets || {};
                  if (town_pets == {}) return //if no pets, return
                  else if (self.get('pets_list')) { //check if pets list has changed
                     var townNew = JSON.stringify(town_pets)
                     var townOld = JSON.stringify(self.get('town_pets'))
                     if (townOld==townNew) {
                        return
                     }
                  }
                  else {
                     self.set('pets_list', [])
                     var list_keys = Object.keys(town_pets);
                     var pet_object = {}
                     for (var i = 0; i < list_keys.length; i++){
                        //Get pet object and add to list
                        pet_object = town_pets[list_keys[i]];
                        pets_list[i] = pet_object;
                        //Get health, hunger, social and sleepiness percentages
                        var health_percentage = Math.round(((pets_list[i]['stonehearth:expendable_resources'].resource_percentages.health)*100)*10)/10;
                        var hunger_percentage = Math.round(100-(Math.round(((pets_list[i]['stonehearth:expendable_resources'].resource_percentages.calories)*100)*10)/10)/10);
                        var social_percentage = Math.round(((pets_list[i]['stonehearth:expendable_resources'].resource_percentages.social_satisfaction)*100)*10)/10;
                        var sleepiness_percentage = Math.round(((pets_list[i]['stonehearth:expendable_resources'].resource_percentages.sleepiness)*100)*10)/10;
                        pets_list[i].health = String(health_percentage)
                        pets_list[i].hunger = String(hunger_percentage)
                        pets_list[i].social = String(social_percentage)
                        pets_list[i].sleepiness = String(sleepiness_percentage)
                        //Get pet status
                        pets_list[i].activity = pets_list[i]['stonehearth:ai'].status_text_key
                        //Get pet Buffs
                        var buff_keys = Object.keys(pets_list[i]['stonehearth:buffs'].buffs);
                        var buff_list = [];
                        for (var j = 0; j < buff_keys.length; j++){
                           
                           buff_list[j] = pets_list[i]['stonehearth:buffs'].buffs[buff_keys[j]];
                           
                        }
                        pets_list[i].buffs = buff_list;

                        //Get pet commands
                        var command_keys = Object.keys(pets_list[i]['stonehearth:commands'].commands);
                        var command_list = [];
                        for (var j = 0; j < command_keys.length; j++){
                           
                           command_list[j] = pets_list[i]['stonehearth:commands'].commands[command_keys[j]];
                           
                        }
                        //console.log(command_list[0].display_name)
                        pets_list[i].available_commands = command_list;
                                             
                     }
                     
                     //Set pet list and selected pet + portrait for the first time
                     self.set('pets_list', pets_list);
                     self.set('town_pets', town_pets)
                     if (!self.get('selected') && pets_list[0]) {
                        self.set('selected', pets_list[0]);
                        self.set('selected_index', pets_list[0]);
                        var uri = pets_list[0].__self;
                        var portrait_url = '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + uri + '&cache_buster=' + Math.random();
                        self.$('#selectedPortrait').css('background-image', 'url(' + portrait_url + ')');  
                     }       
                     
                     
                     //debugger
                     return;
                  }
                  
               })
               .fail(function(e) {
                  console.log(e);
               });

      });
   },
   
   didInsertElement: function() {
      var self = this;
      self._super();
      

      this.$().draggable({ handle: '.title' });

      //not functional yet
      self.$().on('click', '.listTitle', function() {
         var newSortKey = $(this).attr('data-sort-key');
         if (newSortKey) {
            if (newSortKey == self.get('sortKey')) {
               self.set('sortDirection', -(self.get('sortDirection') || 1));
            } else {
               self.set('sortKey', newSortKey);
               self.set('sortDirection', 1);
            }

            petsLastSortKey = newSortKey;
            petsLastSortDirection = self.get('sortDirection');
         }
      });

      if (self.hideOnCreate) {
         self.hide();
      }
      //Change pet selection on click
      self.$('#petTable').on('click', 'tr', function () {
         console.log(pets_list)
         if(pets_list.length > 0){ //check if any pets are available to select
            if(!$(this).hasClass('selected')) {
               $('#petTable tr').removeClass('selected');
               $(this).addClass('selected');
               self.set('selected', pets_list[$(this).index()]);
               self.set('selected_index', $(this).index());
            }
            //Re-select portrait
            var uri = pets_list[$(this).index()].__self;
            var portrait_url = '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + uri + '&cache_buster=' + Math.random();
            self.$('#selectedPortrait').css('background-image', 'url(' + portrait_url + ')');
            //Focus on entity and open pet sheet
            radiant.call('stonehearth:camera_look_at_entity', uri);
            radiant.call('stonehearth:select_entity', uri);
            radiant.call('radiant:play_sound', {'track' : 'stonehearth:sounds:ui:start_menu:focus' });
            //recheck the pets list
            mainView._traceTownPets();
         }
      });
   },
   actions: {
      doCommand: function(command) {
         var self = this;
         var pet_data = self.get('selected');
         var pet_id = pet_data.__self;
         var player_id = pet_data.player_id;
         App.stonehearthClient.doCommand(pet_id, player_id, command);
         //Check if pet was removed
         if (command.name == 'release_pet') {
            //remove pet from list and recheck the pets list
            $('#petTable').find('tr').eq(self.get('selected_index')).remove();
            pets_list.splice(self.get('selected_index'), 1);
            self.set('pets_list', pets_list);
            self.set('selected', pets_list[0]);
            $('#petTable').find('tr').eq(0).addClass('selected');
            var uri = pets_list[0].__self;
            var portrait_url = '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + uri + '&cache_buster=' + Math.random();
            self.$('#selectedPortrait').css('background-image', 'url(' + portrait_url + ')');  
            mainView._traceTownPets();
            
         }
      },
   },
});
