class CardStub {
  final String id;
  final String? imageUrl;
  final String tipo;
  bool tapped;
  CardStub(this.id, {this.imageUrl, this.tipo = '', this.tapped = false});
}
