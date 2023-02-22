App.StonehearthCollectionQuestBulletinDialog = App.StonehearthBaseBulletinDialog.extend({
	templateName: 'collectionQuestBulletinDialog',

   didInsertElement: function() {
      this._super();
      this._wireButtonToCallback('#collectionPayButton',    'collection_pay_callback');
      this._wireButtonToCallback('#collectionCancelButton', 'collection_cancel_callback');
   },

   _demands: function() {
   	var array = [];
      var demands = this.get('model.data.demands');
      if (demands) {
      	array = radiant.map_to_array(demands.items, function(k, v) {
            if (v.uri) {
               var catalogData = App.catalog.getCatalogData(v.uri);
               if (catalogData && catalogData.display_name) {
                  v.display_name = catalogData.display_name;
               }
               v.formatted_cached_count = v.cached_count == null ? '' :
                  ` <span class='numCached'>(${v.cached_count})</span>`;
            }
            return v;
         });
      }
      this.set('demands', array);
   }.observes('model.data.demands'),

});
