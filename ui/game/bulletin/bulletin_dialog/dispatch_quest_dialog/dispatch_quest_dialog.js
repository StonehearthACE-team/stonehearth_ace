App.StonehearthDispatchQuestBulletinDialog = App.StonehearthBaseBulletinDialog.extend({
   templateName: 'dispatchQuestBulletinDialog',

   init: function() {
      this._super();
      var self = this;

      self._popTrace = App.population.getTrace();
      self._popTrace.progress(function (pop) {
         self.set('citizensArray', radiant.map_to_array(pop.citizens, function (k, v) {
            if (k === 'size') {
               return false;  // ignore size field from population data
            }
            if (v.__self) {
               return v.__self;  // get game object id
            }
         }));
      });

      self.set('selected', Ember.A());
   },

   selectedCount: function () {
      var self = this;
      return self.get('selected') ? self.get('selected').length : 0;
   }.property('selected'),

   requiredCount: function () {
      var self = this;
      var requirements = self.get('model.data.requirements');
      return requirements ? requirements.length : 0;
   }.property('model'),

   readyToDispatch: function () {
      var self = this;
      return self.get('selectedCount') == self.get('requiredCount');
   }.property('selectedCount', 'requiredCount'),
   
   unsatisfiedRequirements: function () {
      var self = this;
      if (!self.get('model') || !self.get('model.data.requirements') || !self.get('selected')) {
         return [];
      }

      // This is technically incorrect, since requirements may overlap, but it's probably good enough in practice.
      var remainingRequirements = Array.prototype.slice.call(self.get('model.data.requirements'));
      var remainingCitizens = Array.prototype.slice.call(self.get('selected'));
      radiant.each(remainingCitizens, function (_, citizen) {
         for (var i = 0; i < remainingRequirements.length; ++i) {
            if (self._matchesRequirement(citizen, remainingRequirements[i])) {
               remainingRequirements.removeAt(i);
               return;
            }
         }
      });

      return remainingRequirements;
   }.property('selected', 'model'),

   didInsertElement: function() {
      this._super();
      var self = this;
      self._wireButtonToCallback('#abandonButton', 'on_abandon', true);
      self.dialog.on('click', '#dispatchButton', function () {
         if ($(this).hasClass('disabled')) return;
         self.dispatchPeople();
      });
   },

   destroy: function () {
      if (this._popTrace) {
         this._popTrace.destroy();
         this._popTrace = null;
      }
      this._super();
   },

   selectPerson: function (person) {
      var self = this;
      self.get('selected').push(person);
      self.notifyPropertyChange('selected');
      this.rerender();
   },

   deselectPerson: function (person) {
      if (!person) return;
      var self = this;
      var selected = self.get('selected');
      for (var i = 0; i < selected.length; ++i) {
         if (selected[i] && selected[i].__self == person.__self) {
            selected.removeAt(i);
            break;
         }
      }
      self.notifyPropertyChange('selected');
      this.rerender();
   },

   dispatchPeople: function () {
      var self = this;
      var bulletin = self.get('model');
      if (!bulletin) {
         return;
      }
      var instance = bulletin.callback_instance;
      var method = bulletin.data['on_try_dispatch'];
      if (!method) {
         return;
      }

      radiant.call_obj(instance, method, _.map(self.get('selected'), function (p) { return p.__self; }));
      self._autoDestroy();
   },
   
   shouldShowPerson: function (person) {
      var self = this;

      if (self.isSelected(person.__self)) return true;

      var remainingRequirements = self.get('unsatisfiedRequirements');
      for (var i = 0; i < remainingRequirements.length; ++i) {
         if (self._matchesRequirement(person, remainingRequirements[i])) {
            return true;
         }
      }
      return false;
   },

   isSelected: function (person_id) {
      var self = this;
      var selected = self.get('selected');
      for (var i = 0; i < selected.length; ++i) {
         if (selected[i] && selected[i].__self == person_id) {
            return true;
         }
      }
      return false;
   },

   _matchesRequirement: function (person, requirement) {
      var required_job = requirement.job;
      var required_role = requirement.role;

      if (required_job) {
         if (required_job == person['stonehearth:job'].job_uri) {
            var required_job_level = requirement.job_level;
            if (required_job_level) {
               return person['stonehearth:job'].curr_job_level >= required_job_level;
            } else {
               return true;  // right job and no level requirement
            }
         } else {
            return false;  // not the right job
         }
      }

      if (required_role) {
         let roles = person['stonehearth:job'].curr_job_roles || {};
         if (roles[required_role]) {
            var required_job_level = requirement.job_level;
            if (required_job_level) {
               return person['stonehearth:job'].curr_job_level >= required_job_level;
            } else {
               return true;  // right role and no level requirement
            }
         } else {
            return false;  // not the right role
         }
      }

      return true;
   }
});

App.StonehearthDispatchQuestBulletinRowView = App.View.extend({
   tagName: 'tr',
   classNames: ['row'],
   templateName: 'stonehearthDispatchQuestBulletinRow',
   uriProperty: 'model',

   components: {
      'stonehearth:unit_info': {},
      'stonehearth:job': {},
      'stonehearth:ai': {}
   },

   actions: {
      selectPerson: function (citizen) {
         if (this.get('selected')) {
            this.dialogView.deselectPerson(citizen);
         } else {
            this.dialogView.selectPerson(citizen);
         }
      }
   },

   shouldShow: function () {
      if (this.get('model')) {
         if (this.get('model.stonehearth:ai').status_text_key == 'stonehearth:ai.actions.status_text.away_from_town') {  // Hacky, but the easiest way.
            return false;  // Already dispatched.
         }
         return this.dialogView.shouldShowPerson(this.get('model'));
      } else {
         return this.get('selected');
      }
   }.property('model'),

   selected: function () {
      return this.dialogView.isSelected(this.get('uri'));
   }.property('uri'),
});
