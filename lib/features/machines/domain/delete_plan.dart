/// Files a backend reports it would delete (schema: vm-delete-plan v1).
class DeletePlan {
  const DeletePlan(this.vm, this.paths);
  final String vm;
  final List<String> paths;
}
