var pets = [
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
      available_commands: ['Pet', 'Feed', 'Play'],
      release_pet: {display_name: 'Release Pet'},
      health: '100',
      maxHealth: '100',
      moodValue: '5'
   },
   mingau = {
      display_name: 'Mingau',
      description: 'Befriended by Lara',
      traits: ['Fat', 'Talkative', 'Bald'],
      available_commands: ['Pet', 'Feed', 'Play'],
      release_pet: {display_name: 'Release Pet'},
      health: '100',
      maxHealth: '100',
      moodValue: '5'
   }
]
App.StonehearthAcePetsView = App.View.extend({
   templateName: 'petsView',
   uriProperty: 'model',
   classNames: ['flex', 'exclusive'],
   closeOnEsc: true,
   skipInvisibleUpdates: true,
   hideOnCreate: false,
   components: {
   },

   init: function() {
      var self = this;
      this._super();

      //mocking this before actually getting the data from the game
      self.set('pets', pets);
      self.set('selected', pets[0]);
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

            citizensLastSortKey = newSortKey;
            citizensLastSortDirection = self.get('sortDirection');
         }
      });

      if (self.hideOnCreate) {
         self.hide();
      }

      self.$('#petTable').on('click', 'tr', function () {
         $('#petTable tr').removeClass('selected');
          $(this).addClass('selected');
          self.set('selected', pets[$(this).index()]);
      });
   },
});
