local ns = {}
assert(loadfile("SetupLocales.lua"))("ApplicantScout", ns)
local locales = ns.CompanionSetupLocales
local supported = {"enUS", "deDE", "esES", "esMX", "frFR", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW"}
local keys = {"title", "step", "language", "download", "guide", "later", "done", "back", "next", "finish", "copy", "deferred", "automatic", "details", "less", "source", "wcl", "preview", "noAuto", "enableAuto", "reminder", "companionDownload", "settings"}
local count = 0
for _ in pairs(locales) do count = count + 1 end
assert(count == #supported, "unexpected translation inventory")
for _, code in ipairs(supported) do
    local language = assert(locales[code], "missing locale " .. code)
    assert(type(language.name) == "string" and #language.name > 0, "missing native language name")
    assert(#language.pages == 5, "incomplete guide for " .. code)
    for _, key in ipairs(keys) do
        assert(type(language.ui[key]) == "string" and #language.ui[key] > 0, "missing caption " .. key .. " in " .. code)
    end
    assert(#language.menu == 19, "incomplete menu for " .. code)
    for _, caption in ipairs(language.menu) do
        assert(type(caption) == "string" and #caption > 0, "empty menu caption in " .. code)
    end
    assert(not language.pages[5].summary:find("/apscout setup", 1, true), "automatic-opening help replaced the visible connection check")
    assert(type(string.format(language.ui.step, 2, 5)) == "string", "invalid step format")
    for step, page in ipairs(language.pages) do
        for _, key in ipairs({"title", "body", "hint", "summary", "chapter"}) do
            assert(type(page[key]) == "string" and #page[key] > 0, "incomplete step " .. step .. " in " .. code)
        end
        if code ~= "enUS" then
            assert(page.body ~= locales.enUS.pages[step].body, "English body was substituted for " .. code)
            assert(page.summary ~= locales.enUS.pages[step].summary, "English short steps were substituted for " .. code)
        end
    end
    for step, terms in pairs({
        [1] = {"GitHub", "Warcraft Logs", "Companion"},
        [2] = {"ApplicantScoutCompanionSetup-*.exe", ".sha256", "SmartScreen"},
        [3] = {"http://localhost", "Public Client", "Client ID", "Client Secret", "Test WCL"},
        [4] = {"Screenshots", "Start and stop with WoW", "Share usage statistics", "Start companion"},
        [5] = {"/apscout on", "/apscout shotnow", "/apscout setup", "Show overlay", "Test WCL"},
    }) do
        for _, term in ipairs(terms) do
            assert(language.pages[step].body:find(term, 1, true), "missing external UI term " .. term .. " in " .. code)
        end
    end
    for step, terms in pairs({
        [1] = {"Companion", "Warcraft Logs", "GitHub"},
        [2] = {"ApplicantScoutCompanionSetup-*.exe", "Assets", "Ctrl+C"},
        [3] = {"http://localhost", "Public Client", "Client ID", "Client Secret", "Test WCL"},
        [4] = {"Screenshots", "Start companion"},
        [5] = {"/apscout on", "Party", "Companion"},
    }) do
        for _, term in ipairs(terms) do
            assert(language.pages[step].summary:find(term, 1, true), "missing short-step UI term " .. term .. " in " .. code)
        end
    end
end
print("ok complete translations")
