"""Tests for strings.json: python3 -m unittest discover -s tests"""
import gettext
import json
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME_STRINGS = os.path.expanduser(
    "~/.local/share/Steam/steamapps/common/Transport Fever 3/base/strings")
LANGS = ["en", "ja", "de", "es", "fr", "it", "ko", "nl", "pl", "pt_BR", "ru",
         "zh_CN", "zh_TW"]
P = "hummer_force_unload_default_"
# the checkbox in the cargo filter window and its tooltip
# (gui/line_vehicle_mgmt/cargofilter_window.tl), the window title, and the
# word the base uses for a line's stops
FORCE_UNLOAD = "Force Unload All Cargo On Arrival"
FORCE_UNLOAD_TIP = "Unload cargo even if stocks are full."
LINE_MANAGER = "Line Manager"
STOPS = "Stops"
# the release names chosen by the user (2026-11-22); modId and folder stay
# hummer_force_unload_default(_1)
MOD_NAMES = {"en": "Auto Force Unload at Drop-off Stops",
             "ja": "降ろすだけの駅に積み下ろし強制を自動設定"}
# the parts of each mod name that stand for "force unload": taken from the
# base game's checkbox text, compared case-insensitively
FORCE_UNLOAD_IN_NAME = {
    "en": ["Force Unload"], "ja": ["積み下ろし", "強制"],
    "de": ["Entladen", "erzwingen"], "es": ["Forzar la descarga"],
    "fr": ["Forcer le déchargement"], "it": ["Forza scarico"],
    "ko": ["강제 하차"], "nl": ["verplicht lossen"],
    "pl": ["wymu", "rozładowani"], "pt_BR": ["Forçar descarregamento"],
    "ru": ["принудительно выгружать"], "zh_CN": ["强制卸下"],
    "zh_TW": ["強制卸載"]}
# where the base word does not fit a mod setting button: Italian "Off" is
# "Mai" (never) in the base catalogue
VANILLA_OVERRIDES = {("it", "Off"): "No"}


def load_strings():
    with open(os.path.join(ROOT, "strings.json"), encoding="utf-8") as f:
        return json.load(f)


def catalog(lang):
    mo = os.path.join(GAME_STRINGS, lang, "LC_MESSAGES", "base.mo")
    with open(mo, "rb") as f:
        cat = gettext.GNUTranslations(f)

    def vanilla(key):
        if (lang, key) in VANILLA_OVERRIDES:
            return VANILLA_OVERRIDES[(lang, key)]
        # en has no msgstr: the key is the English text
        return cat.gettext(key)
    return vanilla


class StringsTest(unittest.TestCase):
    def test_all_game_languages_have_the_same_keys(self):
        s = load_strings()
        self.assertEqual(sorted(s), sorted(LANGS))
        for lang in LANGS:
            self.assertEqual(sorted(s[lang]), sorted(s["en"]), lang)
            for key, value in s[lang].items():
                self.assertTrue(value.strip(), "%s: %s empty" % (lang, key))

    def test_ui_words_are_the_vanilla_ones(self):
        # players look for the checkbox, the window and the buttons by the
        # words the game shows them
        if not os.path.isdir(GAME_STRINGS):
            self.skipTest("game strings not found")
        s = load_strings()
        for lang in LANGS:
            v, t = catalog(lang), s[lang]
            if lang != "en":
                for key in (FORCE_UNLOAD, FORCE_UNLOAD_TIP, LINE_MANAGER,
                            STOPS, "On", "Off"):
                    self.assertNotEqual(v(key), key, "%s: %r not in base.mo"
                                        % (lang, key))
            fu = v(FORCE_UNLOAD)
            for key in ("mod_desc", P + "icon_param_tip"):
                self.assertIn(fu, t[key], "%s %s" % (lang, key))
            self.assertIn(v(LINE_MANAGER), t["mod_desc"], lang)
            self.assertIn(v(STOPS).casefold(),
                          t[P + "mode_name"].casefold(), lang)
            self.assertEqual(t[P + "on"], v("On"), lang)
            self.assertEqual(t[P + "off"], v("Off"), lang)
            # the button values open the two halves of the param tooltip
            tip = t[P + "icon_param_tip"]
            self.assertTrue(tip.startswith(v("On")), lang)
            self.assertIn(v("Off"), tip, lang)
            # the marker tooltip repeats the checkbox and its tooltip
            icon = t[P + "icon_tip"]
            first, _, second = icon.partition("\n")
            self.assertTrue(first.startswith(fu), "%s: %r" % (lang, icon))
            self.assertTrue(first.endswith(v("On")), "%s: %r" % (lang, icon))
            self.assertEqual(second, v(FORCE_UNLOAD_TIP), lang)

    def test_mod_names(self):
        s = load_strings()
        for lang, name in MOD_NAMES.items():
            self.assertEqual(s[lang]["mod_name"], name)
        self.assertEqual(sorted(FORCE_UNLOAD_IN_NAME), sorted(LANGS))
        for lang in LANGS:
            for part in FORCE_UNLOAD_IN_NAME[lang]:
                self.assertIn(part.casefold(),
                              s[lang]["mod_name"].casefold(), lang)
        if not os.path.isdir(GAME_STRINGS):
            self.skipTest("game strings not found")
        for lang in LANGS:
            for part in FORCE_UNLOAD_IN_NAME[lang]:
                self.assertIn(part.casefold(),
                              catalog(lang)(FORCE_UNLOAD).casefold(), lang)

    def test_mod_io_page_text_matches_my_mods(self):
        # docs/modio_description.md is pasted by hand on the mod.io page:
        # its summary and headings must follow renames of the mod
        s = load_strings()
        with open(os.path.join(ROOT, "_metadata", "modinfo.json"),
                  encoding="utf-8") as f:
            info = json.load(f)
        with open(os.path.join(ROOT, "docs", "modio_description.md"),
                  encoding="utf-8") as f:
            page = f.read()
        self.assertIn("**Summary:** %s\n" % info["summary"], page)
        self.assertIn("## English: %s\n" % s["en"]["mod_name"], page)
        self.assertIn("## 日本語: %s\n" % s["ja"]["mod_name"], page)

    def test_my_mods_text_matches_the_strings(self):
        # My Mods shows _metadata/modinfo.json, the mod settings show
        # strings.json: keep the two descriptions from drifting apart
        s = load_strings()
        with open(os.path.join(ROOT, "_metadata", "modinfo.json"),
                  encoding="utf-8") as f:
            info = json.load(f)
        self.assertEqual(info["name"], "%s / %s" % (s["en"]["mod_name"],
                                                   s["ja"]["mod_name"]))
        self.assertEqual(info["description"],
                         "[English] %s\n%s\n\n[日本語] %s\n%s"
                         % (s["en"]["mod_name"], s["en"]["mod_desc"],
                            s["ja"]["mod_name"], s["ja"]["mod_desc"]))


if __name__ == "__main__":
    unittest.main()
