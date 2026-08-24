class LegalSection {
  final String? chapter;
  final String? article;
  final List<LegalItem> items;
  const LegalSection({this.chapter, this.article, required this.items});
}

class LegalItem {
  final String text;
  final bool bullet;
  final List<List<String>>? table;
  const LegalItem(this.text, {this.bullet = false, this.table});
}
