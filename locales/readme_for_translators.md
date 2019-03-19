Hello, translators!

This is a short readme file explaining the 3 default files for Localizations that ACE contains and the 2 that every language must contain.

The default files are:
	en.json
	locales_mixin.json
	en_mixin.json 
	
The files that every language should have (using pt-BR as example) are:
	pt-BR.json
	pt-BR_mixin.json 
	
An explanation of each file:

	[ en.json ]
		This file is the default localization file of ACE, in english. All the things that ACE contains, all interface text, descriptions, names, etc... They are all listed here.
		For maintaining a functional translation, you must keep this file exactly the same as the english version in terms of structure, keys and hierarchy - but change the strings between quotes ("")
		
	[ locales_mixin.json ]
		Some things are read by the code straight from the stonehearth main localization file. This is, unfortunately, something that is part of the game code and changing it to read from individual mods
		would be more annoying than good. An easy solution is to simply mix into the stonehearth localization file and add the keys we need - and to keep things compatible to any language, the locales_mixin
		itself is localized, taking all the translations from the en.json or whatever other language is active.
		
	[ en_mixin.json ]
		Similar to the locales_mixin, this file is not localized, however. It exists for situations where localization itself is not the issue (ie: fixing base game typos) or in some few cases where the
		localized strings are necessary before mods are loaded, so they must be mixed into the base game straight as text instead of localization keys that require other mods to be loaded. For that reason 
		this file must exist for each different language and must be mixed into the main file of your own language's translation inside the stonehearth mod. For example, if the pt-BR mod inserts a 
		pt-BR.json file inside /stonehearth/locales/, then this file mixinto inside the stonehearth_ace manifest must be:
		
			"stonehearth/locales/pt-BR.json": "file(locales/pt-BR_mixin.json"
			
		It is the responsibility of the one responsible for the translations to find the correct path for their own language mods and add it to the ACE manifest. 