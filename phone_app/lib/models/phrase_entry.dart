class PhraseEntry {
  const PhraseEntry({
    required this.id,
    required this.category,
    required this.text,
    required this.checksum,
  });

  final String id;
  final String category;
  final String text;
  final String checksum;

  factory PhraseEntry.fromJson(Map<String, dynamic> json) {
    return PhraseEntry(
      id: json['id'] as String,
      category: json['category'] as String,
      text: json['text'] as String,
      checksum: json['checksum'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'text': text,
      'checksum': checksum,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is PhraseEntry &&
        other.id == id &&
        other.category == category &&
        other.text == text &&
        other.checksum == checksum;
  }

  @override
  int get hashCode => Object.hash(id, category, text, checksum);
}
