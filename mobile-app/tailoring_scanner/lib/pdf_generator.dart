import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfGenerator {
  static Future<void> generateAndSharePdf({
    required Map<String, dynamic> measurements,
    required Map<String, dynamic>? sizing,
    required String? imagePath,
    required String scanId,
  }) async {
    final pdf = pw.Document();

    // Load an image if it exists locally
    pw.ImageProvider? profileImage;
    if (imagePath != null &&
        imagePath != 'No Image' &&
        File(imagePath).existsSync()) {
      final imageBytes = File(imagePath).readAsBytesSync();
      profileImage = pw.MemoryImage(imageBytes);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "AI TAILORING REPORT",
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.deepPurple,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        "Scan ID: $scanId",
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.Text(
                    DateTime.now().toLocal().toString().split(' ')[0],
                    style: const pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.Divider(
                thickness: 1.5,
                color: PdfColors.deepPurple,
                height: 24,
              ),

              // Sizing Recommendation Box
              if (sizing != null) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.purple50,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColors.deepPurple200),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            "Recommended Size: ${sizing['recommended_size']}",
                            style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.deepPurple900,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            "Fit Type: ${sizing['fit_type']}",
                            style: const pw.TextStyle(
                              fontSize: 14,
                              color: PdfColors.purple,
                            ),
                          ),
                        ],
                      ),
                      if (profileImage != null)
                        pw.ClipRRect(
                          horizontalRadius: 8,
                          verticalRadius: 8,
                          child: pw.Image(
                            profileImage,
                            width: 50,
                            height: 70,
                            fit: pw.BoxFit.cover,
                          ),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),
              ],

              // Measurements Table Header
              pw.Text(
                "Detailed Body Measurements",
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),

              // Table of Measurements
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Metric',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Centimeters (cm)',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'Inches (in)',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  ...measurements.entries
                      .where((e) => e.key != 'calibration_ppc')
                      .map((entry) {
                        final data = entry.value as Map<String, dynamic>;
                        final formattedName = entry.key
                            .replaceAll('_', ' ')
                            .toUpperCase();
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(formattedName),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('${data['cm']} cm'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('${data['in']} in'),
                            ),
                          ],
                        );
                      }),
                ],
              ),

              pw.Spacer(),

              // Footer
              pw.Center(
                child: pw.Text(
                  "Generated securely via Contactless AI Tailoring Scanner",
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Share or Print the PDF document
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'tailoring_report_$scanId.pdf',
    );
  }
}
