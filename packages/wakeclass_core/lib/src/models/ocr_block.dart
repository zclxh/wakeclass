/// OCR 识别出的一个文本块（行/词组），附带相对坐标。
///
/// 坐标统一使用**相对值（0..1）**，与图片分辨率解耦，
/// 因此可以忽略缩放直接参与网格计算。
class OcrTextBlock {
  const OcrTextBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// 文本内容（可能包含换行）。
  final String text;

  /// 边界框左边界（相对）。
  final double left;

  /// 边界框上边界（相对）。
  final double top;

  /// 边界框宽度（相对）。
  final double width;

  /// 边界框高度（相对）。
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  /// 与另一个矩形在水平方向的重叠长度。
  double horizontalOverlapWith(double otherLeft, double otherRight) {
    final lo = left > otherLeft ? left : otherLeft;
    final hi = right < otherRight ? right : otherRight;
    return hi - lo;
  }

  /// 与另一个矩形在垂直方向的重叠长度。
  double verticalOverlapWith(double otherTop, double otherBottom) {
    final lo = top > otherTop ? top : otherTop;
    final hi = bottom < otherBottom ? bottom : otherBottom;
    return hi - lo;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  factory OcrTextBlock.fromJson(Map<String, dynamic> json) => OcrTextBlock(
        text: json['text'] as String? ?? '',
        left: (json['left'] as num?)?.toDouble() ?? 0,
        top: (json['top'] as num?)?.toDouble() ?? 0,
        width: (json['width'] as num?)?.toDouble() ?? 0,
        height: (json['height'] as num?)?.toDouble() ?? 0,
      );

  @override
  String toString() =>
      'OcrTextBlock("${text.length > 12 ? '${text.substring(0, 12)}…' : text}" '
      '@(${left.toStringAsFixed(2)}, ${top.toStringAsFixed(2)}) '
      '${width.toStringAsFixed(2)}x${height.toStringAsFixed(2)})';
}
