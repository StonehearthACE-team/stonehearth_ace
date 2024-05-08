App.StonehearthRecipeUnlockBulletinDialog = App.StonehearthBaseBulletinDialog.extend({
   templateName: 'recipeUnlockBulletinDialog',

   didInsertElement: function() {
      this._super();

      this._wireButtonToCallback('.closeButton', '_nop');
   },

   actions: {
      // TODO: add action to open the corresponding workshop and select the recipe
      select: function(recipe) {
         App.workshopManager.getWorkshop(recipe.job_alias, function(workshop) {
            if (workshop) {
               workshop.show();
               workshop.selectRecipe(recipe.recipe_key);
            }
         });
      }
   }
});
