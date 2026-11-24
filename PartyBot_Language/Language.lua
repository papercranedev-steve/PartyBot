-- PartyBot's language choice: PartyBotLanguageDB.lang = "zh" | "en" (nil: the client's language).
--
-- A separate addon because WoW loads an addon's saved variables only after all its files ran,
-- and PartyBot builds its windows and tables (with their text) while its files run. PartyBot
-- lists this one in OptionalDeps, so this one is loaded, saved variables included, before
-- PartyBot's first file. PartyBot writes the choice (its Language window entry, /pblang).
--
-- The table exists before anything was ever saved (no saved-variables file yet): PartyBot takes a
-- missing table for a missing addon. A saved choice, loaded after this file, replaces it.

PartyBotLanguageDB = PartyBotLanguageDB or {}
