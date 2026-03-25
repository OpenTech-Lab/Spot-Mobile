void main() {
  final d1 = DateTime(2020);
  final d2 = DateTime(2026);
  final list = [d1, d2];
  list.sort((a,b) => b.compareTo(a));
  print(list);
  final list2 = [d1, d2];
  list2.sort((a,b) => a.compareTo(b));
  print(list2);
}
