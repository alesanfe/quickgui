/// Execution plan emitted by --dry-run --format json (schema v1).
class ExecutionPlan {
  const ExecutionPlan(this.vm, this.command);
  final String vm;
  final String command;
}
