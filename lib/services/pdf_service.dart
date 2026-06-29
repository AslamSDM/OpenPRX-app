import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfService {
  /// Extract plain text from a PDF [file]. Returns empty string on failure.
  static Future<String> extractText(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      try {
        final extractor = PdfTextExtractor(document);
        return extractor.extractText();
      } finally {
        document.dispose();
      }
    } catch (e) {
      return '';
    }
  }
}
