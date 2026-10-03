-- Setup translations share the same five-page order. URLs and transport stay in the runtime.
local _, ns = ...
local locales = {["enUS"] = {["name"] = "English",
["ui"] = {["title"] = "ApplicantScout: first-time setup",
["step"] = "Step %d of %d",
["language"] = "Language",
["download"] = "Download link",
["guide"] = "Illustrated guide",
["later"] = "Later",
["done"] = "Already set up",
["back"] = "Back",
["next"] = "Next",
["finish"] = "Finish guide",
["copy"] = "Select a link, press Ctrl+C, then paste it into your browser outside WoW.",
["deferred"] = "Setup will open when loading, combat or the current encounter/key ends."},
["pages"] = {{["title"] = "Why you need the Windows companion",
["body"] = "ApplicantScout has two parts. This WoW addon collects your Group Finder applicants and party/raid roster. The free Windows companion fetches Warcraft Logs results and shows the applicant table beside WoW. The addon alone cannot show that table.\n\nHow data travels:\nAddon -> QR code -> normal WoW screenshot -> Companion -> Warcraft Logs -> overlay.\n\nWoW addons cannot make these web requests directly. The addon briefly displays a QR image and uses WoW's screenshot function. Companion reads it from your Screenshots folder locally; the screenshot itself is not uploaded to Warcraft Logs.\n\nBoth parts are open source. You can inspect the code on GitHub. No WoW memory reading, code injection or automatic invitations; you choose whom to invite. No Blizzard password is needed.",
["hint"] = "Source code is public. This is an independent project, not an official Blizzard app."},
{["title"] = "Install ApplicantScout Companion",
["body"] = "1. Select the download link below, press Ctrl+C, then paste it into your browser.\n\n2. On GitHub's latest release, expand Assets and download ApplicantScoutCompanionSetup-*.exe. This is the Windows installer, not an Excel file. Do not choose Source code or the .sha256 checksum.\n\n3. Run the installer, then open ApplicantScout Companion from the Windows Start menu. The app opens its first-run settings.\n\nThe portable ZIP is an alternative if you prefer to unpack and run the app yourself.\n\nCurrent Windows releases are unsigned, so Windows SmartScreen may show an unknown publisher. Use the official GitHub release linked here and decide whether you trust the source. Open source and checksums do not guarantee publisher identity.",
["hint"] = "Windows is required. Use Illustrated guide for setup screenshots in your browser."},
{["title"] = "Connect your free Warcraft Logs account",
["body"] = "1. Create a free Warcraft Logs account or sign in, then open API Clients using the link below.\n\n2. Choose Create Client and name it ApplicantScout.\n\n3. Set Redirect URL to exactly http://localhost. Leave Public Client UNCHECKED, then create the client.\n\n4. Copy the generated Client ID and Client Secret into the matching fields in Companion Settings. Use Test WCL to check the connection.\n\nThese are API credentials for reading public Warcraft Logs data, not your WoW login. Keep the Client Secret private and enter it only in Companion, never in WoW chat or a support screenshot.\n\nThe Illustrated guide includes the Create Client form. Companion also has a WCL setup example in Settings.",
["hint"] = "If Test WCL fails, check both copied fields before continuing."},
{["title"] = "Choose folders and startup options",
["body"] = "1. In Companion Settings, select the Screenshots folder inside the WoW client you actually play: _retail_\\Screenshots (or _ptr_ / _xptr_ for PTR). If it does not exist, take a normal screenshot in WoW first.\n\n2. Leave Mythic+ and the raid difficulties you want checked. Optional RaiderIO addon data adds dungeon and raid context.\n\n3. Keep Start and stop with WoW checked if you want Companion to open with the game. A hidden Windows sign-in watcher waits for WoW. If Windows blocks it, use Enable watcher or Repair watcher in Settings. You can also launch Companion manually.\n\n4. Share usage statistics is optional and starts off. Choose whether to enable it; scouting works without it.\n\n5. Click Start companion to save the first setup. Keep the app running alongside WoW.",
["hint"] = "Select the client-specific Screenshots folder, not Interface or AddOns."},
{["title"] = "Check your first applicant or party results",
["body"] = "1. Keep Companion running, return to WoW and use /apscout on. Test out of combat and before starting a Mythic+ key.\n\n2. Open your Group Finder listing with applicants, or join a group and select Party in Companion.\n\n3. If only the small Companion launcher is visible, click it to open the full overlay. If it is missing, use Show overlay from the Windows tray menu.\n\n4. The addon briefly shows a QR code and takes a screenshot automatically. Check that the overlay shows the same player names, then Warcraft Logs results where public logs exist.\n\nNo names? Check the Screenshots folder and try /apscout shotnow. Names but no WCL? Use Test WCL; some players have no public logs. Updates pause in combat, active Mythic+ runs and raid boss encounters.\n\nFinish guide stops its automatic first-login reminder. It does not verify your installation: the addon cannot detect Companion. Reopen any step with /apscout setup.",
["hint"] = "Keep this addon updated through CurseForge:\nhttps://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"}}}}
ns.CompanionSetupLocales = locales
locales.enUS.ui.download = "Select download link"

local function translated(name, captions, titles, bodies, hints)
    local ui, pages = {}, {}
    local keys = {"title", "step", "language", "download", "guide", "later", "done", "back", "next", "finish", "copy", "deferred"}
    for index, key in ipairs(keys) do ui[key] = captions[index] end
    for index = 1, 5 do pages[index] = {title = titles[index], body = bodies[index], hint = hints[index]} end
    return {name = name, ui = ui, pages = pages}
end

locales.ruRU = translated("Русский",
    {"ApplicantScout: первая настройка", "Шаг %d из %d", "Язык", "Ссылка на установщик", "Гид с картинками", "Позже", "Уже настроено", "Назад", "Далее", "Завершить гид", "Выделите ссылку, нажмите Ctrl+C и вставьте её в браузер вне WoW.", "Настройка откроется после загрузки, боя, босса или активного ключа."},
    {"Зачем нужна программа Companion", "Установка ApplicantScout Companion", "Подключение Warcraft Logs", "Папка скриншотов и запуск", "Проверка первых результатов"},
    {
        [[ApplicantScout состоит из двух частей. Аддон собирает заявки из поиска группы и состав группы/рейда. Бесплатная программа Companion для Windows запрашивает Warcraft Logs и показывает таблицу рядом с WoW. Один аддон эту таблицу не показывает.

Путь данных: аддон -> QR-код -> обычный скриншот WoW -> Companion -> Warcraft Logs -> оверлей.

Аддон не может сам выполнять эти веб-запросы. Он ненадолго показывает QR-код и делает скриншот средствами WoW. Companion читает его локально из Screenshots; сам скриншот в Warcraft Logs не отправляется.

Исходники обеих частей открыты на GitHub. Нет чтения памяти WoW, внедрения кода или автоматических приглашений. Решение принимаешь ты. Пароль Blizzard не нужен.]],
        [[1. Выдели ссылку на установщик, нажми Ctrl+C и вставь её в браузер.

2. В последнем релизе GitHub раскрой Assets и скачай ApplicantScoutCompanionSetup-*.exe. Это установщик Windows, не Excel-файл. Source code и .sha256 не являются установщиком.

3. Запусти установщик, затем открой ApplicantScout Companion из меню «Пуск». Появится первая настройка.

Portable ZIP — альтернатива для ручной распаковки и запуска.

Текущие сборки не подписаны: SmartScreen может показать неизвестного издателя. Используй указанный GitHub и оцени доверие к источнику. Открытый код и контрольная сумма не гарантируют личность издателя.]],
        [[1. Создай бесплатный аккаунт Warcraft Logs или войди в него. Открой API Clients по ссылке ниже.

2. Нажми Create Client и назови клиент ApplicantScout.

3. В Redirect URL укажи ровно http://localhost. Галочку Public Client НЕ ставь. Создай клиент.

4. Вставь Client ID и Client Secret в соответствующие поля настроек Companion. Нажми Test WCL для проверки.

Это API-ключи для публичных данных Warcraft Logs, не вход в WoW. Держи Client Secret в тайне: вводи только в Companion, не в чат и не на скриншотах для поддержки.

Гид с картинками показывает Create Client. В настройках Companion также есть пример настройки WCL.]],
        [[1. В Companion выбери Screenshots внутри клиента WoW, в котором играешь: _retail_\Screenshots (для PTR — _ptr_ или _xptr_). Если папки нет, сначала сделай обычный скриншот в WoW.

2. Оставь Mythic+ и нужные сложности рейда. Необязательный аддон RaiderIO добавляет контекст подземелий и рейдов.

3. Start and stop with WoW запускает программу вместе с игрой. Скрытый помощник запускается при входе в Windows и ждёт WoW. Если он заблокирован, используй Enable watcher или Repair watcher. Можно запускать Companion вручную.

4. Share usage statistics — добровольная статистика, по умолчанию выключена. Работа программы от неё не зависит.

5. Нажми Start companion, чтобы сохранить настройку. Оставь программу запущенной рядом с WoW.]],
        [[1. Оставь Companion запущенным и введи /apscout on в WoW. Проверяй вне боя и до начала ключа.

2. Открой свою группу с заявками в поиске группы либо вступи в группу и выбери Party в Companion.

3. Если видно только маленькое окно Companion, нажми его для полного оверлея. Если окна нет, выбери Show overlay в меню значка программы в трее Windows.

4. Аддон покажет QR-код и автоматически сделает скриншот. Проверь совпадение имён, затем результаты Warcraft Logs, если публичные логи есть.

Нет имён? Проверь Screenshots и попробуй /apscout shotnow. Имена есть, WCL нет? Нажми Test WCL; у игрока может не быть логов. Обновления приостанавливаются в бою, активном ключе и на рейдовых боссах.

Завершение гида отключает автопоказ, но не проверяет установку: аддон не видит Companion. Открыть снова: /apscout setup.]]
    },
    {"Открытый независимый проект; не официальная программа Blizzard.", "Нужна Windows. Гид с картинками доступен в браузере.", "Если Test WCL не прошёл, проверь оба скопированных поля.", "Нужна папка Screenshots нужного клиента, не Interface или AddOns.", "Обновляй аддон через CurseForge:\nhttps://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"})

locales.frFR = translated("Français",
    {"ApplicantScout : première configuration", "Étape %d sur %d", "Langue", "Lien de téléchargement", "Guide illustré", "Plus tard", "Déjà configuré", "Retour", "Suivant", "Terminer le guide", "Sélectionnez le lien, faites Ctrl+C et collez-le dans le navigateur hors de WoW.", "La configuration s’ouvrira après le chargement, le combat, le boss ou la clé active."},
    {"Pourquoi installer Companion pour Windows", "Installer ApplicantScout Companion", "Connecter Warcraft Logs", "Dossier et options de démarrage", "Vérifier les premiers résultats"},
    {
        [[ApplicantScout comprend deux parties. L’addon collecte les candidatures et les membres du groupe/raid. L’application Windows gratuite Companion interroge Warcraft Logs et affiche le tableau à côté de WoW. L’addon seul ne peut pas afficher ce tableau.

Trajet : addon -> QR code -> capture WoW -> Companion -> Warcraft Logs -> fenêtre superposée.

Les addons ne peuvent pas effectuer ces requêtes web directement. L’addon affiche brièvement un QR code et prend une capture normale. Companion la lit localement dans Screenshots ; l’image n’est pas envoyée à Warcraft Logs.

Le code des deux parties est public sur GitHub. Aucune lecture de mémoire WoW, injection de code ou invitation automatique. Vous décidez. Aucun mot de passe Blizzard requis.]],
        [[1. Sélectionnez le lien, faites Ctrl+C et collez-le dans votre navigateur.

2. Dans la dernière version GitHub, ouvrez Assets et téléchargez ApplicantScoutCompanionSetup-*.exe. C’est un installateur Windows, pas un fichier Excel. Source code et .sha256 ne sont pas des installateurs.

3. Lancez l’installateur puis ApplicantScout Companion depuis le menu Démarrer. La première configuration s’affiche.

Le ZIP portable permet aussi un lancement manuel après extraction.

Les versions actuelles ne sont pas signées ; SmartScreen peut signaler un éditeur inconnu. Utilisez la version GitHub indiquée et évaluez votre confiance. Code ouvert et sommes de contrôle ne garantissent pas l’identité de l’éditeur.]],
        [[1. Créez un compte Warcraft Logs gratuit ou connectez-vous. Ouvrez API Clients via le lien.

2. Choisissez Create Client et nommez-le ApplicantScout.

3. Saisissez exactement http://localhost dans Redirect URL. Ne cochez PAS Public Client, puis créez le client.

4. Copiez Client ID et Client Secret dans les champs correspondants de Companion. Cliquez sur Test WCL.

Ce sont des identifiants API pour les données publiques Warcraft Logs, pas une connexion WoW. Gardez Client Secret privé, uniquement dans Companion, jamais dans le chat ou une capture de support.

Le guide illustré montre Create Client. Companion propose aussi un exemple WCL.]],
        [[1. Choisissez Screenshots du client utilisé : _retail_\Screenshots, ou _ptr_ / _xptr_ pour le PTR. S’il manque, prenez d’abord une capture normale dans WoW.

2. Gardez Mythic+ et les difficultés de raid souhaitées cochés. RaiderIO, facultatif, ajoute du contexte sur les donjons et raids.

3. Start and stop with WoW lance Companion avec le jeu. Un assistant caché démarre à la connexion Windows et attend WoW. S’il est bloqué, utilisez Enable watcher ou Repair watcher. Le lancement manuel reste possible.

4. Share usage statistics est facultatif et désactivé initialement. L’application fonctionne sans partage.

5. Cliquez sur Start companion pour enregistrer et laissez l’application ouverte avec WoW.]],
        [[1. Laissez Companion ouvert et tapez /apscout on. Testez hors combat et avant une clé.

2. Ouvrez votre annonce avec des candidats, ou rejoignez un groupe et sélectionnez Party.

3. Cliquez sur la petite fenêtre pour ouvrir le tableau complet. Si elle manque, utilisez Show overlay dans le menu de l’icône Windows.

4. L’addon montre brièvement un QR code et prend une capture automatiquement. Vérifiez les mêmes noms puis les résultats Warcraft Logs, si des logs publics existent.

Aucun nom ? Vérifiez Screenshots et essayez /apscout shotnow. Noms sans WCL ? Test WCL ; certains joueurs n’ont pas de logs. Les mises à jour s’arrêtent pendant combats, clés actives et boss de raid.

Terminer le guide arrête le rappel sans vérifier l’installation : l’addon ne détecte pas Companion. Réouverture : /apscout setup.]]
    },
    {"Projet indépendant à code ouvert, pas une application officielle Blizzard.", "Windows requis. Guide illustré disponible dans le navigateur.", "Si Test WCL échoue, vérifiez les deux champs copiés.", "Choisissez Screenshots du bon client, pas Interface ou AddOns.", "Mettez l’addon à jour via CurseForge :\nhttps://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"})

locales.itIT = translated("Italiano",
    {"ApplicantScout: prima configurazione", "Passo %d di %d", "Lingua", "Link download", "Guida illustrata", "Più tardi", "Già configurato", "Indietro", "Avanti", "Termina guida", "Seleziona il link, premi Ctrl+C e incollalo nel browser fuori da WoW.", "La configurazione si aprirà dopo caricamento, combattimento, boss o chiave attiva."},
    {"Perché serve Companion per Windows", "Installare ApplicantScout Companion", "Collegare Warcraft Logs", "Cartella e avvio automatico", "Verificare i primi risultati"},
    {
        [[ApplicantScout ha due parti. L’addon raccoglie candidati e membri del gruppo/incursione. Companion, gratuito per Windows, consulta Warcraft Logs e mostra la tabella accanto a WoW. L’addon da solo non può mostrarla.

Percorso: addon -> codice QR -> screenshot WoW -> Companion -> Warcraft Logs -> overlay.

Gli addon non possono fare queste richieste web direttamente. L’addon mostra brevemente un QR e usa lo screenshot normale di WoW. Companion lo legge localmente da Screenshots; l’immagine non viene caricata su Warcraft Logs.

Il codice di entrambe le parti è pubblico su GitHub. Nessuna lettura della memoria WoW, iniezione di codice o invito automatico. Decidi tu. Non serve la password Blizzard.]],
        [[1. Seleziona il link download, premi Ctrl+C e incollalo nel browser.

2. Nell’ultima release GitHub apri Assets e scarica ApplicantScoutCompanionSetup-*.exe. È l’installer Windows, non un file Excel. Source code e .sha256 non sono installer.

3. Esegui l’installer e apri ApplicantScout Companion dal menu Start. Apparirà la prima configurazione.

Il ZIP portatile è un’alternativa da estrarre e avviare manualmente.

Le build attuali non sono firmate; SmartScreen può mostrare un autore sconosciuto. Usa la release GitHub indicata e valuta se ti fidi. Codice aperto e checksum non garantiscono l’identità dell’autore.]],
        [[1. Crea un account Warcraft Logs gratuito o accedi. Apri API Clients dal link.

2. Scegli Create Client e usa il nome ApplicantScout.

3. Imposta Redirect URL esattamente su http://localhost. NON selezionare Public Client, poi crea il client.

4. Copia Client ID e Client Secret nei campi corrispondenti di Companion. Premi Test WCL.

Sono credenziali API per i dati pubblici Warcraft Logs, non per accedere a WoW. Mantieni privato Client Secret e inseriscilo solo in Companion, mai in chat o negli screenshot di assistenza.

La guida illustrata mostra Create Client. Companion offre anche un esempio WCL.]],
        [[1. Scegli Screenshots del client usato: _retail_\Screenshots, oppure _ptr_ / _xptr_ per PTR. Se manca, fai prima uno screenshot normale in WoW.

2. Seleziona Mythic+ e le difficoltà di incursione desiderate. RaiderIO è facoltativo e aggiunge contesto su spedizioni e incursioni.

3. Start and stop with WoW avvia Companion con il gioco. Un assistente nascosto parte all’accesso Windows e attende WoW. Se bloccato, usa Enable watcher o Repair watcher. Puoi anche avviare l’app manualmente.

4. Share usage statistics è facoltativo e inizialmente disattivato. L’app funziona senza condivisione.

5. Premi Start companion per salvare e lascia l’app aperta con WoW.]],
        [[1. Lascia Companion aperto e digita /apscout on. Prova fuori dal combattimento e prima di una chiave.

2. Apri il tuo annuncio con candidati oppure entra in un gruppo e seleziona Party.

3. Clicca sulla piccola finestra per aprire l’overlay completo. Se manca, usa Show overlay dal menu dell’icona Windows.

4. L’addon mostra brevemente un QR e scatta uno screenshot automatico. Controlla i nomi e i risultati Warcraft Logs, se esistono log pubblici.

Nessun nome? Controlla Screenshots e prova /apscout shotnow. Nomi senza WCL? Usa Test WCL; alcuni giocatori non hanno log. Aggiornamenti sospesi in combattimento, chiavi attive e boss di incursione.

Termina guida elimina il promemoria ma non verifica l’installazione: l’addon non rileva Companion. Riapri con /apscout setup.]]
    },
    {"Progetto indipendente open source, non un’app ufficiale Blizzard.", "Serve Windows. Guida illustrata disponibile nel browser.", "Se Test WCL fallisce, verifica entrambi i campi copiati.", "Scegli Screenshots del client corretto, non Interface o AddOns.", "Aggiorna l’addon tramite CurseForge:\nhttps://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"})

locales.ptBR = translated("Português (Brasil)",
    {"ApplicantScout: configuração inicial", "Etapa %d de %d", "Idioma", "Link de download", "Guia ilustrado", "Mais tarde", "Já configurado", "Voltar", "Avançar", "Concluir guia", "Selecione o link, pressione Ctrl+C e cole no navegador fora do WoW.", "A configuração abrirá após carregamento, combate, chefe ou chave ativa."},
    {"Por que instalar Companion para Windows", "Instalar ApplicantScout Companion", "Conectar Warcraft Logs", "Pasta e opções de inicialização", "Verificar os primeiros resultados"},
    {
        [[ApplicantScout tem duas partes. O addon coleta candidatos e integrantes do grupo/raide. O Companion gratuito para Windows consulta Warcraft Logs e mostra a tabela ao lado do WoW. O addon sozinho não exibe essa tabela.

Caminho: addon -> QR code -> captura WoW -> Companion -> Warcraft Logs -> sobreposição.

Addons não podem fazer essas consultas web diretamente. O addon mostra um QR brevemente e faz uma captura normal. Companion lê a imagem localmente em Screenshots; ela não é enviada ao Warcraft Logs.

O código das duas partes é aberto no GitHub. Não lê memória WoW, injeta código ou convida jogadores automaticamente. Você decide. Não precisa da senha Blizzard.]],
        [[1. Selecione o link de download, pressione Ctrl+C e cole no navegador.

2. Na versão mais recente do GitHub, abra Assets e baixe ApplicantScoutCompanionSetup-*.exe. É o instalador Windows, não um arquivo Excel. Source code e .sha256 não são instaladores.

3. Execute o instalador e abra ApplicantScout Companion pelo menu Iniciar. A configuração inicial aparecerá.

O ZIP portátil permite extrair e executar manualmente.

As versões atuais não são assinadas; SmartScreen pode indicar um editor desconhecido. Use a versão GitHub indicada e avalie se confia. Código aberto e checksums não garantem a identidade do editor.]],
        [[1. Crie uma conta gratuita no Warcraft Logs ou entre nela. Abra API Clients pelo link.

2. Selecione Create Client e use o nome ApplicantScout.

3. Em Redirect URL, coloque exatamente http://localhost. NÃO marque Public Client. Crie o cliente.

4. Copie Client ID e Client Secret para os campos correspondentes do Companion. Clique em Test WCL.

São credenciais API para dados públicos Warcraft Logs, não um login WoW. Mantenha Client Secret privado; digite apenas no Companion, nunca no chat ou em capturas de suporte.

O guia ilustrado mostra Create Client. Companion também oferece um exemplo WCL.]],
        [[1. Selecione Screenshots do cliente jogado: _retail_\Screenshots, ou _ptr_ / _xptr_ para PTR. Se não existir, faça antes uma captura normal no WoW.

2. Marque Mythic+ e as dificuldades de raide desejadas. RaiderIO é opcional e acrescenta contexto de masmorras e raides.

3. Start and stop with WoW abre Companion com o jogo. Um auxiliar oculto inicia no login Windows e espera o WoW. Se bloqueado, use Enable watcher ou Repair watcher. Também pode abrir o aplicativo manualmente.

4. Share usage statistics é opcional e começa desativado. O aplicativo funciona sem compartilhar.

5. Clique em Start companion para salvar e mantenha o aplicativo aberto com WoW.]],
        [[1. Deixe Companion aberto e digite /apscout on. Teste fora de combate e antes de uma chave.

2. Abra seu anúncio com candidatos ou entre em um grupo e selecione Party.

3. Clique na pequena janela para abrir a sobreposição completa. Se faltar, use Show overlay no menu do ícone na bandeja Windows.

4. O addon mostra um QR brevemente e faz uma captura automática. Confira os nomes e os resultados Warcraft Logs, quando houver logs públicos.

Sem nomes? Confira Screenshots e tente /apscout shotnow. Nomes sem WCL? Use Test WCL; alguns jogadores não têm logs. Atualizações pausam em combate, chaves ativas e chefes de raide.

Concluir guia desativa o lembrete, mas não verifica a instalação: o addon não detecta Companion. Reabra com /apscout setup.]]
    },
    {"Projeto independente de código aberto, não um aplicativo oficial Blizzard.", "Windows necessário. Guia ilustrado disponível no navegador.", "Se Test WCL falhar, confira os dois campos copiados.", "Selecione Screenshots do cliente correto, não Interface ou AddOns.", "Atualize o addon pelo CurseForge:\nhttps://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"})

locales.esES = translated("Español (España)",
    {"ApplicantScout: configuración inicial", "Paso %d de %d", "Idioma", "Enlace de descarga", "Guía ilustrada", "Más tarde", "Ya configurado", "Atrás", "Siguiente", "Finalizar guía", "Selecciona el enlace, pulsa Ctrl+C y pégalo en el navegador fuera de WoW.", "La configuración se abrirá tras la carga, el combate, el jefe o la piedra activa."},
    {"Por qué necesitas Companion para Windows", "Instalar ApplicantScout Companion", "Conectar Warcraft Logs", "Carpeta y opciones de inicio", "Comprobar los primeros resultados"},
    {
        [[ApplicantScout tiene dos partes. El addon recoge candidatos y miembros del grupo/banda. Companion, gratuito para Windows, consulta Warcraft Logs y muestra la tabla junto a WoW. El addon solo no muestra esa tabla.

Ruta: addon -> código QR -> captura WoW -> Companion -> Warcraft Logs -> ventana superpuesta.

Los addons no pueden hacer estas consultas web directamente. El addon muestra brevemente un QR y toma una captura normal. Companion la lee localmente desde Screenshots; la imagen no se envía a Warcraft Logs.

El código de ambas partes está abierto en GitHub. Sin lectura de memoria WoW, inyección de código ni invitaciones automáticas. Tú decides. No necesita tu contraseña Blizzard.]],
        [[1. Selecciona el enlace de descarga, pulsa Ctrl+C y pégalo en el navegador.

2. En la última versión GitHub abre Assets y descarga ApplicantScoutCompanionSetup-*.exe. Es el instalador Windows, no un archivo Excel. Source code y .sha256 no son instaladores.

3. Ejecuta el instalador y abre ApplicantScout Companion desde el menú Inicio. Aparecerá la configuración inicial.

El ZIP portátil permite extraer y ejecutar la aplicación manualmente.

Las versiones actuales no están firmadas; SmartScreen puede indicar un editor desconocido. Usa la versión GitHub indicada y evalúa tu confianza en la fuente. Código abierto y sumas de comprobación no garantizan la identidad del editor.]],
        [[1. Crea una cuenta gratuita Warcraft Logs o inicia sesión. Abre API Clients con el enlace.

2. Selecciona Create Client y usa el nombre ApplicantScout.

3. Pon exactamente http://localhost en Redirect URL. NO marques Public Client. Crea el cliente.

4. Copia Client ID y Client Secret en los campos correspondientes de Companion. Pulsa Test WCL.

Son credenciales API para datos públicos Warcraft Logs, no un inicio de sesión WoW. Mantén Client Secret privado; úsalo solo en Companion, nunca en el chat ni en capturas de soporte.

La guía ilustrada muestra Create Client. Companion también incluye un ejemplo WCL.]],
        [[1. Selecciona Screenshots del cliente que juegas: _retail_\Screenshots, o _ptr_ / _xptr_ para PTR. Si no existe, toma primero una captura normal en WoW.

2. Activa Mythic+ y las dificultades de banda deseadas. El addon opcional RaiderIO añade contexto de mazmorras y bandas.

3. Start and stop with WoW abre Companion con el juego. Un ayudante oculto se inicia al entrar en Windows y espera WoW. Si está bloqueado, usa Enable watcher o Repair watcher. También puedes abrirlo manualmente.

4. Share usage statistics es opcional y empieza desactivado. La aplicación funciona sin compartir.

5. Pulsa Start companion para guardar y deja la aplicación abierta junto a WoW.]],
        [[1. Deja Companion abierto y escribe /apscout on. Comprueba fuera de combate y antes de empezar una piedra.

2. Abre tu anuncio con candidatos o entra en un grupo y selecciona Party.

3. Pulsa la pequeña ventana para abrir la tabla completa. Si falta, usa Show overlay en el menú del icono de la bandeja Windows.

4. El addon muestra un QR brevemente y toma una captura automática. Comprueba los nombres y los resultados Warcraft Logs cuando existan registros públicos.

¿Sin nombres? Comprueba Screenshots y prueba /apscout shotnow. ¿Nombres sin WCL? Usa Test WCL; algunos jugadores no tienen registros. Actualizaciones pausadas en combate, piedras activas y jefes de banda.

Finalizar guía detiene el recordatorio, pero no verifica la instalación: el addon no detecta Companion. Reabre con /apscout setup.]]
    },
    {"Proyecto independiente de código abierto, no una aplicación oficial Blizzard.", "Requiere Windows. Guía ilustrada disponible en el navegador.", "Si falla Test WCL, revisa ambos campos copiados.", "Selecciona Screenshots del cliente correcto, no Interface ni AddOns.", "Actualiza el addon mediante CurseForge:\nhttps://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"})

-- Neutral Spanish instructions use the same UI names in both regional clients.
locales.esMX = {name = "Español (Latinoamérica)", ui = locales.esES.ui, pages = locales.esES.pages}

locales.koKR = translated("한국어",
    {"ApplicantScout: 첫 설정", "%d / %d 단계", "언어", "다운로드 링크", "그림 안내", "나중에", "설정 완료됨", "이전", "다음", "안내 마침", "링크를 선택하고 Ctrl+C를 누른 뒤 WoW 밖의 브라우저에 붙여 넣으세요.", "로딩, 전투, 우두머리 또는 진행 중인 쐐기가 끝나면 설정을 엽니다."},
    {"Windows Companion이 필요한 이유", "ApplicantScout Companion 설치", "Warcraft Logs 연결", "폴더와 시작 옵션 선택", "첫 결과 확인"},
    {
        [[ApplicantScout는 두 부분으로 구성됩니다. 애드온은 파티 찾기 신청자와 파티/공격대 정보를 수집합니다. 무료 Windows Companion은 Warcraft Logs를 조회하고 WoW 옆에 표를 표시합니다. 애드온만으로는 이 표가 나오지 않습니다.

데이터 흐름: 애드온 -> QR 코드 -> WoW 스크린샷 -> Companion -> Warcraft Logs -> 오버레이.

애드온은 이런 웹 요청을 직접 할 수 없습니다. 잠깐 QR 코드를 표시하고 WoW의 일반 스크린샷 기능을 사용합니다. Companion은 Screenshots 폴더에서 로컬로 읽으며, 이미지 자체는 Warcraft Logs에 업로드하지 않습니다.

두 부분의 소스는 GitHub에 공개되어 있습니다. WoW 메모리 읽기, 코드 주입, 자동 초대를 하지 않습니다. 초대는 직접 결정하세요. Blizzard 비밀번호는 필요 없습니다.]],
        [[1. 다운로드 링크를 선택하고 Ctrl+C로 복사한 뒤 브라우저에 붙여 넣으세요.

2. 최신 GitHub 릴리스에서 Assets를 열고 ApplicantScoutCompanionSetup-*.exe를 받으세요. Windows 설치 파일이며 Excel 파일이 아닙니다. Source code나 .sha256은 설치 파일이 아닙니다.

3. 설치 후 Windows 시작 메뉴에서 ApplicantScout Companion을 실행하세요. 첫 설정 창이 열립니다.

설치 대신 portable ZIP을 풀고 직접 실행할 수도 있습니다.

현재 빌드는 서명되지 않아 SmartScreen이 알 수 없는 게시자를 표시할 수 있습니다. 연결된 GitHub 릴리스를 사용하고 출처를 신뢰할지 판단하세요. 공개 소스와 체크섬이 게시자 신원을 보장하지는 않습니다.]],
        [[1. 무료 Warcraft Logs 계정을 만들거나 로그인하고 아래 링크의 API Clients를 여세요.

2. Create Client를 누르고 이름을 ApplicantScout로 지정하세요.

3. Redirect URL은 정확히 http://localhost로 입력하세요. Public Client는 체크하지 마세요. 클라이언트를 생성하세요.

4. Client ID와 Client Secret을 Companion 설정의 해당 칸에 붙여 넣고 Test WCL로 확인하세요.

이것은 공개 Warcraft Logs 데이터용 API 자격 증명이며 WoW 로그인 정보가 아닙니다. Client Secret은 Companion에만 입력하고 채팅이나 지원용 스크린샷에 공개하지 마세요.

그림 안내에서 Create Client 양식을 볼 수 있습니다. Companion 설정에도 WCL 예제가 있습니다.]],
        [[1. 실제 플레이하는 클라이언트의 Screenshots를 선택하세요: _retail_\Screenshots, PTR은 _ptr_ 또는 _xptr_. 폴더가 없다면 WoW에서 일반 스크린샷을 먼저 찍으세요.

2. Mythic+와 원하는 공격대 난이도를 체크하세요. 선택적인 RaiderIO 애드온은 던전과 공격대 정보를 추가합니다.

3. Start and stop with WoW를 체크하면 게임과 함께 실행됩니다. 숨겨진 도우미가 Windows 로그인 때 시작하여 WoW를 기다립니다. 차단되면 Enable watcher 또는 Repair watcher를 사용하세요. 수동 실행도 가능합니다.

4. Share usage statistics는 선택 사항이며 기본적으로 꺼져 있습니다. 통계 공유 없이도 작동합니다.

5. Start companion으로 첫 설정을 저장하고 WoW와 함께 실행해 두세요.]],
        [[1. Companion을 실행한 상태로 WoW에서 /apscout on을 입력하세요. 전투 중이 아니고 쐐기를 시작하기 전에 확인하세요.

2. 신청자가 있는 자신의 파티 모집을 열거나 파티에 가입하고 Companion에서 Party를 선택하세요.

3. 작은 실행 창만 보이면 눌러 전체 오버레이를 여세요. 없으면 Windows 트레이 메뉴의 Show overlay를 사용하세요.

4. 애드온이 QR 코드를 잠깐 표시하고 자동으로 스크린샷을 찍습니다. 플레이어 이름이 같은지, 공개 로그가 있는 경우 Warcraft Logs 결과가 나오는지 확인하세요.

이름이 없으면 Screenshots와 /apscout shotnow를 확인하세요. 이름만 있으면 Test WCL을 사용하세요. 공개 로그가 없는 플레이어도 있습니다. 전투, 진행 중인 쐐기, 공격대 우두머리 중에는 갱신이 멈춥니다.

안내 마침은 알림만 끄며 설치를 확인하지는 않습니다. 애드온은 Companion을 감지할 수 없습니다. 다시 열기: /apscout setup.]]
    },
    {"독립적인 오픈 소스 프로젝트이며 공식 Blizzard 앱이 아닙니다.", "Windows가 필요합니다. 그림 안내는 브라우저에서 볼 수 있습니다.", "Test WCL이 실패하면 복사한 두 칸을 확인하세요.", "올바른 클라이언트의 Screenshots를 선택하세요. Interface나 AddOns가 아닙니다.", "CurseForge에서 애드온을 업데이트하세요:\nhttps://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"})

locales.zhCN = translated("简体中文",
    {"ApplicantScout：首次设置", "第 %d 步，共 %d 步", "语言", "下载链接", "图文指南", "稍后", "已经设置", "上一步", "下一步", "完成指南", "选中链接，按 Ctrl+C，再粘贴到 WoW 外的浏览器中。", "加载、战斗、首领战或正在进行的大秘境结束后将打开设置。"},
    {"为什么需要 Windows Companion", "安装 ApplicantScout Companion", "连接 Warcraft Logs", "选择文件夹和启动选项", "检查首次结果"},
    {
        [[ApplicantScout 有两个部分。插件收集预组队申请者和小队/团队成员信息。免费的 Windows Companion 查询 Warcraft Logs，并在 WoW 旁显示表格。只装插件不会显示此表格。

数据流程：插件 -> 二维码 -> 普通 WoW 截图 -> Companion -> Warcraft Logs -> 悬浮窗口。

插件不能直接执行这些网络查询。它会短暂显示二维码并使用 WoW 的普通截图功能。Companion 从 Screenshots 文件夹在本地读取；截图本身不会上传到 Warcraft Logs。

两个部分的源码都在 GitHub 公开。不读取 WoW 内存、不注入代码、不自动邀请玩家；邀请由你决定。不需要 Blizzard 密码。]],
        [[1. 选中下载链接，按 Ctrl+C 并粘贴到浏览器中。

2. 在 GitHub 最新发布页展开 Assets，下载 ApplicantScoutCompanionSetup-*.exe。这是 Windows 安装程序，不是 Excel 文件。不要选择 Source code 或 .sha256 校验文件。

3. 运行安装程序，然后从 Windows 开始菜单启动 ApplicantScout Companion，进入首次设置。

也可以解压 portable ZIP 后手动运行。

当前版本没有数字签名，SmartScreen 可能显示未知发布者。请使用这里链接的 GitHub 发布页，并自行判断是否信任来源。开源和校验和不保证发布者身份。]],
        [[1. 注册免费 Warcraft Logs 账户或登录，然后通过下方链接打开 API Clients。

2. 点击 Create Client，名称填写 ApplicantScout。

3. Redirect URL 必须填写 http://localhost。不要勾选 Public Client，然后创建客户端。

4. 将生成的 Client ID 和 Client Secret 复制到 Companion 设置的对应栏位，点击 Test WCL 检查连接。

这些是查询公开 Warcraft Logs 数据的 API 凭据，不是 WoW 登录信息。Client Secret 必须保密，只输入 Companion，不要发到聊天或客服截图中。

图文指南包含 Create Client 表单截图，Companion 设置也提供 WCL 示例。]],
        [[1. 选择实际游玩的客户端内的 Screenshots：_retail_\Screenshots，PTR 使用 _ptr_ 或 _xptr_。如果文件夹不存在，先在 WoW 中拍一张普通截图。

2. 勾选 Mythic+ 和需要的团队难度。可选的 RaiderIO 插件可提供地下城和团队副本背景信息。

3. 勾选 Start and stop with WoW 可随游戏启动。隐藏助手在登录 Windows 时运行并等待 WoW；被阻止时使用 Enable watcher 或 Repair watcher，也可手动启动。

4. Share usage statistics 是自愿选项，初始关闭。不分享统计也能使用。

5. 点击 Start companion 保存首次设置，并让程序与 WoW 同时运行。]],
        [[1. 保持 Companion 运行，在 WoW 输入 /apscout on。在非战斗且尚未开始大秘境时测试。

2. 打开有申请者的自己的预组队招募，或加入队伍并在 Companion 选择 Party。

3. 若只有小型启动窗口，点击它打开完整悬浮窗口。若看不到，使用 Windows 托盘菜单的 Show overlay。

4. 插件短暂显示二维码并自动截图。确认玩家名字一致，然后查看有公开日志的 Warcraft Logs 结果。

没有名字？检查 Screenshots 并尝试 /apscout shotnow。有名字但无 WCL？使用 Test WCL；部分玩家没有公开日志。战斗、进行中的大秘境和团队首领战期间暂停更新。

完成指南仅关闭提醒，不验证安装：插件无法检测 Companion。再次打开：/apscout setup。]]
    },
    {"独立开源项目，并非 Blizzard 官方应用。", "需要 Windows。图文指南可在浏览器中查看。", "Test WCL 失败时请检查复制的两个栏位。", "选择正确客户端的 Screenshots，不是 Interface 或 AddOns。", "通过 CurseForge 更新插件：\nhttps://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"})

locales.zhTW = translated("繁體中文",
    {"ApplicantScout：首次設定", "第 %d 步，共 %d 步", "語言", "下載連結", "圖文指南", "稍後", "已經設定", "上一步", "下一步", "完成指南", "選取連結，按 Ctrl+C，再貼到 WoW 外的瀏覽器中。", "載入、戰鬥、首領戰或進行中的傳奇鑰石結束後將開啟設定。"},
    {"為什麼需要 Windows Companion", "安裝 ApplicantScout Companion", "連接 Warcraft Logs", "選擇資料夾與啟動選項", "檢查首次結果"},
    {
        [[ApplicantScout 有兩個部分。插件收集預組隊申請者與隊伍/團隊成員資訊。免費的 Windows Companion 查詢 Warcraft Logs，並在 WoW 旁顯示表格。只裝插件不會顯示此表格。

資料流程：插件 -> QR 碼 -> 一般 WoW 截圖 -> Companion -> Warcraft Logs -> 浮動視窗。

插件不能直接執行這些網路查詢。它短暫顯示 QR 碼並使用 WoW 的一般截圖功能。Companion 在本機從 Screenshots 讀取，圖片本身不會上傳至 Warcraft Logs。

兩個部分的原始碼都在 GitHub 公開。不讀取 WoW 記憶體、不注入程式碼、不自動邀請玩家；邀請由你決定。不需要 Blizzard 密碼。]],
        [[1. 選取下載連結，按 Ctrl+C 並貼到瀏覽器中。

2. 在 GitHub 最新發行頁展開 Assets，下載 ApplicantScoutCompanionSetup-*.exe。這是 Windows 安裝程式，不是 Excel 檔案。不要選 Source code 或 .sha256 校驗檔。

3. 執行安裝程式，再從 Windows 開始功能表啟動 ApplicantScout Companion，進入首次設定。

也可解壓縮 portable ZIP 後手動執行。

目前版本沒有數位簽章，SmartScreen 可能顯示未知發行者。請使用這裡連結的 GitHub 發行頁，並自行判斷是否信任來源。開源與校驗和不保證發行者身分。]],
        [[1. 註冊免費 Warcraft Logs 帳號或登入，再透過下方連結開啟 API Clients。

2. 點選 Create Client，名稱填入 ApplicantScout。

3. Redirect URL 必須填入 http://localhost。不要勾選 Public Client，再建立用戶端。

4. 將產生的 Client ID 與 Client Secret 複製到 Companion 設定的對應欄位，點選 Test WCL 檢查連線。

這些是查詢公開 Warcraft Logs 資料的 API 憑證，不是 WoW 登入資訊。Client Secret 必須保密，只輸入 Companion，不要貼到聊天或客服截圖中。

圖文指南包含 Create Client 表單截圖，Companion 設定也提供 WCL 範例。]],
        [[1. 選擇實際遊玩用戶端內的 Screenshots：_retail_\Screenshots，PTR 使用 _ptr_ 或 _xptr_。若資料夾不存在，先在 WoW 拍一張一般截圖。

2. 勾選 Mythic+ 與需要的團隊難度。選用的 RaiderIO 插件提供地城與團隊副本背景資訊。

3. 勾選 Start and stop with WoW 可隨遊戲啟動。隱藏助手在登入 Windows 時執行並等待 WoW；被阻擋時使用 Enable watcher 或 Repair watcher，也可手動啟動。

4. Share usage statistics 是自願選項，初始關閉。不分享統計也能使用。

5. 點選 Start companion 儲存首次設定，讓程式與 WoW 同時執行。]],
        [[1. 保持 Companion 執行，在 WoW 輸入 /apscout on。在非戰鬥且尚未開始鑰石時測試。

2. 開啟有申請者的自己的預組隊招募，或加入隊伍並在 Companion 選擇 Party。

3. 若只有小型啟動視窗，點選它開啟完整浮動視窗。若看不到，使用 Windows 系統匣選單的 Show overlay。

4. 插件短暫顯示 QR 碼並自動截圖。確認玩家名字一致，再查看有公開紀錄的 Warcraft Logs 結果。

沒有名字？檢查 Screenshots 並嘗試 /apscout shotnow。有名字但無 WCL？使用 Test WCL；有些玩家沒有公開紀錄。戰鬥、進行中的鑰石與團隊首領戰時暫停更新。

完成指南只關閉提醒，不驗證安裝：插件無法偵測 Companion。再次開啟：/apscout setup。]]
    },
    {"獨立開源專案，並非 Blizzard 官方應用程式。", "需要 Windows。圖文指南可在瀏覽器中查看。", "Test WCL 失敗時請檢查複製的兩個欄位。", "選擇正確用戶端的 Screenshots，不是 Interface 或 AddOns。", "透過 CurseForge 更新插件：\nhttps://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"})

locales.deDE = translated("Deutsch",
    {"ApplicantScout: Ersteinrichtung", "Schritt %d von %d", "Sprache", "Download-Link", "Bildanleitung", "Später", "Schon eingerichtet", "Zurück", "Weiter", "Anleitung beenden", "Link markieren, Ctrl+C drücken und außerhalb von WoW im Browser einfügen.", "Die Einrichtung öffnet sich nach Laden, Kampf, Boss oder aktivem Schlüsselstein."},
    {"Warum die Windows-App benötigt wird", "ApplicantScout Companion installieren", "Warcraft Logs verbinden", "Ordner und Startoptionen auswählen", "Erste Ergebnisse prüfen"},
    {
        [[ApplicantScout besteht aus zwei Teilen. Das Addon sammelt Bewerber und Gruppen-/Schlachtzugsmitglieder. Die kostenlose Windows-App Companion ruft Warcraft Logs ab und zeigt die Tabelle neben WoW. Das Addon allein zeigt diese Tabelle nicht.

Datenweg: Addon -> QR-Code -> normaler WoW-Screenshot -> Companion -> Warcraft Logs -> Overlay.

Addons können diese Webanfragen nicht direkt senden. Das Addon zeigt kurz einen QR-Code und erstellt einen WoW-Screenshot. Companion liest ihn lokal aus Screenshots; das Bild wird nicht an Warcraft Logs hochgeladen.

Beide Teile sind quelloffen auf GitHub. Kein Lesen des WoW-Speichers, keine Code-Injektion und keine automatischen Einladungen. Du entscheidest. Kein Blizzard-Passwort erforderlich.]],
        [[1. Download-Link markieren, Ctrl+C drücken und im Browser einfügen.

2. Im neuesten GitHub-Release Assets öffnen und ApplicantScoutCompanionSetup-*.exe herunterladen. Das ist der Windows-Installer, keine Excel-Datei. Source code und .sha256 sind keine Installer.

3. Installer ausführen und ApplicantScout Companion im Windows-Startmenü öffnen. Die Ersteinrichtung erscheint.

Alternativ das portable ZIP entpacken und selbst starten.

Aktuelle Builds sind nicht signiert; SmartScreen kann einen unbekannten Herausgeber melden. Nutze den verlinkten GitHub-Release und prüfe dein Vertrauen in die Quelle. Offener Code und Prüfsummen garantieren keine Herausgeberidentität.]],
        [[1. Ein kostenloses Warcraft-Logs-Konto erstellen oder anmelden. API Clients über den Link öffnen.

2. Create Client wählen und ApplicantScout als Namen eingeben.

3. Redirect URL genau auf http://localhost setzen. Public Client NICHT aktivieren. Client erstellen.

4. Client ID und Client Secret in die entsprechenden Companion-Einstellungen kopieren. Mit Test WCL prüfen.

Dies sind API-Zugangsdaten für öffentliche Warcraft-Logs-Daten, kein WoW-Login. Client Secret nur in Companion eingeben, nie im Chat oder in Support-Screenshots.

Die Bildanleitung zeigt Create Client. Companion bietet ebenfalls ein WCL-Einrichtungsbeispiel.]],
        [[1. Screenshots im gespielten Client wählen: _retail_\Screenshots, für PTR _ptr_ oder _xptr_. Falls der Ordner fehlt, zuerst einen normalen WoW-Screenshot machen.

2. Mythic+ und gewünschte Raid-Schwierigkeiten auswählen. Das optionale RaiderIO-Addon ergänzt Dungeon- und Raid-Kontext.

3. Start and stop with WoW startet Companion mit dem Spiel. Ein versteckter Helfer startet bei der Windows-Anmeldung und wartet auf WoW. Bei Blockierung Enable watcher oder Repair watcher nutzen. Manueller Start ist möglich.

4. Share usage statistics ist freiwillig und anfangs aus. Die App funktioniert ohne Statistikfreigabe.

5. Mit Start companion die Ersteinrichtung speichern und die App neben WoW laufen lassen.]],
        [[1. Companion geöffnet lassen und in WoW /apscout on eingeben. Außerhalb des Kampfes und vor einem Schlüsselstein testen.

2. Eine eigene Gruppensuche mit Bewerbern öffnen oder einer Gruppe beitreten und Party wählen.

3. Auf das kleine Companion-Fenster klicken, um das volle Overlay zu öffnen. Fehlt es, Show overlay im Windows-Traymenü wählen.

4. Das Addon zeigt kurz einen QR-Code und erstellt automatisch einen Screenshot. Die Namen vergleichen, dann Warcraft-Logs-Ergebnisse bei vorhandenen öffentlichen Logs.

Keine Namen? Screenshots prüfen und /apscout shotnow versuchen. Namen ohne WCL? Test WCL nutzen; manche Spieler haben keine Logs. Updates pausieren im Kampf, im aktiven Schlüsselstein und bei Raidbossen.

Anleitung beenden stoppt die Erinnerung, prüft aber keine Installation: Das Addon erkennt Companion nicht. Erneut öffnen: /apscout setup.]]
    },
    {"Unabhängiges Open-Source-Projekt, keine offizielle Blizzard-App.", "Windows erforderlich. Die Bildanleitung ist im Browser verfügbar.", "Bei fehlgeschlagenem Test WCL beide kopierten Felder prüfen.", "Screenshots des richtigen Clients wählen, nicht Interface oder AddOns.", "Addon über CurseForge aktualisieren:\nhttps://www.curseforge.com/wow/addons/applicantscout-lfg-overlay"})

local automatic = {
    enUS = "Auto (WoW)", deDE = "Automatisch (WoW)", esES = "Automático (WoW)",
    esMX = "Automático (WoW)", frFR = "Automatique (WoW)", itIT = "Automatico (WoW)",
    ptBR = "Automático (WoW)", ruRU = "Как в WoW", koKR = "자동 (WoW)",
    zhCN = "自动 (WoW)", zhTW = "自動 (WoW)",
}
for code, text in pairs(automatic) do locales[code].ui.automatic = text end
