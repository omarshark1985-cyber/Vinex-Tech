import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/invoice_model.dart';
import '../utils/currency_helper.dart';

/// PDF invoice generator — exactly matches the Print View (HTML) screen
class InvoicePdfGenerator {
  // ── Colors (identical to Print View HTML) ────────────────────────────────
  /// Header gradient: left = #1e3a5f, right = #1b5e20
  static const PdfColor _hdrLeft  = PdfColor.fromInt(0xFF1E3A5F);
  static const PdfColor _hdrRight = PdfColor.fromInt(0xFF1B5E20);

  /// Accent colours
  static const PdfColor _blue        = PdfColor.fromInt(0xFF2563EB); // table header + BILL TO
  static const PdfColor _green       = PdfColor.fromInt(0xFF2E7D32); // INVOICE DETAILS
  static const PdfColor _greenLight  = PdfColor.fromInt(0xFF43A047); // total bar right
  static const PdfColor _red         = PdfColor.fromInt(0xFFCC0000); // customer name / values

  /// Neutral
  static const PdfColor _white       = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor _black       = PdfColor.fromInt(0xFF000000);
  static const PdfColor _dark        = PdfColor.fromInt(0xFF333333);
  static const PdfColor _mid         = PdfColor.fromInt(0xFF444444);
  static const PdfColor _border      = PdfColor.fromInt(0xFFE5E7EB);
  static const PdfColor _rowEven     = PdfColor.fromInt(0xFFF0F4FF);
  static const PdfColor _notesBg     = PdfColor.fromInt(0xFFFFFDE7);
  static const PdfColor _notesBorder = PdfColor.fromInt(0xFFFFECB3);
  static const PdfColor _footerText  = PdfColor.fromInt(0xFF94A3B8);
  static const PdfColor _footerBlue  = PdfColor.fromInt(0xFF2563EB);

  // ── Public entry point ────────────────────────────────────────────────────
  static Future<Uint8List> generate(Invoice invoice) async {
    // Load logo
    pw.MemoryImage? logo;
    try {
      final data = await rootBundle.load('assets/images/company_logo.png');
      logo = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      logo = null;
    }

    final invNum    = invoice.invoiceNumber.toString().padLeft(4, '0');
    final dateStr   = DateFormat('MMMM dd, yyyy').format(invoice.invoiceDate);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,           // we control padding manually
        build: (ctx) => [
          _buildHeader(logo, invNum),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(40, 24, 40, 0),
            child: _buildInfoRow(invoice, invNum, dateStr),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(40, 24, 40, 0),
            child: _buildItemsTable(invoice),
          ),
          if (invoice.notes.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(40, 20, 40, 0),
              child: _buildNotes(invoice.notes),
            ),
          pw.Spacer(),
          _buildFooter(),
        ],
      ),
    );
    return pdf.save();
  }

  // ── HEADER ────────────────────────────────────────────────────────────────
  static pw.Widget _buildHeader(pw.MemoryImage? logo, String invNum) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      decoration: const pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [_hdrLeft, _hdrRight],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.topRight,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // ── Logo box ──────────────────────────────────────────────────
          pw.Container(
            width: 64,
            height: 64,
            decoration: pw.BoxDecoration(
              color: const PdfColor(1, 1, 1, 0.15),
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(
                  color: const PdfColor(1, 1, 1, 0.3), width: 1.5),
            ),
            child: logo != null
                ? pw.ClipRRect(
                    horizontalRadius: 10,
                    verticalRadius: 10,
                    child: pw.Image(logo, fit: pw.BoxFit.contain))
                : pw.Center(
                    child: pw.Text('VT',
                        style: pw.TextStyle(
                            color: _white,
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold))),
          ),
          pw.SizedBox(width: 16),
          // ── Company name + address + phone ────────────────────────────
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('VINEX TECHNOLOGY',
                    style: pw.TextStyle(
                        color: _white,
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 2)),
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    pw.Text('📍 ',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.Text(
                        'Baghdad, Yarmouk, Al-Fakhri 2 Building',
                        style: pw.TextStyle(
                            color: const PdfColor(1, 1, 1, 0.85),
                            fontSize: 10,
                            letterSpacing: 0.2)),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Row(
                  children: [
                    pw.Text('📞 ',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('07803662728',
                        style: pw.TextStyle(
                            color: const PdfColor(1, 1, 1, 0.85),
                            fontSize: 10,
                            letterSpacing: 0.5)),
                  ],
                ),
              ],
            ),
          ),
          // ── Invoice badge ─────────────────────────────────────────────
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 14, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: const PdfColor(1, 1, 1, 0.2),
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(
                      color: const PdfColor(1, 1, 1, 0.4), width: 1),
                ),
                child: pw.Text('INVOICE',
                    style: pw.TextStyle(
                        color: _white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 3)),
              ),
              pw.SizedBox(height: 6),
              pw.Text('#$invNum',
                  style: pw.TextStyle(
                      color: _white,
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  // ── INFO ROW ──────────────────────────────────────────────────────────────
  static pw.Widget _buildInfoRow(
      Invoice invoice, String invNum, String dateStr) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Bill To
        pw.Expanded(
          child: _infoCard(
            title: 'BILL TO',
            accentColor: _blue,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Customer',
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _mid)),
                pw.SizedBox(height: 4),
                pw.Text(invoice.customerName,
                    style: pw.TextStyle(
                        fontSize: 17,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFFCC0000))),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 16),
        // Invoice Details
        pw.Expanded(
          child: _infoCard(
            title: 'INVOICE DETAILS',
            accentColor: _green,
            child: pw.Table(
              columnWidths: {
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(1),
              },
              children: [
                _detailRow('Invoice No.', '#$invNum'),
                _detailRow('Date', dateStr),
                _detailRow('Items', '${invoice.items.length} item(s)'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _infoCard({
    required String title,
    required PdfColor accentColor,
    required pw.Widget child,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _border, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: accentColor,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(7),
                topRight: pw.Radius.circular(7),
              ),
            ),
            child: pw.Text(title,
                style: pw.TextStyle(
                    color: _white,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.2)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(12),
            child: child,
          ),
        ],
      ),
    );
  }

  static pw.TableRow _detailRow(String label, String value,
      {bool small = false}) {
    return pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Text(label,
            style: pw.TextStyle(
                color: _mid,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Text(value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(
                color: _red,
                fontSize: small ? 11 : 13,
                fontWeight: pw.FontWeight.bold)),
      ),
    ]);
  }

  // ── ITEMS TABLE ───────────────────────────────────────────────────────────
  static pw.Widget _buildItemsTable(Invoice invoice) {
    final subtotal   = invoice.subtotal;
    final hasDiscount = invoice.discount > 0;

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _border, width: 1),
      ),
      child: pw.Column(
        children: [
          // ── Table header ──────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: const pw.BoxDecoration(
              color: _blue,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(7),
                topRight: pw.Radius.circular(7),
              ),
            ),
            child: pw.Row(
              children: [
                _hdrCell('#',          28,  align: pw.TextAlign.center),
                _hdrCell('ITEM NAME',   0,  flex: 5),
                _hdrCell('QTY',        60,  align: pw.TextAlign.center),
                _hdrCell('UNIT PRICE', 110, align: pw.TextAlign.right),
                _hdrCell('AMOUNT',     110, align: pw.TextAlign.right),
              ],
            ),
          ),

          // ── Data rows ─────────────────────────────────────────────────
          ...invoice.items.asMap().entries.map((entry) {
            final idx  = entry.key;
            final item = entry.value;
            final bg   = idx % 2 == 0 ? _white : _rowEven;
            final qty  = item.quantity % 1 == 0
                ? item.quantity.toInt().toString()
                : item.quantity.toStringAsFixed(2);

            return pw.Container(
              color: bg,
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: pw.Row(
                children: [
                  // Seq badge
                  pw.SizedBox(
                    width: 28,
                    child: pw.Center(
                      child: pw.Container(
                        width: 22,
                        height: 22,
                        decoration: pw.BoxDecoration(
                          color: const PdfColor(0.082, 0.345, 0.753, 0.12),
                          shape: pw.BoxShape.circle,
                        ),
                        child: pw.Center(
                          child: pw.Text('${item.sequence}',
                              style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _blue)),
                        ),
                      ),
                    ),
                  ),
                  pw.Expanded(
                    flex: 5,
                    child: pw.Text(item.itemName,
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: _dark)),
                  ),
                  pw.SizedBox(
                    width: 60,
                    child: pw.Text(qty,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold, color: _dark)),
                  ),
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text(
                        CurrencyHelper.format(item.unitPrice),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 12, fontWeight: pw.FontWeight.bold, color: _dark)),
                  ),
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text(
                        CurrencyHelper.format(item.totalPrice),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: _black)),
                  ),
                ],
              ),
            );
          }),

          // ── Divider before totals ─────────────────────────────────────
          pw.Container(
            height: 2,
            color: _border,
          ),

          // ── Subtotal row (only when discount exists) ──────────────────
          if (hasDiscount) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: pw.Row(
                children: [
                  pw.Expanded(child: pw.SizedBox()),
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text('Subtotal',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 13, fontWeight: pw.FontWeight.bold, color: _mid)),
                  ),
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text(
                        CurrencyHelper.format(subtotal),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 13, fontWeight: pw.FontWeight.bold, color: _black)),
                  ),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: pw.Row(
                children: [
                  pw.Expanded(child: pw.SizedBox()),
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text('Discount',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 13,
                            color: _red,
                            fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(
                    width: 110,
                    child: pw.Text(
                        '- ${CurrencyHelper.format(invoice.discount)}',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                            fontSize: 13,
                            color: _red,
                            fontWeight: pw.FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

          // ── TOTAL AMOUNT bar ──────────────────────────────────────────
          pw.Container(
            decoration: pw.BoxDecoration(
              gradient: const pw.LinearGradient(
                colors: [_green, _greenLight],
                begin: pw.Alignment.centerLeft,
                end: pw.Alignment.centerRight,
              ),
              borderRadius: invoice.hasDownPayment
                  ? pw.BorderRadius.zero
                  : const pw.BorderRadius.only(
                      bottomLeft: pw.Radius.circular(7),
                      bottomRight: pw.Radius.circular(7),
                    ),
            ),
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text('TOTAL AMOUNT',
                      style: pw.TextStyle(
                          color: _white,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.8)),
                ),
                pw.Text(
                    CurrencyHelper.format(invoice.totalAmount),
                    style: pw.TextStyle(
                        color: const PdfColor.fromInt(0xFF000000),
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),

          // ── DOWN PAYMENT & REMAINING ──────────────────────────────────
          if (invoice.hasDownPayment) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text('Down Payment',
                        style: pw.TextStyle(
                            fontSize: 12,
                            color: const PdfColor(0.08, 0.40, 0.75),
                            fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.Text(
                    CurrencyHelper.format(invoice.downPayment),
                    style: pw.TextStyle(
                        fontSize: 12,
                        color: const PdfColor(0.08, 0.40, 0.75),
                        fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 4),
              decoration: const pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  colors: [
                    PdfColor(0.08, 0.40, 0.75),
                    PdfColor(0.10, 0.47, 0.85),
                  ],
                  begin: pw.Alignment.centerLeft,
                  end: pw.Alignment.centerRight,
                ),
                borderRadius: pw.BorderRadius.only(
                  bottomLeft: pw.Radius.circular(7),
                  bottomRight: pw.Radius.circular(7),
                ),
              ),
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text('Remaining Amount',
                        style: pw.TextStyle(
                            color: _white,
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.5)),
                  ),
                  pw.Text(
                    CurrencyHelper.format(invoice.remainingAmount),
                    style: pw.TextStyle(
                        color: const PdfColor(1, 1, 0),
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static pw.Widget _hdrCell(String text, double width,
      {int flex = 0, pw.TextAlign align = pw.TextAlign.left}) {
    final style = pw.TextStyle(
        color: _white,
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 0.5);
    if (flex > 0) {
      return pw.Expanded(
          flex: flex,
          child: pw.Text(text, style: style, textAlign: align));
    }
    return pw.SizedBox(
        width: width,
        child: pw.Text(text, style: style, textAlign: align));
  }

  // ── NOTES ─────────────────────────────────────────────────────────────────
  static pw.Widget _buildNotes(String notes) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _notesBg,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _notesBorder, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('NOTES',
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF795548),
                  letterSpacing: 1)),
          pw.SizedBox(height: 6),
          pw.Text(notes,
              style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _black,
                  lineSpacing: 2)),
        ],
      ),
    );
  }

  // ── FOOTER ────────────────────────────────────────────────────────────────
  static pw.Widget _buildFooter() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(40, 14, 40, 14),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: _border, width: 1),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Thank you for your business!',
                  style: pw.TextStyle(
                      fontSize: 12,
                      color: _footerText,
                      fontStyle: pw.FontStyle.italic)),
              pw.SizedBox(height: 3),
              pw.Row(
                children: [
                  pw.Text('📍 Baghdad, Yarmouk, Al-Fakhri 2 Building',
                      style: pw.TextStyle(
                          fontSize: 11, color: _footerText)),
                  pw.SizedBox(width: 12),
                  pw.Text('📞 07803662728',
                      style: pw.TextStyle(
                          fontSize: 11, color: _footerText)),
                ],
              ),
            ],
          ),
          pw.Text('VINEX TECHNOLOGY © 2025',
              style: pw.TextStyle(
                  fontSize: 12,
                  color: _footerBlue,
                  fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
