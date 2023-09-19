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

      self.set('display_name', 'Kitty');
      self.set('description', 'Befriended by Lara');
      var traits = ['Nice', 'Strong', 'Carnivore'];
      var available_commands = ['Pet', 'Feed', 'Play'];
      var release = {display_name: 'Release Pet'};
      self.set('traits', traits);
      self.set('available_commands', available_commands);
      self.set('release_pet', release);
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
   },
});
