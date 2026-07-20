import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/invoice_model.dart';
import '../utils/currency_helper.dart';

/// PDF invoice generator — multi-page A4 with fixed header & footer on every page
class InvoicePdfGenerator {
  // ── Colors ────────────────────────────────────────────────────────────────
  static const PdfColor _hdrLeft    = PdfColor.fromInt(0xFF1E3A5F);
  static const PdfColor _hdrRight   = PdfColor.fromInt(0xFF1B5E20);
  static const PdfColor _blue       = PdfColor.fromInt(0xFF2563EB);
  static const PdfColor _green      = PdfColor.fromInt(0xFF2E7D32);
  static const PdfColor _greenLight = PdfColor.fromInt(0xFF43A047);
  static const PdfColor _blueLight  = PdfColor.fromInt(0xFF1A65C0);
  static const PdfColor _red        = PdfColor.fromInt(0xFFCC0000);
  static const PdfColor _white      = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor _dark       = PdfColor.fromInt(0xFF1A1A1A);
  static const PdfColor _mid        = PdfColor.fromInt(0xFF555555);
  static const PdfColor _border     = PdfColor.fromInt(0xFFE0E0E0);
  static const PdfColor _rowEven    = PdfColor.fromInt(0xFFF0F4FF);
  static const PdfColor _notesBg    = PdfColor.fromInt(0xFFFFFDE7);
  static const PdfColor _notesBdr   = PdfColor.fromInt(0xFFFFECB3);
  static const PdfColor _grey       = PdfColor.fromInt(0xFF94A3B8);
  static const PdfColor _yellow     = PdfColor.fromInt(0xFFFFFF00);
  static const PdfColor _orange     = PdfColor.fromInt(0xFFE65100);

  // ── Public entry point ────────────────────────────────────────────────────
  static Future<pw.Document> buildDocument(Invoice invoice) async {
    pw.MemoryImage? logo;
    try {
      final data = await rootBundle.load('assets/images/company_logo.png');
      logo = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {}

    final invNum  = invoice.invoiceNumber.toString().padLeft(4, '0');
    final dateStr = DateFormat('MMMM dd, yyyy').format(invoice.invoiceDate);

    final pdf = pw.Document(compress: true);

    // ── PageTheme: A4 with zero margin (we handle padding ourselves) ─────────
    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      buildBackground: (ctx) => pw.Container(color: _white),
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        // ── HEADER (repeats on every page) ──────────────────────────────────
        header: (ctx) => _buildHeader(logo, invNum, invoice, ctx),
        // ── FOOTER (repeats on every page) ──────────────────────────────────
        footer: (ctx) => _buildFooter(ctx),
        // ── BODY ────────────────────────────────────────────────────────────
        build: (ctx) => [
          // Info cards (Bill To + Invoice Details) — first page only
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(36, 20, 36, 0),
            child: _buildInfoRow(invoice, invNum, dateStr),
          ),
          pw.SizedBox(height: 20),
          // Items table (auto-splits across pages)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 36),
            child: _buildItemsTable(invoice),
          ),
          pw.SizedBox(height: 16),
          // Notes + Totals (bottom of last page)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 36),
            child: _buildTotalsRow(invoice),
          ),
          if (invoice.notes.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 36),
              child: _buildNotes(invoice.notes),
            ),
          ],
          pw.SizedBox(height: 20),
        ],
      ),
    );

    return pdf;
  }

  /// Save PDF to bytes (for download / share)
  static Future<List<int>> generate(Invoice invoice) async {
    final doc = await buildDocument(invoice);
    return doc.save();
  }

  // ── HEADER ─────────────────────────────────────────────────────────────────
  static pw.Widget _buildHeader(pw.MemoryImage? logo, String invNum,
      Invoice invoice, pw.Context ctx) {
    return pw.Container(
      width: double.infinity,
      decoration: const pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [_hdrLeft, _hdrRight],
          begin: pw.Alignment.centerLeft,
          end: pw.Alignment.centerRight,
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 22),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Logo
          pw.Container(
            width: 56, height: 56,
            decoration: pw.BoxDecoration(
              color: const PdfColor(1, 1, 1, 0.15),
              borderRadius: pw.BorderRadius.circular(10),
              border: pw.Border.all(color: const PdfColor(1, 1, 1, 0.3)),
            ),
            child: logo != null
                ? pw.ClipRRect(horizontalRadius: 9, verticalRadius: 9,
                    child: pw.Image(logo, fit: pw.BoxFit.contain))
                : pw.Center(child: pw.Text('VT',
                    style: pw.TextStyle(color: _white, fontSize: 20,
                        fontWeight: pw.FontWeight.bold))),
          ),
          pw.SizedBox(width: 14),
          // Company info
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('VINEX TECHNOLOGY',
                    style: pw.TextStyle(color: _white, fontSize: 20,
                        fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
                pw.SizedBox(height: 5),
                pw.Text('Baghdad, Yarmouk — Al-Fakhri 2 Building  |  📞 07803662728',
                    style: pw.TextStyle(
                        color: const PdfColor(1, 1, 1, 0.8), fontSize: 9)),
              ],
            ),
          ),
          // Invoice badge
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: pw.BoxDecoration(
                color: const PdfColor(1, 1, 1, 0.2),
                borderRadius: pw.BorderRadius.circular(5),
                border: pw.Border.all(color: const PdfColor(1, 1, 1, 0.4)),
              ),
              child: pw.Text(invoice.isQuote ? 'QUOTATION' : 'INVOICE',
                  style: pw.TextStyle(color: _white, fontSize: 10,
                      fontWeight: pw.FontWeight.bold, letterSpacing: 2.5)),
            ),
            pw.SizedBox(height: 5),
            pw.Text('#$invNum',
                style: pw.TextStyle(color: _white, fontSize: 22,
                    fontWeight: pw.FontWeight.bold)),
            if (ctx.pagesCount > 1)
              pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                  style: pw.TextStyle(
                      color: const PdfColor(1, 1, 1, 0.7), fontSize: 9)),
          ]),
        ],
      ),
    );
  }

  // ── FOOTER ─────────────────────────────────────────────────────────────────
  static pw.Widget _buildFooter(pw.Context ctx) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Thank you for your business!',
              style: pw.TextStyle(fontSize: 10, color: _grey,
                  fontStyle: pw.FontStyle.italic)),
          pw.Text('VINEX TECHNOLOGY © 2025',
              style: pw.TextStyle(fontSize: 10, color: _blue,
                  fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // ── INFO ROW (Bill To + Invoice Details) ───────────────────────────────────
  static pw.Widget _buildInfoRow(
      Invoice invoice, String invNum, String dateStr) {
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(child: _infoCard(
        title: 'BILL TO', accentColor: _blue,
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Customer', style: pw.TextStyle(fontSize: 10,
                fontWeight: pw.FontWeight.bold, color: _mid)),
            pw.SizedBox(height: 5),
            pw.Text(invoice.customerName, style: pw.TextStyle(
                fontSize: 15, fontWeight: pw.FontWeight.bold, color: _red)),
          ]),
      )),
      pw.SizedBox(width: 16),
      pw.Expanded(child: _infoCard(
        title: 'INVOICE DETAILS', accentColor: _green,
        child: pw.Table(
          columnWidths: {
            0: const pw.FlexColumnWidth(1.2),
            1: const pw.FlexColumnWidth(1),
          },
          children: [
            _detailRow('Invoice No.', '#$invNum'),
            _detailRow('Date', dateStr),
            _detailRow('Items', '${invoice.items.length} item(s)'),
          ],
        ),
      )),
    ]);
  }

  static pw.Widget _infoCard({
    required String title,
    required PdfColor accentColor,
    required pw.Widget child,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _white,
        borderRadius: pw.BorderRadius.circular(7),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: pw.BoxDecoration(
              color: accentColor,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(6),
                topRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Text(title, style: pw.TextStyle(color: _white,
                fontSize: 11, fontWeight: pw.FontWeight.bold,
                letterSpacing: 1.2)),
          ),
          pw.Padding(padding: const pw.EdgeInsets.all(11), child: child),
        ],
      ),
    );
  }

  static pw.TableRow _detailRow(String label, String value) {
    return pw.TableRow(children: [
      pw.Padding(padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Text(label, style: pw.TextStyle(color: _mid,
              fontSize: 11, fontWeight: pw.FontWeight.bold))),
      pw.Padding(padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Text(value, textAlign: pw.TextAlign.right,
              style: pw.TextStyle(color: _red, fontSize: 12,
                  fontWeight: pw.FontWeight.bold))),
    ]);
  }

  // ── ITEMS TABLE ────────────────────────────────────────────────────────────
  static pw.Widget _buildItemsTable(Invoice invoice) {
    return pw.TableHelper.fromTextArray(
      border: pw.TableBorder.all(color: _border, width: 0.5),
      headerDecoration: const pw.BoxDecoration(color: _blue),
      headerStyle: pw.TextStyle(color: _white, fontSize: 11,
          fontWeight: pw.FontWeight.bold, letterSpacing: 0.4),
      headerPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      cellStyle: pw.TextStyle(fontSize: 11, color: _dark),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      oddRowDecoration: const pw.BoxDecoration(color: _rowEven),
      // evenRowDecoration not available in this pdf version; white is the default
      columnWidths: {
        0: const pw.FixedColumnWidth(32),
        1: const pw.FlexColumnWidth(5),
        2: const pw.FixedColumnWidth(55),
        3: const pw.FixedColumnWidth(105),
        4: const pw.FixedColumnWidth(105),
      },
      headers: ['#', 'ITEM NAME', 'QTY', 'UNIT PRICE', 'AMOUNT'],
      headerAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      data: invoice.items.asMap().entries.map((e) {
        final item = e.value;
        final qty = item.quantity % 1 == 0
            ? item.quantity.toInt().toString()
            : item.quantity.toStringAsFixed(2);
        return [
          '${e.key + 1}',
          item.itemName,
          qty,
          CurrencyHelper.format(item.unitPrice),
          CurrencyHelper.format(item.totalPrice),
        ];
      }).toList(),
    );
  }

  // ── TOTALS (right-aligned summary) ────────────────────────────────────────
  static pw.Widget _buildTotalsRow(Invoice invoice) {
    final hasDiscount = invoice.discount > 0;
    final hasDP       = invoice.hasDownPayment;

    return pw.Row(children: [
      // Notes placeholder keeps totals right-aligned when no notes
      pw.Expanded(child: pw.SizedBox()),
      pw.SizedBox(width: 260,
        child: pw.Container(
          decoration: pw.BoxDecoration(
            color: _white,
            borderRadius: pw.BorderRadius.circular(7),
            border: pw.Border.all(color: _border),
          ),
          child: pw.Column(children: [
            // Subtotal
            if (hasDiscount) ...[
              _totalRow('Subtotal',
                  CurrencyHelper.format(invoice.subtotal), _mid, _dark),
              _totalRow('Discount',
                  '− ${CurrencyHelper.format(invoice.discount)}',
                  _orange, _orange),
              pw.Container(height: 0.8, color: _border),
            ],
            // TOTAL bar
            pw.Container(
              decoration: pw.BoxDecoration(
                gradient: const pw.LinearGradient(
                    colors: [_green, _greenLight],
                    begin: pw.Alignment.centerLeft,
                    end: pw.Alignment.centerRight),
                borderRadius: pw.BorderRadius.only(
                  bottomLeft:  hasDP ? pw.Radius.zero : const pw.Radius.circular(6),
                  bottomRight: hasDP ? pw.Radius.zero : const pw.Radius.circular(6),
                  topLeft:  !hasDiscount ? const pw.Radius.circular(6) : pw.Radius.zero,
                  topRight: !hasDiscount ? const pw.Radius.circular(6) : pw.Radius.zero,
                ),
              ),
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text('TOTAL AMOUNT',
                    style: pw.TextStyle(color: _white, fontSize: 12,
                        fontWeight: pw.FontWeight.bold, letterSpacing: 0.6))),
                pw.Text(CurrencyHelper.format(invoice.totalAmount),
                    style: pw.TextStyle(color: _yellow, fontSize: 13,
                        fontWeight: pw.FontWeight.bold)),
              ]),
            ),
            if (hasDP) ...[
              _totalRow('Down Payment',
                  CurrencyHelper.format(invoice.downPayment),
                  _blueLight, _blueLight, bold: true),
              // Remaining bar
              pw.Container(
                decoration: const pw.BoxDecoration(
                  gradient: pw.LinearGradient(
                      colors: [_blueLight, PdfColor(0.12, 0.50, 0.90)],
                      begin: pw.Alignment.centerLeft,
                      end: pw.Alignment.centerRight),
                  borderRadius: pw.BorderRadius.only(
                    bottomLeft: pw.Radius.circular(6),
                    bottomRight: pw.Radius.circular(6),
                  ),
                ),
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: pw.Row(children: [
                  pw.Expanded(child: pw.Text('Remaining Amount',
                      style: pw.TextStyle(color: _white, fontSize: 12,
                          fontWeight: pw.FontWeight.bold, letterSpacing: 0.5))),
                  pw.Text(CurrencyHelper.format(invoice.remainingAmount),
                      style: pw.TextStyle(color: _yellow, fontSize: 13,
                          fontWeight: pw.FontWeight.bold)),
                ]),
              ),
            ],
          ]),
        ),
      ),
    ]);
  }

  static pw.Widget _totalRow(String label, String value,
      PdfColor labelColor, PdfColor valueColor, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(label,
            style: pw.TextStyle(fontSize: 11, color: labelColor,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 12, color: valueColor,
                fontWeight: pw.FontWeight.bold)),
      ]),
    );
  }

  // ── NOTES ──────────────────────────────────────────────────────────────────
  static pw.Widget _buildNotes(String notes) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _notesBg,
        borderRadius: pw.BorderRadius.circular(7),
        border: pw.Border.all(color: _notesBdr),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('NOTES', style: pw.TextStyle(fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF795548), letterSpacing: 1)),
          pw.SizedBox(height: 6),
          pw.Text(notes, style: pw.TextStyle(fontSize: 13,
              fontWeight: pw.FontWeight.bold, color: _dark, lineSpacing: 2)),
        ],
      ),
    );
  }
}
