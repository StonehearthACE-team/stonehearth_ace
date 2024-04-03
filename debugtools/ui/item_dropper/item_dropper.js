$(document).on('stonehearthReady', function(){
   App.debugDock.addToDock(App.StonehearthItemDropperIcon);
   radiant.call('debugtools:get_all_item_uris_command')
      .done(function(response) {
         allUris = response;
         allUris.sort();
      })
      .fail(function() {
      });
});

var itemDropperInitialValue = "";
var allUris = {};

App.StonehearthItemDropperIcon = App.View.extend({
   templateName: 'itemDropperIcon',
   classNames: ['debugDockIcon'],

   didInsertElement: function() {
      var self = this;
      $('#itemDropperIcon').tooltipster();
      self.$().click(function () {
         // Add item dropper view when icon clicked
         var view = App.debugView.getView(App.StonehearthItemDropperView);
         if (view) {
            view.$().toggle();
            view.$('#uriInput').focus();
         } else {
            view = App.debugView.addView(App.StonehearthItemDropperView);
         }

         // Set input field text if we are currently selecting an entity
         var selected = App.stonehearthClient.getSelectedEntity();
         if (selected) {
            var components = { 'stonehearth:iconic_form': { 'root_entity': {} }};
            self.selectedEntityTrace = new StonehearthDataTrace(selected, components)
               .progress(function(result) {
                  var root_uri = result.get('stonehearth:iconic_form.root_entity.uri');
                  var uri = root_uri != null ? root_uri : result.uri;
                  if (uri.indexOf(':') > 0) {
                     view.setInputValue(uri);
                  } else {

                  }
               })
               .fail(function(e) {
                  console.log(e);
               });
         }
      });
   }
});

App.StonehearthItemDropperView = App.View.extend({
   templateName: 'itemDropper',

   init: function() {
      var self = this;
      this._super();
   },

   didInsertElement: function() {
      var self = this;

      this._super();

      this.$().draggable({ handle: '.header' });

      jQuery.widget( "ui.autocomplete", jQuery.ui.autocomplete, {
          _close: function( event ) {
              if(event!== undefined && event.keepOpen===true) {
                  //trigger new search with current value
                  return true;
              }
              //otherwise invoke the original
              return this._super( event );
          }
      });


      this.$('#uriInput')
         .attr("value", itemDropperInitialValue)
         .autocomplete({
            source: allUris,
            delay: 0,
            select: function (event, ui) {
               jQuery.extend(event.originalEvent,{keepOpen:true});
               self.$('#uriInput').val(ui.item.value).change();
               self.$('#makeButton').click();
               return false;
            }})
         .focus();
      this.$('#uriInput').autocomplete("widget").addClass('itemDropperAutocomplete');

      // Starting a selector while another one is on cancels the previous one, but the
      // notifications may be out of order, so keep track of how many are active at a time.
      self.numDroppersActive = 0;
      var doPlaceEntity = function (uri, iconic, timesNine, quality) {
         self.numDroppersActive++;
         self.$('#itemDropper').addClass('active');
         radiant.call('debugtools:create_and_place_entity', uri, iconic, timesNine, quality)
            .always(function () {
               self.numDroppersActive--;
               if (self.numDroppersActive <= 0) {
                  self.$('#itemDropper').removeClass('active');
               }
            })
            .done(function () {
               doPlaceEntity(uri, iconic, timesNine, quality);
            });
      };

      this.$('#uriInput').focus(function(e) {       
         $(this).select();
      });

      this.$('#uriInput').keypress(function (e) {
         if (e.which == 13) { // return
            self.$('#makeButton').click();
         }
      });

      this.$('#uriInput').on('change keyup paste input', function (e) {
         var uri = self.$('#uriInput').val().toLowerCase().trim();
         self.$('#uriInput').toggleClass('invalid', !!(uri && allUris.indexOf(uri) == -1));
      });

      this.$('#makeButton').click(function() {
         var uri = self.$('#uriInput').val().toLowerCase().trim();
         if (uri && allUris.indexOf(uri) != -1) {
            itemDropperInitialValue = uri;
            var iconic = self.$('#iconicCheckbox').is(':checked');
            var timesNine = self.$('#timesNineCheckbox').is(':checked');
            var quality = self.get('quality');
            self.$('#uriInput').blur();
            doPlaceEntity(uri, iconic, timesNine, quality);
         } else {
            self.$('#uriInput').focus().addClass('notifyInvalid');
            setTimeout(function () { self.$('#uriInput').removeClass('notifyInvalid'); }, 500);
         }
      });

      this.$('#iconicCheckbox').change(function () {
         if (self.numDroppersActive > 0) {
            self.$('#makeButton').click();
         }
      })

      this.$('#timesNineCheckbox').change(function () {
         if (self.numDroppersActive > 0) {
            self.$('#makeButton').click();
         }
      })

      this.$('.close').click(function() {
         self.$().toggle();
      });

      this.$('#itemDropper').position({
         my: 'left top',
         at: 'left-300 bottom-60',
         of: $('#itemDropperIcon').closest('.debugDock')
      });

      // ACE: Add quality selector
      var qualityEntries = [];
      qualityEntries.push({
         display_name: 'i18n(stonehearth_ace:ui.debugtools.quality.quality-1)',
         icon: '/stonehearth_ace/ui/common/images/quality_none.png',
         key: 1,
      });
      qualityEntries.push({
         display_name: 'i18n(stonehearth_ace:ui.debugtools.quality.quality-2)',
         icon: '/stonehearth/ui/common/images/quality_fine.png',
         key: 2,
      });
      qualityEntries.push({
         display_name: 'i18n(stonehearth_ace:ui.debugtools.quality.quality-3)',
         icon: '/stonehearth/ui/common/images/quality_excellent.png',
         key: 3,
      });
      qualityEntries.push({
         display_name: 'i18n(stonehearth_ace:ui.debugtools.quality.quality-4)',
         icon: '/stonehearth/ui/common/images/quality_masterwork.png',
         key: 4,
      });

      var onChanged = function (id, value) {
         self.set('quality', value.key);
      };

      var qualitySelector = App.guiHelper.createCustomSelector('debug_tools_item_dropper_quality_selector', qualityEntries, onChanged).container;
      App.guiHelper.setListSelectorValue(qualitySelector, qualityEntries[0]);

      self._qualitySelector = qualitySelector;
      self.$('#qualitySelectionList').append(qualitySelector);
   },

   setInputValue: function(value) {
      var uriInput = this.$('#uriInput');
      if (uriInput) {
         uriInput.focus();
         uriInput.attr("value", value);
      }
   }

});
