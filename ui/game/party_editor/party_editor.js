$(document).ready(function(){
   $(top).on('radiant_show_party_editor', function(_, e){
      App.stonehearthClient.showPartyEditor(e.entity)
   });
});

//
// App.StonehearthPartyEditorBase is defined in parties.js.  It handles
// the behavior of the attack and defend buttons
//
App.StonehearthPartyEditorView = App.View.extend({
	templateName: 'partyEditor',
   uriProperty: 'model',
   components: {
      "stonehearth:unit_info" : {},
      "stonehearth:party" : {},
   },
   closeOnEsc: true,

   didInsertElement: function() {
      var self = this;

      this.$('.bannerButton').each(function() {
         $(this).tooltipster({
            content: $('<div class=title>' + $(this).attr('title') + '</div>' +
                       '<div class=description>' + $(this).attr('description') + '</div>')
         });
      });

   },

   willDestroyElement: function() {
      this._super();
      if (this._addMemberView && !this._addMemberView.isDestroyed && !this._addMemberView.isDestroying) {
         this._addMemberView.destroy();
         this._addMemberView = null;
      }
   },

   setCitizenRowContainerView: function(containerView) {
      this._containerView = containerView;
   },

   party_name: function() {
      var partyNameKey = this.get('model.stonehearth:unit_info.display_name');
      var partyName = i18n.t(partyNameKey, {self: this.get('model')});
      return partyName;
   }.property('model.stonehearth:unit_info'),

   actions: {
      remove_members: function() {
         var party = this.get('model.stonehearth:party');
         if (party) {
            radiant.call_obj('stonehearth.unit_control', 'remove_all_members_command', party.id);
         }
         //We only have 4 player-facing parties, so we no longer destroy them.
         //Instead, just remove all the people. If we ever want to go back to
         //an infinite #of parties, turn this back into disband, and destroy the party.
      },
      editRoster: function() {
         if (!this._addMemberView || this._addMemberView.isDestroyed || this._addMemberView.isDestroying) {
            var party_entity = this.get('model');
            var party_component = this.get('model.stonehearth:party');
            this._addMemberView = App.gameView.addView(App.StonehearthPartyEditorEditRosterView, {
                  'party_entity' : party_entity.__self,
                  'party_component' : party_component.__self,
               });
         } else {
            this._addMemberView.destroy();
            this._addMemberView = null;
         }
      },
   },

   updatePartyMembers: function() {
      if (this._containerView) {
         var partyMembers = this.get('model.stonehearth:party.members');
         this._containerView.updateRows(partyMembers);
      }
      if (this._addMemberView) {
         this._addMemberView.updateCitizens();
      }
   }.observes('model.stonehearth:party.members'),

   _hideMemberView: function() {
      if (this._addMemberView && !this._addMemberView.isDestroyed && !this._addMemberView.isDestroying) {
         this._addMemberView.destroy();
         this._addMemberView = null;
      }
   }.observes('uri'),

   _setSelected: function() {
      var party = this.get('model.stonehearth:party');
      if (party) {
         radiant.call_obj('stonehearth.party_editor', 'select_party_command', party.id);
      }
   }.observes('model.stonehearth:party'),
});

App.StonehearthPartyMemberRowView = App.View.extend({
   tagName: 'tr',
   classNames: ['row'],
   templateName: 'partyMemberRow',
   uriProperty: 'model',

   components: {
      "stonehearth:unit_info": {},
      "stonehearth:job" : {
         "job_uri" : {}
      },
      "stonehearth:party_member" : {
         "party" : {
            "stonehearth:party" : {}
         },
      },
   },
   didInsertElement: function() {
      var self = this;
      this._super();
      self.$(".selectable_party_row").click(function() {

         radiant.call('stonehearth:camera_look_at_entity', self.uri);
         radiant.call('stonehearth:select_entity', self.uri);
      });
   },
   actions: {
      removePartyMember: function (citizen) {
         if (!citizen) return;
         var party = this.get('model.stonehearth:party_member.party.stonehearth:party');
         radiant.call_obj(party, 'remove_member_command', citizen.__self)
                  .fail(function(response) {
                     console.log('failed to remove party member', response);
                  });

      },
   },
});

App.StonehearthPartyEditorEditRosterView = App.View.extend({
   templateName: 'partyEditorEditRoster',
   uriProperty: 'model',
   closeOnEsc: true,

   init: function() {
      var self = this;
      this._super();
      radiant.call_obj('stonehearth.population', 'get_population_command')
               .done(function (response) {
                  if (self.isDestroying || self.isDestroyed) {
                     return;
                  }
                  self.set('uri', response.uri)
               });
   },

   actions: {
      close: function() {
         this.destroy();
      },
   },

   didInsertElement: function() {
      var self = this;
      this._super();

      this.$().draggable();

      // remember the citizen for the row that the mouse is over
      this.$().on('mouseenter', '.row', function() {
      });
   },

   setCitizenRowContainerView: function(containerView) {
      this._containerView = containerView;
   },

   updateCitizens: function() {
      var self = this;

      radiant.call_obj('stonehearth.population', 'get_addable_citizens_for_party', self.party_entity)
         .done(function(response) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }

            if (self._containerView) {
               self._containerView.updateRows(response.citizens);
            }
         });
   }.observes('model.citizens'),
});

App.StonehearthPartyEditorEditRosterRowView = App.View.extend({
   tagName: 'tr',
   classNames: ['row'],
   templateName: 'partyEditorEditRosterRow',
   uriProperty: 'model',

   components: {
      "stonehearth:unit_info": {},
      "stonehearth:job" : {
         'curr_job_controller' : {},
         "job_uri" : {}
      },
      "stonehearth:party_member" : {
         "party" : {
            "stonehearth:unit_info" : {},
            "stonehearth:party" : {}
         }
      },
   },

   didInsertElement: function() {
      var self = this;
      self.$(".selectable_party_row").click(function() {

         radiant.call('stonehearth:camera_look_at_entity', self.uri)
         radiant.call('stonehearth:select_entity', self.uri);
      });
   },

   actions: {
      addPartyMember: function(citizen) {
         var self = this;
         var party = this.get('party_component');
         radiant.call_obj(party, 'add_member_command', citizen.__self)
                  .fail(function(response) {
                     console.log('failed to add party member', response);
                  });

      }
   },
});

App.StonehearthPartyRowsContainerView = App.StonehearthCitizenRowContainerView.extend({
   tagName: 'tbody',
   templateName: 'partyRowsContainer',
   containerParentView: null,
   currentCitizensMap: {},
   rowCtor: App.StonehearthPartyMemberRowView,

   constructRowViewArgs: function(citizenId, entry) {
      return {
         party: this.containerParentView.model.__self,
         uri: entry.entity,
         citizenId: citizenId,
      }
   },
});

App.StonehearthPartyEditorRowsContainerView = App.StonehearthCitizenRowContainerView.extend({
   tagName: 'tbody',
   templateName: 'partyEditorRowsContainer',
   currentCitizensMap: {},
   rowCtor: App.StonehearthPartyEditorEditRosterRowView,

   constructRowViewArgs: function(citizenId, entry) {
      return {
         party_entity: this.containerParentView.get('party_entity'),
         party_component: this.containerParentView.get('party_component'),
         uri: entry,
         citizenId: citizenId,
      };
   },
});
