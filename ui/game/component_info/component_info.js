var _componentInfoShown = false;

var _updateComponentInfoShown = function() {
   let compInfo = App.gameView.getView(App.ComponentInfoView);
   if (compInfo) {
      compInfo._onEntitySelected();
   }
};

$(top).on("show_component_info_changed", function (_, e) {
   _componentInfoShown = e.value;
   _updateComponentInfoShown();
});

$(top).on('stonehearthReady', function (cc) {
   if (!App.gameView) {
      return;
   }
   var compInfo = App.gameView.getView(App.ComponentInfoView);
   if (!compInfo) {
      App.gameView.addView(App.ComponentInfoView, {});
   }

   // need to apply the setting on load as well
   stonehearth_ace.getModConfigSetting('stonehearth_ace', 'show_component_info', function(value) {
      $(top).trigger('show_component_info_changed', { value: value });
   });
});

App.ComponentInfoView = App.View.extend({
   templateName: 'componentInfo',
   classNames: ['flex', 'exclusive'],
   closeOnEsc: true,

   components: [],

   willDestroyElement: function() {
      var self = this;
      self.$().find('.tooltipstered').tooltipster('destroy');

      self.$().off('click');
      $(top).off("radiant_selection_changed.component_info");

      self._destroyTraces();

      self._super();
   },

   dismiss: function () {
      this.hide();
   },

   hide: function (animate) {
      var self = this;

      if (!self.$()) return;

      var index = App.stonehearth.modalStack.indexOf(self)
      if (index > -1) {
         App.stonehearth.modalStack.splice(index, 1);
      }

      this._super();
   },

   show: function (animate) {
      this._super();
      App.stonehearth.modalStack.push(this);
   },

   init: function() {
      var self = this;
      self._super();

      radiant.call_obj('stonehearth.selection', 'get_selected_command')
         .done(function(data) {
            if (self.isDestroyed || self.isDestroying) {
               return;
            }
            self._onEntitySelected(data);
         });
   },

   didInsertElement: function () {
      var self = this;
      self._super();

      this.$().draggable({ handle: '.title' });

      // load up the default component data
      $.getJSON('/stonehearth_ace/data/component_info/component_info.json', function(data) {
         var sortedData = [];
         radiant.each(data, function(k, v) {
            v.name = k;
            sortedData.push(v);
         });
         sortedData.sort(function(a, b) {
            if (a.name < b.name) {
               return -1;
            }
            if (a.name > b.name) {
               return 1;
            }
            return 0;
         })
         
         self.set('generalDetails', sortedData);

         if (self.get('specificDetails')) {
            self._updateData();
         }
      });

      $(top).on("radiant_selection_changed.component_info", function (_, e) {
         self._onEntitySelected(e);
      });

      $(top).on("component_info_toggled", function (_, e) {
         if (self.visible()) {
            self.hide();
         }
         else {
            self.show();
            self._updateData();
         }
      });

      self.hide();
   },

   _destroyTraces: function() {
      if (self._tracer) {
         self._tracer.destroy();
         self._tracer = null;
      }

      if (self.selectedEntityTrace) {
         self.selectedEntityTrace.destroy();
         self.selectedEntityTrace = null;
      }

      if (self.selectedEntityInfoTrace) {
         self.selectedEntityInfoTrace.destroy();
         self.selectedEntityInfoTrace = null;
      }
   },

   _onEntitySelected: function(e) {
      var self = this;
      var entity;

      self._destroyTraces();

      if (e) {
         entity = e.selected_entity;
         self.selectedEntity = entity;
      }
      else {
         entity = self.selectedEntity;
      }

      if (!entity || !_componentInfoShown) {
         self.hide();
         // only need to trigger the event if we still have a selected entity
         if (entity) {
            $(top).trigger('selection_has_component_info_changed', {
               has_component_info: false
            });
         }
         return;
      }

      self._tracer = new RadiantTrace();
      self.selectedEntityTrace = self._tracer.traceUri(entity, {})
         .progress(function(result) {
            if (self.isDestroying || self.isDestroyed) {
               return;
            }

            self.set('selectedGeneral', result);
            if (result['stonehearth_ace:component_info'])
            {
               self.selectedEntityInfoTrace = self._tracer.traceUri(result['stonehearth_ace:component_info'], {})
                  .progress(function(compResult) {
                     if (self.isDestroying || self.isDestroyed) {
                        return;
                     }

                     self.set('selectedDetails', compResult.components || {});
                  });
            }
            else {
               self.set('selectedDetails', {});
            }
         })
         .fail(function(e) {
            console.log(e);
         });
   },

   _updateData: function() {
      var self = this;

      var general = self.get('generalDetails');

      if (general) {
         var selected = self.get('selectedGeneral') || {};
         var specific = self.get('selectedDetails');
         var data = [];

         radiant.each(general, function(_, component) {
            if (selected[component.name]) {
               // if the selected entity has this component, we're adding it to the list
               var entry = {
                  'icon': component.icon,
                  'displayName': component.display_name,
                  'generalDetails': component.description,
                  'specificDetails': [],
                  'showGeneral': true,
                  'showSpecific': false,
                  'visible': true
               };

               var specificDetails = specific[component.name];
               if (specificDetails) {
                  entry.showGeneral = !specificDetails.hide_general;
                  entry.showSpecific = !specificDetails.hide_specific;
                  entry.visible = entry.showGeneral || entry.showSpecific;
                  radiant.each(specificDetails.details, function(name, specific) {
                     var details = self._createDetailDiv(specific);
                     entry.specificDetails.push({
                        'details': details,
                        'ordinal': specific.ordinal
                     });
                  });

                  entry.specificDetails.sort(function(a, b) {
                     return a.ordinal - b.ordinal;
                  })
               }

               data.push(entry);
            }
         });

         self.set('componentsInfo', data);

         var has_data = data.length > 0;
         if (!has_data && self.visible()) {
            self.hide();
         }

         $(top).trigger('selection_has_component_info_changed', {
            has_component_info: has_data
         });
      }
   }.observes('selectedDetails'),

   _createDetailDiv: function (details) {
      var self = this;
      
      var detail = details.detail;
      switch (detail.type) {
         case 'string':
            // 'content' contains i18n string
            var content = i18n.t(detail.content, details.i18n_data);
            return content;

         case 'item_list':
            // 'items' contains the items, 'header' contains optional header, 'footer' contains optional footer
            var content = '';
            if (detail.header) {
               content += i18n.t(detail.header, details.i18n_data);
            }

            var items = {};
            // condense the items by uri and quality
            radiant.each(detail.items, function(_, item){
               var key = item.uri + '|' + (item.quality || 1);
               var arrItem = items[key];
               if (arrItem) {
                  arrItem.count++;
               }
               else {
                  arrItem = {
                     key: key,
                     item: item,
                     count: 1
                  }
                  items[key] = arrItem;
               }
            });

            items = radiant.map_to_array(items);
            items.sort(function(a, b) {
               return a.key.localeCompare(b.key);
            });

            radiant.each(items, function(_, arrItem){
               var item = arrItem.item;
               var catalogData = App.catalog.getCatalogData(item.uri);
               if (catalogData) {
                  content += `<div class="listItem"><span class="listItemText quality-${item.quality || 1}">`;
                  if (catalogData.icon) {
                     content += `<img class="inlineImg" src="${catalogData.icon}" />`
                  }
                  if (catalogData.display_name) {
                     content += i18n.t(catalogData.display_name);
                  }
                  if (arrItem.count > 1) {
                     content += `<span class="textValue"> (x${arrItem.count})</span>`;
                  }
                  content += '</span></div>'
               }
            })

            if (detail.footer) {
               content += i18n.t(detail.footer, details.i18n_data);
            }

            return content;

         case 'title_list':
            // 'titles' contains the titles, 'titles_json' contains the titles_json, 'header' contains optional header, 'footer' contains optional footer
            // actual titles content will be deferred because the json might not be loaded yet
            var content = '';
            if (detail.header) {
               content += i18n.t(detail.header, details.i18n_data);
            }

            content += '<div id="titlesContent">';

            var isWaitingForCallback = false;

            stonehearth_ace.loadAvailableTitles(detail.titles_json, function(allTitles) {
               var titlesArr = stonehearth_ace.getTitlesList(allTitles, detail.titles, '', true)
               var titlesContent = '';
   
               var descriptions = {};
               radiant.each(titlesArr, function(_, titleData) {
                  titlesContent += '<div class="specificTitle">';
                  // for each title, offer name and description
                  // then do <ul> for all the ranks (with gray/italic "next" rank at end [attained == false])
                  // with tooltips of descriptions for each of the attained ranks (and they get to wonder about the "next" one!)
                  titlesContent += `<span class="listHeader">${i18n.t(titleData.display_name)}: ${i18n.t(titleData.description)}</span>`;

                  var list = '<ul class="titleList">';
                  radiant.each(titleData.ranks, function(_, rankData) {
                     descriptions[rankData.key] = rankData.description;
                     list += `<li class="titleRank ${rankData.attained ? 'attained' : 'unattained'}" description-key="${rankData.key}" renown="${rankData.renown}">${i18n.t(rankData.display_name)}</li>`;
                  });
                  list += '</ul></div>';
                  titlesContent += list;

                  titlesContent += '</div>';
               });

               if (isWaitingForCallback) {
                  self.$('#titlesContent').html(titlesContent);
               }
               else {
                  content += titlesContent;
               }

               Ember.run.scheduleOnce('afterRender', self, function() {
                  var titleRank = self.$('.titleRank');
                  if (titleRank) {
                     // don't give description tooltips for the unattained "next" ones
                     self.$('.titleRank.attained').each(function() {
                        var description = i18n.t(descriptions[$(this).attr('description-key')]) + '<br>' +
                              i18n.t('stonehearth_ace:component_info.stonehearth_ace.titles.renown', {renown: $(this).attr('renown')});
                        App.guiHelper.addTooltip($(this), description);
                     });

                     self.$('.titleRank.unattained').each(function() {
                        App.guiHelper.addTooltip($(this), i18n.t('stonehearth_ace:component_info.stonehearth_ace.titles.unattained'));
                     });
                  }
               });
            });

            content += '</div>';

            if (detail.footer) {
               content += i18n.t(detail.footer, details.i18n_data);
            }

            isWaitingForCallback = true;

            return content;
      }
   }
});
