App.StonehearthCitizenCharacterSheetView.reopen({
   //Go through each job we've had and annotate the perk table accordingly
   _updateJobsAndPerks : function() {
      var self = this;

      //Hide all the job divs before selectively showing the ones for the current
      //character.
      if (!self.$('.jobData')) {
         return; // this can happen if character is destroyed.
      }

      self.$('.jobData').hide();

      //show each class that this person has ever been
      var allJobData = App.jobConstants;
      var jobs = this.get('model.stonehearth:job.job_controllers');
      var workerDivs = [];
      radiant.each(jobs, function(alias, data) {
         var job_alias = data.json_path;
         var isWorker = job_alias == 'stonehearth:jobs:worker';
         var hasPerks = job_alias != 'stonehearth:jobs:worker';
         var jobData = allJobData[job_alias];
         if (jobData) {
            isWorker = jobData.description.is_worker;
            hasPerks = false;
            if (jobData.description.levelArray) {
               jobData.description.levelArray.forEach(levelData => {
                  if (levelData.perks && levelData.perks.length > 0) {
                     hasPerks = true;
                  }
               });
            }
         }
         else {
            job_alias = alias;
         }

         if (hasPerks) {
            var div = self.$("[uri='" + job_alias + "']");

            //For each, figure out which perks should be unlocked
            self._unlockPerksToLevel(div, data.last_gained_lv)

            $(div).show();

            if (isWorker) {
               workerDivs.push(div);
            }
         }
      });

      //Highlight current class, since it needs to be 100% up to date
      self.$('.activeClassNameHeader').removeClass('activeClassNameHeader');
      self.$('.className').addClass('retiredClassNameHeader');
      self.$('.jobData').addClass('retiredEffect');
      var currClassAlias = this.get('model.stonehearth:job.job_json_path');
      var $currClass = self.$("[uri='" + currClassAlias + "']");
      $currClass.prependTo("#citizenCharacterSheet #abilitiesTab");
      $currClass.find('.className').removeClass('retiredClassNameHeader').addClass('activeClassNameHeader');
      $currClass.removeClass('retiredEffect');
      //$currClass.removeClass('retiredClassNameHeader').addClass('activeClassNameHeader');
      self._unlockPerksToLevel($currClass,  this.get('model.stonehearth:job.curr_job_controller.last_gained_lv'))
      $currClass.find('.retiredAt').hide();

      workerDivs.forEach(div => {
         div.find('.retiredAt').hide();
      });

      //Make the job tooltips
      this._updateJobTooltips();
   }
});
