import 'dart:io';

/// Extracts `context.t('...')` msgids from lib/, appends missing ones to
/// quickgui.pot (empty msgstr), en.po (msgstr = msgid) and es.po (Spanish
/// translation when known). Run: `dart run tool/update_localizations.dart`.
void main() {
  final used = <String>{};
  final re = RegExp(r"""\.t\(\s*'((?:[^'\\]|\\.)*)'""");
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    for (final m in re.allMatches(entity.readAsStringSync())) {
      used.add(_unescapeDart(m.group(1)!));
    }
  }

  final potFile = File('assets/translations/quickgui.pot');
  final potIds = _msgids(potFile.readAsStringSync());
  final missing = used.where((s) => !potIds.contains(s)).toList()..sort();

  if (missing.isEmpty) {
    stdout.writeln('All ${used.length} msgids already in quickgui.pot');
  } else {
    _append(potFile, missing.map((id) => (id, '')).toList());
    stdout.writeln('Appended ${missing.length} msgids to quickgui.pot');
  }

  for (final locale in ['en', 'es']) {
    final file = File('assets/translations/$locale.po');
    final ids = _msgids(file.readAsStringSync());
    final absent = used.where((s) => !ids.contains(s)).toList()..sort();
    _append(
      file,
      absent.map((id) => (id, locale == 'en' ? id : (_es[id] ?? ''))).toList(),
    );
    stdout.writeln('$locale.po: appended ${absent.length} entries');
  }
}

String _unescapeDart(String s) => s
    .replaceAll(r"\'", "'")
    .replaceAll(r'\\', r'\')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\t', '\t')
    .replaceAll(r'\$', r'$')
    .replaceAll(r'\"', '"');

String _escapePo(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll('\n', r'\n')
    .replaceAll('\t', r'\t');

Set<String> _msgids(String content) => RegExp(
  r'^msgid "(.*)"$',
  multiLine: true,
).allMatches(content).map((m) => _unescapePo(m.group(1)!)).toSet();

String _unescapePo(String s) => s
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\t', '\t')
    .replaceAll(r'\"', '"')
    .replaceAll(r'\\', r'\');

void _append(File file, List<(String, String)> entries) {
  if (entries.isEmpty) return;
  final sink = file.openWrite(mode: FileMode.append);
  for (final (id, str) in entries) {
    sink.writeln('\nmsgid "${_escapePo(id)}"\nmsgstr "${_escapePo(str)}"');
  }
  sink.close();
}

/// Spanish translations for msgids introduced by the redesign. Missing
/// entries fall back to an empty msgstr (English).
const _es = <String, String>{
  'Home': 'Inicio',
  'Machines': 'Máquinas',
  'Create': 'Crear',
  'Activity': 'Actividad',
  'Diagnostics': 'Diagnóstico',
  'Settings': 'Ajustes',
  'Welcome to Quickgui': 'Bienvenido a Quickgui',
  'Create, run and manage your virtual machines.':
      'Crea, ejecuta y gestiona tus máquinas virtuales.',
  'Create a machine': 'Crear una máquina',
  'Create your first machine': 'Crea tu primera máquina',
  'Import a disk image': 'Importar una imagen de disco',
  'Running': 'En ejecución',
  'Warnings': 'Advertencias',
  'Free disk space': 'Espacio libre en disco',
  'Backend status': 'Estado del backend',
  'Quickemu is available': 'Quickemu está disponible',
  'Quickemu is unavailable. Open diagnostics for installation help.':
      'Quickemu no está disponible. Abre Diagnóstico para obtener ayuda.',
  'Could not check Quickemu': 'No se pudo comprobar Quickemu',
  'Checking…': 'Comprobando…',
  'Could not load machines': 'No se pudieron cargar las máquinas',
  'No virtual machines yet': 'Todavía no hay máquinas virtuales',
  'Recent activity': 'Actividad reciente',
  'View all': 'Ver todo',
  'No activity yet. Downloads and machine operations will show up here.':
      'Sin actividad todavía. Las descargas y operaciones aparecerán aquí.',
  'Open details': 'Abrir detalles',
  'Retry': 'Reintentar',
  'Refresh': 'Actualizar',
  'All': 'Todas',
  'Stopped': 'Detenidas',
  'Paused': 'Pausadas',
  'New': 'Nuevas',
  'Favourites': 'Favoritas',
  'Favourite': 'Favorita',
  'Select multiple': 'Seleccionar varias',
  'Select all': 'Seleccionar todas',
  '{0} selected': '{0} seleccionadas',
  'Switch view': 'Cambiar vista',
  'Edit tags': 'Editar etiquetas',
  'Comma-separated tags': 'Etiquetas separadas por comas',
  'Use group:name to organise a collection':
      'Usa grupo:nombre para organizar colecciones',
  'Review batch operation': 'Revisar operación por lotes',
  'Action: {0}': 'Acción: {0}',
  'Continue': 'Continuar',
  'Batch operation completed': 'Operación por lotes completada',
  'Some machines failed: {0}': 'Algunas máquinas fallaron: {0}',
  'No machines match these filters':
      'Ninguna máquina coincide con estos filtros',
  'Download an operating system or import a disk image to create your first machine.': 'Descarga un sistema operativo o importa una imagen de disco para crear tu primera máquina.',
  'Last refreshed: {0}': 'Última actualización: {0}',
  'Configure': 'Configurar',
  'Lifecycle': 'Ciclo de vida',
  'Maintenance': 'Mantenimiento',
  'In progress': 'En curso',
  'History': 'Historial',
  'Clear history': 'Limpiar historial',
  'Completed': 'Completada',
  'Failed': 'Fallida',
  'Cancelled': 'Cancelada',
  'Interrupted': 'Interrumpida',
  'Cancelling': 'Cancelando',
  'Copy report': 'Copiar informe',
  'Close': 'Cerrar',
  'Download': 'Descargar',
  'Start': 'Iniciar',
  'Stop': 'Detener',
  'Clone': 'Clonar',
  'Export': 'Exportar',
  'Verify image': 'Verificar imagen',
  'Resize disk': 'Redimensionar disco',
  'Snapshots': 'Instantáneas',
  'Delete': 'Eliminar',
  'Import': 'Importar',
  'Convert': 'Convertir',
  'Command': 'Comando',
  'Overview': 'Resumen',
  'Console': 'Consola',
  'Hardware': 'Hardware',
  'Disks': 'Discos',
  'Network': 'Red',
  'Logs': 'Registros',
  'Back': 'Atrás',
  'VM settings': 'Ajustes de la VM',
  'Confirm machine action': 'Confirmar acción de máquina',
  'This action can discard unsaved guest state. Continue?': 'Esta acción puede descartar cambios no guardados del invitado. ¿Continuar?',
  'Resume': 'Reanudar',
  'Pause': 'Pausar',
  'Reset': 'Reiniciar',
  'Screenshot': 'Captura de pantalla',
  'Send Ctrl+Alt+Del': 'Enviar Ctrl+Alt+Supr',
  'Shut down': 'Apagar',
  'Connect to your machine': 'Conectar a tu máquina',
  'Quickgui manages the connection here and opens the native viewer. A SPICE or VNC display is not embedded in this build.': 'Quickgui gestiona la conexión aquí y abre el visor nativo. Esta compilación no incluye una pantalla SPICE ni VNC integrada.',
  'Connect / reconnect': 'Conectar / reconectar',
  'Connect with SSH': 'Conectar con SSH',
  'Refresh ports': 'Actualizar puertos',
  'Open viewer in full screen': 'Abrir visor a pantalla completa',
  'The guest has not published a connection port. Start the machine and wait until it is ready, then retry.': 'El invitado aún no ha publicado un puerto de conexión. Inicia la máquina, espera a que esté lista y reintenta.',
  'The forwarded port is not serving SSH yet. Wait for guest startup and check the guest SSH service.': 'El puerto redirigido aún no sirve SSH. Espera al arranque del invitado y comprueba el servicio SSH.',
  'No terminal emulator found': 'No se encontró un emulador de terminal',
  'The selected SPICE viewer is unavailable. Install spicy or remote-viewer and choose it in Settings.': 'El visor SPICE seleccionado no está disponible. Instala spicy o remote-viewer y elígelo en Ajustes.',
  'External viewer opened. Display resize, clipboard and guest integration are provided by the viewer and guest tools.': 'Visor externo abierto. El redimensionado, el portapapeles y la integración los aportan el visor y las herramientas del invitado.',
  'The SPICE port is closed. The machine may still be starting or may have stopped. Refresh the status and retry.': 'El puerto SPICE está cerrado. La máquina puede estar arrancando o haberse detenido. Actualiza el estado y reintenta.',
  'Connection failed: {0}': 'La conexión falló: {0}',
  'Serial and VNC access': 'Acceso serie y VNC',
  'Serial sockets and VNC addresses can be configured in Advanced settings. No terminal or VNC client is embedded; do not expose these ports to untrusted networks.': 'Los sockets serie y las direcciones VNC se configuran en Ajustes avanzados. No hay terminal ni cliente VNC integrados; no expongas estos puertos a redes no fiables.',
  'Storage': 'Almacenamiento',
  'No disk configured': 'No hay disco configurado',
  'Image file size: {0}. Virtual capacity is configured separately.': 'Tamaño del archivo de imagen: {0}. La capacidad virtual se configura aparte.',
  'The disk has not been created yet or is unavailable.':
      'El disco aún no se ha creado o no está disponible.',
  'Expand disk': 'Expandir disco',
  'Compact disk': 'Compactar disco',
  'Check VM': 'Comprobar VM',
  'Export / full backup': 'Exportar / copia completa',
  'Open VM folder': 'Abrir carpeta de la VM',
  'Disk maintenance and a consistent full backup require a stopped machine. Snapshots are not independent backups.': 'El mantenimiento de disco y una copia completa consistente requieren la máquina detenida. Las instantáneas no son copias de seguridad independientes.',
  'New capacity (for example 128G)': 'Nueva capacidad (por ejemplo 128G)',
  'Use a value larger than the existing capacity. Back up important data first.': 'Usa un valor mayor que la capacidad actual. Haz copia de los datos importantes primero.',
  'Replace existing archive?': '¿Reemplazar el archivo existente?',
  'Replace': 'Reemplazar',
  'Search logs': 'Buscar en registros',
  'No activity recorded for this machine.':
      'No hay actividad registrada para esta máquina.',
  'Virtual machine not found: {0}': 'Máquina virtual no encontrada: {0}',
  'Configure storage and removable media':
      'Configurar almacenamiento y medios extraíbles',
  'Attach ISO and recovery images in Hardware → Boot. Additional disk topologies depend on the installed Quickemu version.': 'Conecta imágenes ISO y de recuperación en Hardware → Arranque. Las topologías de disco adicionales dependen de la versión de Quickemu instalada.',
  'Changes take effect at the next start':
      'Los cambios se aplican en el próximo arranque',
  'Stop the machine before changing disks, firmware or network configuration.':
      'Detén la máquina antes de cambiar discos, firmware o red.',
  'Advanced': 'Avanzado',
  'Advanced (other keys)': 'Avanzado (otras claves)',
  'Show all options, including ones not covered by the basic editor':
      'Mostrar todas las opciones, incluidas las que el editor básico no cubre',
  'Edit raw configuration': 'Editar configuración en bruto',
  'Configuration saved': 'Configuración guardada',
  'Could not save configuration: {0}':
      'No se pudo guardar la configuración: {0}',
  'Unable to load configuration': 'No se pudo cargar la configuración',
  'Memory': 'Memoria',
  'CPU cores': 'Núcleos de CPU',
  'Virtual disk capacity': 'Capacidad del disco virtual',
  'Firmware': 'Firmware',
  'Guest OS': 'SO invitado',
  'Display': 'Pantalla',
  'Display viewer': 'Visor de pantalla',
  'Audio': 'Audio',
  'Network mode or bridge interface': 'Modo de red o interfaz bridge',
  'Legacy bridge interface': 'Interfaz bridge heredada',
  'MAC address': 'Dirección MAC',
  'Forwarded ports (host:guest)': 'Puertos redirigidos (anfitrión:invitado)',
  'Shared host folder': 'Carpeta compartida del anfitrión',
  'USB devices (vendor:product)': 'Dispositivos USB (vendor:product)',
  'Installation ISO': 'ISO de instalación',
  'Recovery image': 'Imagen de recuperación',
  'Additional ISO': 'ISO adicional',
  'Floppy image': 'Imagen de disquete',
  'TPM 2.0': 'TPM 2.0',
  'Secure Boot': 'Arranque seguro',
  'Boot': 'Arranque',
  'Display & sound': 'Pantalla y sonido',
  'Sharing & devices': 'Compartición y dispositivos',
  'Empty = user NAT. restrict = isolated user network. none = disconnected. For bridging, enter the host bridge name (for example br0).': 'Vacío = NAT de usuario. restrict = red de usuario aislada. none = desconectada. Para bridge, escribe el nombre del bridge del anfitrión (por ejemplo br0).',
  'Comma-separated host:guest pairs. Quickemu forwards both TCP and UDP on all host interfaces. Only available with user NAT/restricted networking.': 'Pares anfitrión:invitado separados por comas. Quickemu redirige TCP y UDP en todas las interfaces. Solo disponible con NAT de usuario o red restringida.',
  'Share only a trusted folder. Guest access can expose host files; permissions and guest tools still apply.': 'Comparte solo carpetas de confianza. El invitado puede exponer archivos del anfitrión; siguen aplicando los permisos y las herramientas del invitado.',
  'Comma-separated USB vendor:product identifiers. Disconnecting host devices may interrupt other applications.': 'Identificadores vendor:product de USB separados por comas. Desconectar dispositivos del anfitrión puede interrumpir otras aplicaciones.',
  'Enter a positive CPU count': 'Introduce un número de CPU positivo',
  'Use a size such as 4G or 512M': 'Usa un tamaño como 4G o 512M',
  'Enter a valid MAC address': 'Introduce una dirección MAC válida',
  'Use port pairs from 1 to 65535, for example 8080:80':
      'Usa pares de puertos de 1 a 65535, por ejemplo 8080:80',
  'Enter a network mode or a valid host bridge name':
      'Introduce un modo de red o un nombre de bridge válido',
  'Download started — track it in Activity':
      'Descarga iniciada — síguela en Actividad',
  'Appearance': 'Apariencia',
  'Behaviour': 'Comportamiento',
  'Virtual machines': 'Máquinas virtuales',
  'About': 'Acerca de',
  'Change': 'Cambiar',
  'Pick a folder': 'Elegir carpeta',
  'Refresh interval': 'Intervalo de actualización',
  'How often the machine list is updated':
      'Con qué frecuencia se actualiza la lista de máquinas',
  'Preferred display viewer': 'Visor de pantalla preferido',
  'Used to open the console of running machines':
      'Se usa para abrir la consola de las máquinas en ejecución',
  'Automatic': 'Automático',
  'Advanced configuration mode': 'Modo de configuración avanzado',
  'Show every configuration key in the VM settings page':
      'Mostrar todas las claves en la página de ajustes de la VM',
  'Notify when downloads finish': 'Notificar al terminar las descargas',
  'Confirm risky actions': 'Confirmar acciones de riesgo',
  'Ask before resetting machines, forcing stops or applying snapshots. Deleting always asks.': 'Preguntar antes de reiniciar máquinas, forzar apagados o aplicar instantáneas. Eliminar siempre pregunta.',
  'Profile': 'Perfil',
  'Low disk space': 'Poco espacio en disco',
  'Continue anyway': 'Continuar de todos modos',
  'The selected image is currently unavailable.':
      'La imagen seleccionada no está disponible ahora mismo.',
  'Snapshot tag': 'Etiqueta de instantánea',
  'Tag for the new or existing snapshot':
      'Etiqueta para la instantánea nueva o existente',
  'Info': 'Información',
  'Apply': 'Aplicar',
  'Existing snapshots': 'Instantáneas existentes',
  'No snapshots yet. Snapshots capture the disk state so you can roll back later.': 'Sin instantáneas todavía. Las instantáneas capturan el estado del disco para poder volver atrás.',
  'Delete snapshot {0}': 'Eliminar instantánea {0}',
  'Apply snapshot {0}': 'Aplicar instantánea {0}',
  'The snapshot {0} of {1} will be permanently deleted. This cannot be undone.': 'La instantánea {0} de {1} se eliminará permanentemente. No se puede deshacer.',
  'The current state of {0} will be replaced by the snapshot {1}. This cannot be undone.': 'El estado actual de {0} será reemplazado por la instantánea {1}. No se puede deshacer.',
  'Settings — {0}': 'Ajustes — {0}',
};
