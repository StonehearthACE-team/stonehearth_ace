App.StonehearthDeliveryQuestBulletinDialog.reopen({
   _updateFromI18nData: function() {
      var self = this;
      var i18n_data = self.get('model.i18n_data');
      var requirements = self.get('requirements');
      var rawReqData = self.get('model.data.requirements');
      if (!requirements || !rawReqData) return;

      // we have to match up any requirements listed in i18n_data with the overall requirements
      var id = 1;
      var i18n_reqs = [];
      while (true) {
         var data = i18n_data && i18n_data['req_' + id];
         if (!data) break;
         i18n_reqs.push(data);
         id++;
      }

      for (var i = 0; i < requirements.length; i++) {
         var requirement = rawReqData[i];
         var foundReq = false;
         for (var j = 0; j < i18n_reqs.length; j++) {
            var i18nData = i18n_reqs[j];
            var i18nReq = i18nData.requirement;
            if ((requirement.type == 'give_item' && !requirement.keep_items && i18nReq.uri == requirement.uri) ||
                  (requirement.type == 'give_material' && !requirement.keep_items && i18nReq.material == requirement.material)) {
               Ember.set(requirements[i], 'real_available_count', requirements[i].available_count + (i18nData.quantity || 0));
               Ember.set(requirements[i], 'items_cached_class', i18nData.items_cached_class || 'noCache');
               Ember.set(requirements[i], 'cached_count', i18nData.quantity && ` <span class='numCached'>(${i18nData.quantity})</span>` || '');
               Ember.set(requirements[i], 'fulfilled', requirements[i].real_available_count >= requirement.count);
               foundReq = true;
               break;
            }
         }
         
         if (!foundReq) {
            Ember.set(requirements[i], 'real_available_count', requirements[i].available_count);
            Ember.set(requirements[i], 'items_cached_class', '');
            Ember.set(requirements[i], 'cached_count', '');
            Ember.set(requirements[i], 'fulfilled', requirements[i].real_available_count >= requirements[i].count);
         }
      }
   }.observes('model.i18n_data', 'requirements'),
});
