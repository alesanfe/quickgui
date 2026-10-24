/// A named backend capability flag (e.g. structuredStatus).
class Capability {
  const Capability(this.name, this.supported);
  final String name;
  final bool supported;
}
