/// Port: access to a VM's `.conf` file — a `key="value"` store plus
/// raw load/save for full-text editing.
///
/// Presentation and application layers use this contract; the concrete
/// implementation lives in `infrastructure/vm_config.dart`.
abstract class VmConfigStore {
  /// Reads one `key` value from [confPath], or null when absent.
  String? read(String confPath, String key);

  /// Writes a `key="value"` entry to [confPath], replacing the
  /// existing line or appending a new one.
  void write(String confPath, String key, String value);

  /// Loads the full file contents (empty string when missing).
  Future<String> loadRaw(String confPath);

  /// Persists [content] as the new file contents.
  Future<void> saveRaw(String confPath, String content);
}
