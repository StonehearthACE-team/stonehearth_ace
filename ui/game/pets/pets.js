let pets_list = [];
   
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
            self._trace_pets = new StonehearthDataTrace(town, components)
               .progress(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  var town_pets = response.town_pets || {};
                  var list_keys = Object.keys(town_pets);
                  var pet_object = {}
                  

                  for (var i = 0; i < list_keys.length; i++){
                     //Get pet object and simple attributes
                     pet_object = town_pets[list_keys[i]];
                     pets_list[i] = pet_object;
                     health_percentage = (pets_list[i]['stonehearth:expendable_resources'].resource_percentages.health)*100;
                     pets_list[i].health = String(health_percentage)
                    
                     //Get pet Buffs
                     var buff_keys = Object.keys(pets_list[i]['stonehearth:buffs'].buffs);
                     for (var j = 0; j < buff_keys.length; j++){
                        var buff_list = [];
                        buff_list[j] = pets_list[i]['stonehearth:buffs'].buffs[buff_keys[j]];
                        
                     }
                     pets_list[i].buffs = buff_list;

                     //Get pet commands
                     pets_list[i].available_commands = Object.entries(pets_list[i]['stonehearth:commands'].commands);
                                          
                  }
                  
                  //Set pet list and selected pet + portrait for the first time
                  self.set('pets_list', pets_list);
                  if (!self.get('selected')) {
                     self.set('selected', pets_list[0]);
                     var uri = pets_list[0].__self;
                     var portrait_url = '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + uri + '&cache_buster=' + Math.random();
                     self.$('#selectedPortrait').css('background-image', 'url(' + portrait_url + ')');  
                  }            
                  return;
                  
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

      self.$().on('click', '.moodIcon', function() {
         self._moodIconClicked = true;
      });

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

      //console.log("pets_list: ", pets_list);

      self.$('#petTable').on('click', 'tr', function () {
         $('#petTable tr').removeClass('selected');
          $(this).addClass('selected');
          self.set('selected', pets_list[$(this).index()]);
          var uri = pets_list[$(this).index()].__self;
          var portrait_url = '/r/get_portrait/?type=headshot&animation=idle_breathe.json&entity=' + uri + '&cache_buster=' + Math.random();
          self.$('#selectedPortrait').css('background-image', 'url(' + portrait_url + ')');
      });

      self.$('#release_pet').on('click', function (_, e) {
         App.gameView.addView(App.StonehearthConfirmView, {
            title : i18n.t('stonehearth:ui.game.pet_character_sheet.release_pet_confirm_dialog.title'),
            message : i18n.t('stonehearth:ui.game.pet_character_sheet.release_pet_confirm_dialog.message'),
            buttons : [
               {
                  id: 'accept',
                  label: i18n.t('stonehearth:ui.game.pet_character_sheet.release_pet_confirm_dialog.accept'),
                  click: function() {
                     radiant.call('stonehearth:release_pet', e.entity);
                  }
               },
               {
                  id: 'cancel',
                  label: i18n.t('stonehearth:ui.game.pet_character_sheet.release_pet_confirm_dialog.cancel')
               }
            ]
         });
      });
   },
});
