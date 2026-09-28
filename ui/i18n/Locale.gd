## Game language. UI code is written with English source strings; every Control / Label3D text
## that matches a key of the active catalogue is translated by Godot on its own (auto-translate),
## and code that formats text calls tr() / Locale.t() on the pattern first ("%d  ALIVE").
## Keys that are also ids (character, ability, item names) stay English in code and on the network.
## Default language: Russian (GameSettings.language).
extends RefCounted
class_name Locale

const LANGUAGES = {"ru": "Русский", "en": "English"}

static var _installed := false

static func setup(language: String) -> void:
	if not _installed:
		var ru = Translation.new()
		ru.locale = "ru"
		for key in LocaleRu.STRINGS:
			ru.add_message(key, LocaleRu.STRINGS[key])
		for key in LocaleRu.SHORT:
			ru.add_message(key, LocaleRu.SHORT[key], "short")
		TranslationServer.add_translation(ru)
		_installed = true
	TranslationServer.set_locale(language if LANGUAGES.has(language) else "ru")

## tr() for static code and RefCounted classes
static func t(key: String, context: String = "") -> String:
	return String(TranslationServer.translate(key, context))
