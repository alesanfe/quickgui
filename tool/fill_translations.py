#!/usr/bin/env python3
"""Fill missing msgstr entries in the .po files.

- en.po: msgstr = msgid for every missing entry.
- es.po: full Spanish translations for every missing entry.
- other locales: translate the newest msgids only (project norm is a
  sparse translation covering the base UI; full catalogue stays as-is).
"""
import io, os, re, sys

D = os.path.dirname(os.path.abspath(__file__))
TDIR = os.path.join(D, "..", "assets", "translations")

NEW_MSGIDS = [
    'Value', 'Required', 'A frontend for quickemu — discover, download and manage VMs.',
    'Hotplug — {0}', 'Inventory', 'Move / Rename — {0}', 'Plugins', 'QuickGUI',
    'Console — {0}', 'Type text into the machine', 'Live console',
    'Machine is not running', 'The machine is not running — start it to use the console.',
    'Unsupported framebuffer', 'Open external viewer', 'Added {0}',
    'Keyboard shortcuts', 'Show QuickGUI', 'Quit',
    'Cancel multi-select / close dialogs', 'Create a new virtual machine',
    'Filter the machines list', 'Open this shortcuts reference',
    'Refresh the machines list', 'Switch between the six sections',
    'Ctrl+1…6', 'Unsupported file type for drop: {0}',
]

ES = {
    'Download of {0} has failed.': 'La descarga de {0} ha fallado.',
    'Download of {0} has been cancelled.': 'La descarga de {0} se ha cancelado.',
    'You are about to delete {0}. This cannot be undone. Would you like to delete the disk image but keep the configuration, or delete the whole VM?':
        'Está a punto de eliminar {0}. Esta acción no se puede deshacer. ¿Desea eliminar la imagen de disco conservando la configuración, o eliminar la máquina virtual completa?',
    'Launch SSH connection to {0}': 'Iniciar conexión SSH a {0}',
    'Could not write to the working directory. Please check the permissions.':
        'No se pudo escribir en el directorio de trabajo. Compruebe los permisos.',
    'Dependency check': 'Comprobación de dependencias',
    'Could not check for updates. Check your network connection and try again later.':
        'No se pudieron buscar actualizaciones. Compruebe su conexión de red e inténtelo más tarde.',
    'Installed: {0}\nLatest: {1}': 'Instalada: {0}\nÚltima: {1}',
    'Quickemu report': 'Informe de Quickemu',
    'Target folder: {0}': 'Carpeta de destino: {0}',
    'Could not load the OS catalogue. Check that quickget is installed and try again.':
        'No se pudo cargar el catálogo de sistemas operativos. Compruebe que quickget está instalado e inténtelo de nuevo.',
    'Stop {0}': 'Detener {0}',
    'Shut down {0} gracefully, or force it to stop? Forcing discards unsaved changes in the guest.':
        '¿Apagar {0} correctamente o forzar su detención? Forzar descarta los cambios no guardados del invitado.',
    'Force stop': 'Forzar detención',
    'Stale (process exited unexpectedly)': 'Obsoleto (el proceso terminó inesperadamente)',
    'New size (current: {0}, grow only)': 'Nuevo tamaño (actual: {0}, solo aumentar)',
    'Command output': 'Salida del comando',
    'Replace {0}?': '¿Reemplazar {0}?',
    'The file already exists and will be overwritten.': 'El archivo ya existe y se sobrescribirá.',
    'Start the virtual machine': 'Iniciar la máquina virtual',
    'Shut down or stop the virtual machine': 'Apagar o detener la máquina virtual',
    'Not running': 'Detenida',
    'Select a virtual machine': 'Seleccione una máquina virtual',
    'A required port is already in use. Stop the conflicting VM or change the port forwards.':
        'Un puerto necesario ya está en uso. Detenga la VM en conflicto o cambie las redirecciones de puertos.',
    'Choose an operating system or import an existing image to get started.':
        'Elija un sistema operativo o importe una imagen existente para empezar.',
    'Create a virtual machine': 'Crear una máquina virtual',
    'Download of {0} has been canceled.': 'La descarga de {0} se ha cancelado.',
    'Hardware virtualisation (/dev/kvm) is not available; VMs will run slowly.':
        'La virtualización por hardware (/dev/kvm) no está disponible; las VM funcionarán lentamente.',
    'KVM is not accessible. Add your user to the kvm group or check /dev/kvm permissions.':
        'KVM no es accesible. Añada su usuario al grupo kvm o compruebe los permisos de /dev/kvm.',
    'Only {0} is free in the working directory. Large guests may fail to download or run out of disk space.':
        'Solo quedan {0} libres en el directorio de trabajo. Los invitados grandes pueden fallar al descargar o quedarse sin espacio.',
    'Pick an operating system and a version, or drop a disk image anywhere on this page.':
        'Elija un sistema operativo y una versión, o suelte una imagen de disco en cualquier parte de esta página.',
    'The SPICE viewer was not found. Install spicy or pick another display viewer in Settings.':
        'No se encontró el visor SPICE. Instale spicy o elija otro visor en Configuración.',
    'The disk image is missing or corrupted. Verify the image or download it again.':
        'La imagen de disco falta o está dañada. Verifique la imagen o descárguela de nuevo.',
    'The disk is full. Free space in the working directory or move the VMs to a larger disk.':
        'El disco está lleno. Libere espacio en el directorio de trabajo o mueva las VM a un disco mayor.',
    'The file will be moved into a new virtual machine folder inside the working directory.':
        'El archivo se moverá a una nueva carpeta de máquina virtual dentro del directorio de trabajo.',
    'The image will be converted to qcow2, then moved into a new virtual machine folder inside the working directory.':
        'La imagen se convertirá a qcow2 y luego se moverá a una nueva carpeta de máquina virtual dentro del directorio de trabajo.',
    'Version {0} — Powered by Quickemu': 'Versión {0} — Con tecnología de Quickemu',
    'VirtIO drivers / unattended install present': 'Controladores VirtIO / instalación desatendida presentes',
    'macOS {0} requires a CPU with {1} support.': 'macOS {0} requiere una CPU compatible con {1}.',
    'swtpm is not installed. Windows guests need a TPM 2.0 emulator.':
        'swtpm no está instalado. Los invitados Windows necesitan un emulador de TPM 2.0.',
    'swtpm was not found in your PATH. Windows guests require a TPM 2.0 emulator. Please install swtpm and try again.':
        'No se encontró swtpm en su PATH. Los invitados Windows requieren un emulador de TPM 2.0. Instale swtpm e inténtelo de nuevo.',
    'Configuration changed outside Quickgui': 'La configuración cambió fuera de Quickgui',
    'Key': 'Clave',
    'Local copy saved to {0}': 'Copia local guardada en {0}',
    'On disk': 'En disco',
    'Original': 'Original',
    'Overwrite anyway': 'Sobrescribir de todos modos',
    'Reload from disk': 'Recargar desde el disco',
    'Save a copy': 'Guardar una copia',
    'The file {0} was modified by Quickemu, another editor or an external operation since it was opened.':
        'El archivo {0} fue modificado por Quickemu, otro editor o una operación externa desde que se abrió.',
    'Your edit': 'Su edición',
    'Affected: {0}': 'Afectado: {0}',
    'Copy error report': 'Copiar informe de errores',
    'Some changes were applied before the failure.': 'Algunos cambios se aplicaron antes del fallo.',
    'Technical details': 'Detalles técnicos',
    'No activity yet. Downloads and machine ': 'Sin actividad todavía. Las descargas y las ',
    'Type': 'Tipo',
    'Backend compatibility': 'Compatibilidad del backend',
    'Commands without envelope': 'Comandos sin envelope',
    'Last fallback': 'Último fallback',
    'Legacy fallbacks used': 'Fallbacks heredados usados',
    'Structured contract': 'Contrato estructurado',
    'Quickemu': 'Quickemu',
    'Download with quickget': 'Descargar con quickget',
    'ISO, qcow2, vdi, vmdk, vhdx or raw': 'ISO, qcow2, vdi, vmdk, vhdx o raw',
    'Pick an image from the catalogue': 'Elija una imagen del catálogo',
    # new strings
    'Value': 'Valor',
    'Required': 'Obligatorio',
    'A frontend for quickemu — discover, download and manage VMs.':
        'Un frontend para quickemu: descubra, descargue y gestione máquinas virtuales.',
    'Hotplug — {0}': 'Conexión en caliente — {0}',
    'Inventory': 'Inventario',
    'Move / Rename — {0}': 'Mover / Renombrar — {0}',
    'Plugins': 'Plugins',
    'QuickGUI': 'QuickGUI',
    'Console — {0}': 'Consola — {0}',
    'Type text into the machine': 'Escriba texto en la máquina',
    'Live console': 'Consola en vivo',
    'Machine is not running': 'La máquina no está en ejecución',
    'The machine is not running — start it to use the console.':
        'La máquina no está en ejecución — iníciela para usar la consola.',
    'Unsupported framebuffer': 'Framebuffer no soportado',
    'Open external viewer': 'Abrir visor externo',
    'Added {0}': '{0} añadido',
    'Keyboard shortcuts': 'Atajos de teclado',
    'Show QuickGUI': 'Mostrar QuickGUI',
    'Quit': 'Salir',
    'Cancel multi-select / close dialogs': 'Cancelar selección múltiple / cerrar diálogos',
    'Create a new virtual machine': 'Crear una nueva máquina virtual',
    'Filter the machines list': 'Filtrar la lista de máquinas',
    'Open this shortcuts reference': 'Abrir esta referencia de atajos',
    'Refresh the machines list': 'Actualizar la lista de máquinas',
    'Switch between the six sections': 'Cambiar entre las seis secciones',
    'Ctrl+1…6': 'Ctrl+1…6',
    'Unsupported file type for drop: {0}': 'Tipo de archivo no soportado para soltar: {0}',
}

# Translations of NEW_MSGIDS per locale (excluding en/es handled above).
L10N = {
 'de': {'Value':'Wert','Required':'Erforderlich','A frontend for quickemu — discover, download and manage VMs.':'Ein Frontend für quickemu – VMs entdecken, herunterladen und verwalten.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventar','Move / Rename — {0}':'Verschieben / Umbenennen — {0}','Plugins':'Plugins','QuickGUI':'QuickGUI','Console — {0}':'Konsole — {0}','Type text into the machine':'Text in die Maschine eingeben','Live console':'Live-Konsole','Machine is not running':'Die Maschine läuft nicht','The machine is not running — start it to use the console.':'Die Maschine läuft nicht — starten Sie sie, um die Konsole zu verwenden.','Unsupported framebuffer':'Nicht unterstützter Framebuffer','Open external viewer':'Externen Viewer öffnen','Added {0}':'{0} hinzugefügt','Keyboard shortcuts':'Tastenkombinationen','Show QuickGUI':'QuickGUI anzeigen','Quit':'Beenden','Cancel multi-select / close dialogs':'Mehrfachauswahl abbrechen / Dialoge schließen','Create a new virtual machine':'Neue virtuelle Maschine erstellen','Filter the machines list':'Maschinenliste filtern','Open this shortcuts reference':'Diese Tastenkombinationsübersicht öffnen','Refresh the machines list':'Maschinenliste aktualisieren','Switch between the six sections':'Zwischen den sechs Bereichen wechseln','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Nicht unterstützter Dateityp für Drop: {0}'},
 'fr': {'Value':'Valeur','Required':'Obligatoire','A frontend for quickemu — discover, download and manage VMs.':'Une interface pour quickemu — découvrez, téléchargez et gérez vos VM.','Hotplug — {0}':'Connexion à chaud — {0}','Inventory':'Inventaire','Move / Rename — {0}':'Déplacer / Renommer — {0}','Plugins':'Extensions','QuickGUI':'QuickGUI','Console — {0}':'Console — {0}','Type text into the machine':'Saisir du texte dans la machine','Live console':'Console en direct','Machine is not running':"La machine n'est pas en cours d'exécution",'The machine is not running — start it to use the console.':"La machine n'est pas en cours d'exécution — démarrez-la pour utiliser la console.",'Unsupported framebuffer':'Framebuffer non pris en charge','Open external viewer':'Ouvrir la visionneuse externe','Added {0}':'{0} ajouté','Keyboard shortcuts':'Raccourcis clavier','Show QuickGUI':'Afficher QuickGUI','Quit':'Quitter','Cancel multi-select / close dialogs':'Annuler la sélection multiple / fermer les boîtes de dialogue','Create a new virtual machine':'Créer une nouvelle machine virtuelle','Filter the machines list':'Filtrer la liste des machines','Open this shortcuts reference':'Ouvrir cette référence de raccourcis','Refresh the machines list':'Actualiser la liste des machines','Switch between the six sections':'Basculer entre les six sections','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Type de fichier non pris en charge pour le dépôt : {0}'},
 'it': {'Value':'Valore','Required':'Obbligatorio','A frontend for quickemu — discover, download and manage VMs.':'Un frontend per quickemu: scopri, scarica e gestisci le VM.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventario','Move / Rename — {0}':'Sposta / Rinomina — {0}','Plugins':'Plugin','QuickGUI':'QuickGUI','Console — {0}':'Console — {0}','Type text into the machine':'Digita testo nella macchina','Live console':'Console live','Machine is not running':'La macchina non è in esecuzione','The machine is not running — start it to use the console.':'La macchina non è in esecuzione — avviala per usare la console.','Unsupported framebuffer':'Framebuffer non supportato','Open external viewer':'Apri visualizzatore esterno','Added {0}':'{0} aggiunto','Keyboard shortcuts':'Scorciatoie da tastiera','Show QuickGUI':'Mostra QuickGUI','Quit':'Esci','Cancel multi-select / close dialogs':'Annulla selezione multipla / chiudi finestre','Create a new virtual machine':'Crea una nuova macchina virtuale','Filter the machines list':"Filtra l'elenco delle macchine",'Open this shortcuts reference':'Apri questo riferimento delle scorciatoie','Refresh the machines list':"Aggiorna l'elenco delle macchine",'Switch between the six sections':'Passa da una sezione all\u2019altra','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Tipo di file non supportato per il rilascio: {0}'},
 'nl': {'Value':'Waarde','Required':'Verplicht','A frontend for quickemu — discover, download and manage VMs.':"Een frontend voor quickemu — VM's ontdekken, downloaden en beheren.",'Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventaris','Move / Rename — {0}':'Verplaatsen / Hernoemen — {0}','Plugins':'Plug-ins','QuickGUI':'QuickGUI','Console — {0}':'Console — {0}','Type text into the machine':'Typ tekst in de machine','Live console':'Liveconsole','Machine is not running':'De machine draait niet','The machine is not running — start it to use the console.':'De machine draait niet — start hem om de console te gebruiken.','Unsupported framebuffer':'Niet-ondersteunde framebuffer','Open external viewer':'Externe viewer openen','Added {0}':'{0} toegevoegd','Keyboard shortcuts':'Sneltoetsen','Show QuickGUI':'QuickGUI weergeven','Quit':'Afsluiten','Cancel multi-select / close dialogs':'Meervoudige selectie annuleren / dialoogvensters sluiten','Create a new virtual machine':'Nieuwe virtuele machine maken','Filter the machines list':'Machinelijst filteren','Open this shortcuts reference':'Deze sneltoetsreferentie openen','Refresh the machines list':'Machinelijst vernieuwen','Switch between the six sections':'Wisselen tussen de zes secties','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Niet-ondersteund bestandstype voor neerzetten: {0}'},
 'pt_BR': {'Value':'Valor','Required':'Obrigatório','A frontend for quickemu — discover, download and manage VMs.':'Um frontend para quickemu — descubra, baixe e gerencie VMs.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventário','Move / Rename — {0}':'Mover / Renomear — {0}','Plugins':'Plug-ins','QuickGUI':'QuickGUI','Console — {0}':'Console — {0}','Type text into the machine':'Digite texto na máquina','Live console':'Console ao vivo','Machine is not running':'A máquina não está em execução','The machine is not running — start it to use the console.':'A máquina não está em execução — inicie-a para usar o console.','Unsupported framebuffer':'Framebuffer não suportado','Open external viewer':'Abrir visualizador externo','Added {0}':'{0} adicionado','Keyboard shortcuts':'Atalhos de teclado','Show QuickGUI':'Mostrar QuickGUI','Quit':'Sair','Cancel multi-select / close dialogs':'Cancelar seleção múltipla / fechar diálogos','Create a new virtual machine':'Criar nova máquina virtual','Filter the machines list':'Filtrar a lista de máquinas','Open this shortcuts reference':'Abrir esta referência de atalhos','Refresh the machines list':'Atualizar a lista de máquinas','Switch between the six sections':'Alternar entre as seis seções','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Tipo de arquivo não suportado para soltar: {0}'},
 'pt_PT': {'Value':'Valor','Required':'Obrigatório','A frontend for quickemu — discover, download and manage VMs.':'Um frontend para quickemu — descubra, descarregue e gira VMs.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventário','Move / Rename — {0}':'Mover / Renomear — {0}','Plugins':'Plug-ins','QuickGUI':'QuickGUI','Console — {0}':'Consola — {0}','Type text into the machine':'Escreva texto na máquina','Live console':'Consola em direto','Machine is not running':'A máquina não está em execução','The machine is not running — start it to use the console.':'A máquina não está em execução — inicie-a para usar a consola.','Unsupported framebuffer':'Framebuffer não suportado','Open external viewer':'Abrir visualizador externo','Added {0}':'{0} adicionado','Keyboard shortcuts':'Atalhos de teclado','Show QuickGUI':'Mostrar QuickGUI','Quit':'Sair','Cancel multi-select / close dialogs':'Cancelar seleção múltipla / fechar diálogos','Create a new virtual machine':'Criar nova máquina virtual','Filter the machines list':'Filtrar a lista de máquinas','Open this shortcuts reference':'Abrir esta referência de atalhos','Refresh the machines list':'Atualizar a lista de máquinas','Switch between the six sections':'Alternar entre as seis secções','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Tipo de ficheiro não suportado para largar: {0}'},
 'sv': {'Value':'Värde','Required':'Obligatoriskt','A frontend for quickemu — discover, download and manage VMs.':'Ett gränssnitt för quickemu – upptäck, ladda ner och hantera virtuella maskiner.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventarie','Move / Rename — {0}':'Flytta / Byt namn — {0}','Plugins':'Insticksmoduler','QuickGUI':'QuickGUI','Console — {0}':'Konsol — {0}','Type text into the machine':'Skriv text i maskinen','Live console':'Livekonsol','Machine is not running':'Maskinen körs inte','The machine is not running — start it to use the console.':'Maskinen körs inte — starta den för att använda konsolen.','Unsupported framebuffer':'Framebuffer som inte stöds','Open external viewer':'Öppna extern visare','Added {0}':'{0} tillagd','Keyboard shortcuts':'Kortkommandon','Show QuickGUI':'Visa QuickGUI','Quit':'Avsluta','Cancel multi-select / close dialogs':'Avbryt flerval / stäng dialogrutor','Create a new virtual machine':'Skapa en ny virtuell maskin','Filter the machines list':'Filtrera maskinlistan','Open this shortcuts reference':'Öppna denna kortkommandoreferens','Refresh the machines list':'Uppdatera maskinlistan','Switch between the six sections':'Växla mellan de sex sektionerna','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Filtypen stöds inte för släpp: {0}'},
 'no': {'Value':'Verdi','Required':'Obligatorisk','A frontend for quickemu — discover, download and manage VMs.':'Et grensesnitt for quickemu – oppdag, last ned og administrer VM-er.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventar','Move / Rename — {0}':'Flytt / Gi nytt navn — {0}','Plugins':'Utvidelser','QuickGUI':'QuickGUI','Console — {0}':'Konsoll — {0}','Type text into the machine':'Skriv tekst i maskinen','Live console':'Live-konsoll','Machine is not running':'Maskinen kjører ikke','The machine is not running — start it to use the console.':'Maskinen kjører ikke — start den for å bruke konsollen.','Unsupported framebuffer':'Framebuffer støttes ikke','Open external viewer':'Åpne ekstern visning','Added {0}':'{0} lagt til','Keyboard shortcuts':'Hurtigtaster','Show QuickGUI':'Vis QuickGUI','Quit':'Avslutt','Cancel multi-select / close dialogs':'Avbryt flervalg / lukk dialoger','Create a new virtual machine':'Opprett en ny virtuell maskin','Filter the machines list':'Filtrer maskinlisten','Open this shortcuts reference':'Åpne denne hurtigtastreferansen','Refresh the machines list':'Oppdater maskinlisten','Switch between the six sections':'Bytt mellom de seks seksjonene','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Filtypen støttes ikke for slipp: {0}'},
 'ru': {'Value':'Значение','Required':'Обязательно','A frontend for quickemu — discover, download and manage VMs.':'Интерфейс для quickemu — находите, скачивайте и управляйте виртуальными машинами.','Hotplug — {0}':'Горячее подключение — {0}','Inventory':'Инвентарь','Move / Rename — {0}':'Переместить / Переименовать — {0}','Plugins':'Плагины','QuickGUI':'QuickGUI','Console — {0}':'Консоль — {0}','Type text into the machine':'Введите текст в машину','Live console':'Живая консоль','Machine is not running':'Машина не запущена','The machine is not running — start it to use the console.':'Машина не запущена — запустите её, чтобы использовать консоль.','Unsupported framebuffer':'Неподдерживаемый кадровый буфер','Open external viewer':'Открыть внешнюю программу просмотра','Added {0}':'Добавлено: {0}','Keyboard shortcuts':'Сочетания клавиш','Show QuickGUI':'Показать QuickGUI','Quit':'Выход','Cancel multi-select / close dialogs':'Отменить множественный выбор / закрыть диалоги','Create a new virtual machine':'Создать новую виртуальную машину','Filter the machines list':'Отфильтровать список машин','Open this shortcuts reference':'Открыть справочник сочетаний клавиш','Refresh the machines list':'Обновить список машин','Switch between the six sections':'Переключение между шестью разделами','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Неподдерживаемый тип файла для перетаскивания: {0}'},
 'cs_CZ': {'Value':'Hodnota','Required':'Povinné','A frontend for quickemu — discover, download and manage VMs.':'Rozhraní pro quickemu — objevujte, stahujte a spravujte virtuální stroje.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventář','Move / Rename — {0}':'Přesunout / Přejmenovat — {0}','Plugins':'Zásuvné moduly','QuickGUI':'QuickGUI','Console — {0}':'Konzole — {0}','Type text into the machine':'Zadejte text do stroje','Live console':'Živá konzole','Machine is not running':'Stroj neběží','The machine is not running — start it to use the console.':'Stroj neběží — spusťte ho, abyste mohli používat konzoli.','Unsupported framebuffer':'Nepodporovaný framebuffer','Open external viewer':'Otevřít externí prohlížeč','Added {0}':'Přidáno {0}','Keyboard shortcuts':'Klávesové zkratky','Show QuickGUI':'Zobrazit QuickGUI','Quit':'Ukončit','Cancel multi-select / close dialogs':'Zrušit výběr více položek / zavřít dialogy','Create a new virtual machine':'Vytvořit nový virtuální stroj','Filter the machines list':'Filtrovat seznam strojů','Open this shortcuts reference':'Otevřít tuto referenci zkratek','Refresh the machines list':'Obnovit seznam strojů','Switch between the six sections':'Přepínat mezi šesti sekcemi','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Nepodporovaný typ souboru pro přetažení: {0}'},
 'tr': {'Value':'Değer','Required':'Gerekli','A frontend for quickemu — discover, download and manage VMs.':"quickemu için bir arayüz — VM'leri keşfedin, indirin ve yönetin.",'Hotplug — {0}':'Hotplug — {0}','Inventory':'Envanter','Move / Rename — {0}':'Taşı / Yeniden adlandır — {0}','Plugins':'Eklentiler','QuickGUI':'QuickGUI','Console — {0}':'Konsol — {0}','Type text into the machine':'Makineye metin yazın','Live console':'Canlı konsol','Machine is not running':'Makine çalışmıyor','The machine is not running — start it to use the console.':'Makine çalışmıyor — konsolu kullanmak için başlatın.','Unsupported framebuffer':'Desteklenmeyen çerçeve arabelleği','Open external viewer':'Harici görüntüleyiciyi aç','Added {0}':'{0} eklendi','Keyboard shortcuts':'Klavye kısayolları','Show QuickGUI':"QuickGUI'yi göster",'Quit':'Çık','Cancel multi-select / close dialogs':'Çoklu seçimi iptal et / iletişim kutularını kapat','Create a new virtual machine':'Yeni sanal makine oluştur','Filter the machines list':'Makine listesini filtrele','Open this shortcuts reference':'Bu kısayol referansını aç','Refresh the machines list':'Makine listesini yenile','Switch between the six sections':'Altı bölüm arasında geçiş yap','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Bırakma için desteklenmeyen dosya türü: {0}'},
 'ja': {'Value':'値','Required':'必須','A frontend for quickemu — discover, download and manage VMs.':'quickemu のフロントエンド — VM を探してダウンロードし、管理します。','Hotplug — {0}':'ホットプラグ — {0}','Inventory':'インベントリ','Move / Rename — {0}':'移動 / 名前変更 — {0}','Plugins':'プラグイン','QuickGUI':'QuickGUI','Console — {0}':'コンソール — {0}','Type text into the machine':'マシンにテキストを入力','Live console':'ライブコンソール','Machine is not running':'マシンは実行されていません','The machine is not running — start it to use the console.':'マシンが実行されていません — コンソールを使うには起動してください。','Unsupported framebuffer':'サポートされていないフレームバッファ','Open external viewer':'外部ビューアを開く','Added {0}':'{0} を追加しました','Keyboard shortcuts':'キーボードショートカット','Show QuickGUI':'QuickGUI を表示','Quit':'終了','Cancel multi-select / close dialogs':'複数選択をキャンセル / ダイアログを閉じる','Create a new virtual machine':'新しい仮想マシンを作成','Filter the machines list':'マシンリストをフィルター','Open this shortcuts reference':'このショートカット一覧を開く','Refresh the machines list':'マシンリストを更新','Switch between the six sections':'6 つのセクションを切り替える','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'ドロップできないファイル形式です: {0}'},
 'id': {'Value':'Nilai','Required':'Wajib','A frontend for quickemu — discover, download and manage VMs.':'Frontend untuk quickemu — temukan, unduh, dan kelola VM.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventaris','Move / Rename — {0}':'Pindahkan / Ganti nama — {0}','Plugins':'Plugin','QuickGUI':'QuickGUI','Console — {0}':'Konsol — {0}','Type text into the machine':'Ketik teks ke dalam mesin','Live console':'Konsol langsung','Machine is not running':'Mesin tidak berjalan','The machine is not running — start it to use the console.':'Mesin tidak berjalan — jalankan untuk menggunakan konsol.','Unsupported framebuffer':'Framebuffer tidak didukung','Open external viewer':'Buka penampil eksternal','Added {0}':'{0} ditambahkan','Keyboard shortcuts':'Pintasan keyboard','Show QuickGUI':'Tampilkan QuickGUI','Quit':'Keluar','Cancel multi-select / close dialogs':'Batalkan multi-pilih / tutup dialog','Create a new virtual machine':'Buat mesin virtual baru','Filter the machines list':'Filter daftar mesin','Open this shortcuts reference':'Buka referensi pintasan ini','Refresh the machines list':'Muat ulang daftar mesin','Switch between the six sections':'Beralih di antara enam bagian','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Jenis file tidak didukung untuk dilepas: {0}'},
 'hu': {'Value':'Érték','Required':'Kötelező','A frontend for quickemu — discover, download and manage VMs.':'Felület a quickemuhoz – fedezze fel, töltse le és kezelje a virtuális gépeket.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Leltár','Move / Rename — {0}':'Áthelyezés / Átnevezés — {0}','Plugins':'Beépülő modulok','QuickGUI':'QuickGUI','Console — {0}':'Konzol — {0}','Type text into the machine':'Írjon szöveget a gépbe','Live console':'Élő konzol','Machine is not running':'A gép nem fut','The machine is not running — start it to use the console.':'A gép nem fut — indítsa el a konzol használatához.','Unsupported framebuffer':'Nem támogatott framebuffer','Open external viewer':'Külső megjelenítő megnyitása','Added {0}':'{0} hozzáadva','Keyboard shortcuts':'Billentyűparancsok','Show QuickGUI':'QuickGUI megjelenítése','Quit':'Kilépés','Cancel multi-select / close dialogs':'Többszörös kijelölés törlése / párbeszédablakok bezárása','Create a new virtual machine':'Új virtuális gép létrehozása','Filter the machines list':'Géplista szűrése','Open this shortcuts reference':'A parancsikon-referencia megnyitása','Refresh the machines list':'Géplista frissítése','Switch between the six sections':'Váltás a hat szakasz között','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Nem támogatott fájltípus a dobáshoz: {0}'},
 'ka': {'Value':'მნიშვნელობა','Required':'აუცილებელია','A frontend for quickemu — discover, download and manage VMs.':'ინტერფეისი quickemu-სთვის — აღმოაჩინეთ, ჩამოტვირთეთ და მართეთ VM-ები.','Hotplug — {0}':'Hotplug — {0}','Inventory':'ინვენტარი','Move / Rename — {0}':'გადატანა / სახელის შეცვლა — {0}','Plugins':'პლაგინები','QuickGUI':'QuickGUI','Console — {0}':'კონსოლი — {0}','Type text into the machine':'ჩაწერეთ ტექსტი მანქანაში','Live console':'ცოცხალი კონსოლი','Machine is not running':'მანქანა არ მუშაობს','The machine is not running — start it to use the console.':'მანქანა არ მუშაობს — გაუშვით კონსოლის გამოსაყენებლად.','Unsupported framebuffer':'მხარდაუჭერელი კადრების ბუფერი','Open external viewer':'გარე პროგრამის გახსნა','Added {0}':'{0} დაემატა','Keyboard shortcuts':'კლავიატურის მალსახმობები','Show QuickGUI':'QuickGUI-ის ჩვენება','Quit':'გამოსვლა','Cancel multi-select / close dialogs':'მრავალჯერადი მონიშვნის გაუქმება / დიალოგების დახურვა','Create a new virtual machine':'ახალი ვირტუალური მანქანის შექმნა','Filter the machines list':'მანქანების სიის გაფილტვრა','Open this shortcuts reference':'მალსახმობების სახელმძღვანელოს გახსნა','Refresh the machines list':'მანქანების სიის განახლება','Switch between the six sections':'ექვს განყოფილებას შორის გადართვა','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'ფაილის მხარდაუჭერელი ტიპი ჩამოსაშვებად: {0}'},
 'gd': {'Value':'Luach','Required':'Riatanach','A frontend for quickemu — discover, download and manage VMs.':'Frontend airson quickemu — lorg, luchdaich sìos agus stiùir VMan.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventaraidh','Move / Rename — {0}':'Gluais / Ath-ainmich — {0}','Plugins':'Plùigidean','QuickGUI':'QuickGUI','Console — {0}':'Consol — {0}','Type text into the machine':'Sgrìobh teacsa a-steach dhan inneal','Live console':'Consol beò','Machine is not running':"Chan eil an inneal a' ruith",'The machine is not running — start it to use the console.':"Chan eil an inneal a' ruith — tòisich e airson a' chonsol a chleachdadh.",'Unsupported framebuffer':'Frèam-buffer gun taic','Open external viewer':'Fosgail an sealladair a-muigh','Added {0}':'{0} air a chur ris','Keyboard shortcuts':'Ath-ghoireidean meur-chlàr','Show QuickGUI':'Seall QuickGUI','Quit':'Fàg','Cancel multi-select / close dialogs':'Cuir taghadh iomadach dheth / dùin còmhragan','Create a new virtual machine':'Cruthaich inneal brìgheil ùr','Filter the machines list':'Criathraich liosta nan innealan','Open this shortcuts reference':'Fosgail an iomradh ath-ghoireidean seo','Refresh the machines list':'Ùraich liosta nan innealan','Switch between the six sections':'Gluais eadar na sia earrannan','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Seòrsa faidhle gun taic airson leigeil sìos: {0}'},
 'cy': {'Value':'Gwerth','Required':'Gofynnol','A frontend for quickemu — discover, download and manage VMs.':'Pen blaen ar gyfer quickemu — darganfyddwch, lawrlwythwch a rheolwch VMau.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Rhestr','Move / Rename — {0}':'Symud / Ailenwi — {0}','Plugins':'Ategion','QuickGUI':'QuickGUI','Console — {0}':'Consol — {0}','Type text into the machine':"Teipiwch destun i'r peiriant",'Live console':'Consol fyw','Machine is not running':"Nid yw'r peiriant yn rhedeg",'The machine is not running — start it to use the console.':"Nid yw'r peiriant yn rhedeg — dechreuwch ef i ddefnyddio'r consol.",'Unsupported framebuffer':'Ffrâmbyffer heb ei gynnal','Open external viewer':'Agorwch y golwydd allanol','Added {0}':'Ychwanegwyd {0}','Keyboard shortcuts':'Llwybrau byr bysellfwrdd','Show QuickGUI':'Dangos QuickGUI','Quit':'Gadael','Cancel multi-select / close dialogs':'Canslo aml-ddewis / cau deialogau','Create a new virtual machine':'Creu peiriant rhithwir newydd','Filter the machines list':"Hidlo'r rhestr o beiriannau",'Open this shortcuts reference':'Agorwch y cyfeirnod llwybrau byr hwn','Refresh the machines list':'Adnewyddwch y rhestr o beiriannau','Switch between the six sections':'Newid rhwng y chwe rhan','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Math o ffeil heb gefnogaeth ar gyfer gollwng: {0}'},
 'oc': {'Value':'Valor','Required':'Obligatòri','A frontend for quickemu — discover, download and manage VMs.':'Una interfàcia per quickemu — descobrissètz, telecargatz e gerissètz las MV.','Hotplug — {0}':'Hotplug — {0}','Inventory':'Inventari','Move / Rename — {0}':'Desplaçar / Renomenar — {0}','Plugins':'Plugins','QuickGUI':'QuickGUI','Console — {0}':'Consòla — {0}','Type text into the machine':'Picatz de tèxte dins la maquina','Live console':'Consòla en dirècte','Machine is not running':'La maquina es pas en cors d\u2019execucion','The machine is not running — start it to use the console.':'La maquina es pas en cors d\u2019execucion — aviatz-la per utilizar la consòla.','Unsupported framebuffer':'Tampon de trama pas pres en carga','Open external viewer':'Dobrir lo visualizador extèrne','Added {0}':'{0} ajustat','Keyboard shortcuts':'Acorchis de clavièr','Show QuickGUI':'Afichar QuickGUI','Quit':'Quitaar','Cancel multi-select / close dialogs':'Anullar la seleccion multipla / tancar las bóstias de dialòg','Create a new virtual machine':'Crear una maquina virtuala novèla','Filter the machines list':'Filtrar la lista de las maquinas','Open this shortcuts reference':'Dobrir aquesta referéncia d\u2019acorchis','Refresh the machines list':'Actualizar la lista de las maquinas','Switch between the six sections':'Bascular entre las sièis seccions','Ctrl+1…6':'Ctrl+1…6','Unsupported file type for drop: {0}':'Tipe de fichièr pas pres en carga per depausar : {0}'},
}

def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')

def parse_blocks(lines):
    """Yield (start_idx, msgid_str, msgstr_idx_or_None) per entry."""
    i = 0
    n = len(lines)
    while i < n:
        l = lines[i]
        if l.startswith('msgid '):
            start = i
            msgid = l[6:].strip()
            j = i + 1
            # continuation lines of the msgid
            while j < n and lines[j].startswith('"'):
                msgid += lines[j].strip()
                j += 1
            # find msgstr within next few lines
            k = j
            while k < n and not lines[k].startswith('msgstr') and not lines[k].startswith('msgid') and lines[k].strip() != '':
                k += 1
            msgstr_idx = k if k < n and lines[k].startswith('msgstr') else None
            # unquote
            try:
                mid = eval(msgid)
            except Exception:
                mid = msgid.strip('"')
            yield start, mid, msgstr_idx
            i = j
        else:
            i += 1

def fill(path, table):
    lines = open(path, encoding='utf-8').read().splitlines()
    msgstrs_filled = set()
    for start, mid, midx in parse_blocks(lines):
        if mid in table and midx is not None:
            if lines[midx].strip() == 'msgstr ""':
                lines[midx] = 'msgstr "%s"' % esc(table[mid])
                msgstrs_filled.add(mid)
    # append entries entirely absent
    appended = 0
    for mid in table:
        if mid in msgstrs_filled:
            continue
        present = any(m == mid for _, m, _ in parse_blocks(lines))
        if not present:
            lines.append('')
            lines.append('msgid "%s"' % esc(mid))
            lines.append('msgstr "%s"' % esc(table[mid]))
            appended += 1
    open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
    return len(msgstrs_filled), appended

def main():
    for fn in sorted(os.listdir(TDIR)):
        if not fn.endswith('.po'):
            continue
        loc = fn[:-3]
        path = os.path.join(TDIR, fn)
        if loc == 'en':
            # en msgstr = msgid, for the NEW set only (rest is project norm)
            table = {m: m for m in NEW_MSGIDS}
        elif loc == 'es':
            table = ES
        else:
            table = L10N.get(loc, {})
            if not table:
                print('skip', fn); continue
        f, a = fill(path, table)
        print('%s: filled %d in-place, appended %d' % (fn, f, a))

if __name__ == '__main__':
    main()
