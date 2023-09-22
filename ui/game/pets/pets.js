var mocked_pets = [
   kitty = {
      display_name: 'Kitty',
      description: 'Befriended by Lara',
      traits: ['Nice', 'Strong', 'Carnivore'],
      available_commands: ['Pet', 'Feed', 'Play'],
      release_pet: {display_name: 'Release Pet'},
      health: '100',
      maxHealth: '100',
      moodValue: '5',
      selected: true
   },
   batman = {
      display_name: 'Batman',
      description: 'Befriended by Ivens',
      traits: ['Disguised', 'Strong', 'Powerful'],
      available_commands: ['Pet', 'Hunt', 'Play'],
      release_pet: {display_name: 'Release Pet'},
      health: '100',
      maxHealth: '100',
      moodValue: '5'
   },
   mingau = {
      display_name: 'Mingau',
      description: 'Befriended by Lara',
      traits: ['Fat', 'Talkative', 'Bald'],
      available_commands: ['Pet', 'Feed'],
      release_pet: {display_name: 'Release Pet'},
      health: '100',
      maxHealth: '100',
      moodValue: '5'
   }
]
var pets_list = [];
   
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
      

      
      //mocking this before actually getting the data from the game
      self.set('pets', mocked_pets);
      
      this._traceTownPets();
      
      
   },
   
   _traceTownPets: function() {
      var playerId = App.stonehearthClient.getPlayerId()
      var self = this;
      //console.log("Player ID: " + playerId);
      radiant.call_obj('stonehearth.town', 'get_town_entity_command', playerId)
         .done(function (response) {
            var components = {
               town_pets: {
                 '*': {
                   'stonehearth:commands': {},
                   'stonehearth:pet': {},
                   'stonehearth:unit_info': {},
                 },
               },
            };
            var town = response.town;
            //console.log("town: " + JSON.stringify(response));
            self._trace_pets = new StonehearthDataTrace(town, components)
               .progress(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  var town_pets = response.town_pets;
                  //console.log(town_pets)
                  var list_keys = Object.keys(town_pets);
                  var pets_list = []
                  var pet_object = {}
                  
                  for (var i = 0; i < list_keys.length; i++){
                     pet_object = town_pets[list_keys[i]];
                     pets_list[i] = pet_object;
                     //console.log("DISPLAY name: ", pets_list[i]['stonehearth:unit_info'].custom_name);
                     //console.log("UI GAME CUSTOM name: ", pets_list[i]['stonehearth:ui.game.entities.custom_name']);
                     
                  }
                  
                  
                  self.set('pets_list', pets_list);
                  self.set('selected', pets_list[0]);
                  return pets_list;
                  
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

      console.log("antes", pets_list)
      pets_list = this._traceTownPets();
      console.log("depois", pets_list)
      console.log("pets list", pets_list)
      self.$('#petTable').on('click', 'tr', function () {
         $('#petTable tr').removeClass('selected');
          $(this).addClass('selected');
          self.set('selected', pets_list[$(this).index()]);
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
