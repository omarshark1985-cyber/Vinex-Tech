import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/invoice_model.dart';
import '../utils/currency_helper.dart';

// ══════════════════════════════════════════════════════════════════════════════
// InvoicePdfGenerator
// Pixel-perfect mirror of the Flutter _A4Page preview widget.
// Every color, dimension, font-size, bold flag, column width, and IQD position
// matches the on-screen preview exactly.
// ══════════════════════════════════════════════════════════════════════════════
class InvoicePdfGenerator {
  // ── Colors (identical to _pv* constants in invoice_detail_screen.dart) ───
  static const PdfColor _hdrLeft     = PdfColor.fromInt(0xFF1E3A5F);
  static const PdfColor _hdrRight    = PdfColor.fromInt(0xFF1B5E20);
  static const PdfColor _blue        = PdfColor.fromInt(0xFF2563EB);
  static const PdfColor _green       = PdfColor.fromInt(0xFF2E7D32);
  static const PdfColor _greenLight  = PdfColor.fromInt(0xFF43A047);
  static const PdfColor _blueLight   = PdfColor.fromInt(0xFF1A65C0);
  static const PdfColor _blueLighter = PdfColor.fromInt(0xFF1F80E6);
  static const PdfColor _red         = PdfColor.fromInt(0xFFCC0000);
  static const PdfColor _white       = PdfColor.fromInt(0xFFFFFFFF);
  static const PdfColor _dark        = PdfColor.fromInt(0xFF1A1A1A);
  static const PdfColor _mid         = PdfColor.fromInt(0xFF555555);
  static const PdfColor _border      = PdfColor.fromInt(0xFFE0E0E0);
  static const PdfColor _rowEven     = PdfColor.fromInt(0xFFF0F4FF);
  static const PdfColor _notesBg     = PdfColor.fromInt(0xFFFFFDE7);
  static const PdfColor _notesBdr    = PdfColor.fromInt(0xFFFFECB3);
  static const PdfColor _grey        = PdfColor.fromInt(0xFF94A3B8);
  static const PdfColor _yellow      = PdfColor.fromInt(0xFFFFFF00);
  static const PdfColor _orange      = PdfColor.fromInt(0xFFE65100);
  static const PdfColor _brown       = PdfColor.fromInt(0xFF795548);

  // ── A4 layout constants (mirror of invoice_detail_screen.dart _a4* consts) ─
  // A4 at 72 pt/inch = 595.28 × 841.89 pt  (pdf package uses pt by default)
  // We use the same logical proportions as the Flutter widget (794 × 1123 px)
  // by working in the pdf package's pt coordinate system.
  static const double _bodyPadH     = 32;   // body horizontal padding
  static const double _bodyPadTop   = 20;   // body top padding (page 1)
  static const double _bodyPadBot   = 20;   // body bottom padding
  static const double _infoRowH     = 80;   // info cards height
  static const double _tableRowH    = 28;   // items table data row height
  static const double _tableHdrH    = 28;   // items table header row height

  // ── Column widths for items table (matches Flutter widget exactly) ────────
  // Total content width ≈ 595 − 2×32(hPad) − 2×1(border) = 529 pt
  // Flutter: Fixed(40) + Flex(1) + Fixed(55) + Fixed(125) + Fixed(125) = 345 + flex
  // Scale factor ≈ 529/794 ≈ 0.666  →  Fixed(27) + Flex + Fixed(37) + Fixed(83) + Fixed(83)
  static const double _colW0 = 27;   // #
  static const double _colW2 = 37;   // QTY
  static const double _colW3 = 83;   // UNIT PRICE
  static const double _colW4 = 83;   // AMOUNT

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

    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      buildBackground: (_) => pw.Container(color: _white),
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,
        // ── HEADER — repeats on every page ───────────────────────────────────
        header: (ctx) => _buildHeader(logo, invNum, invoice, ctx),
        // ── FOOTER — repeats on every page ───────────────────────────────────
        footer: (ctx) => _buildFooter(ctx),
        // ── BODY ─────────────────────────────────────────────────────────────
        build: (ctx) => [
          // Info cards (page 1 only — MultiPage places them before the table)
          pw.Padding(
            padding: pw.EdgeInsets.fromLTRB(
                _bodyPadH, _bodyPadTop, _bodyPadH, 0),
            child: _buildInfoRow(invoice, invNum, dateStr),
          ),
          pw.SizedBox(height: 20),
          // Items table — auto-splits across pages
          pw.Padding(
            padding: pw.EdgeInsets.symmetric(horizontal: _bodyPadH),
            child: _buildItemsTable(invoice),
          ),
          pw.SizedBox(height: 16),
          // Totals
          pw.Padding(
            padding: pw.EdgeInsets.symmetric(horizontal: _bodyPadH),
            child: _buildTotalsRow(invoice),
          ),
          // Notes
          if (invoice.notes.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Padding(
              padding: pw.EdgeInsets.symmetric(horizontal: _bodyPadH),
              child: _buildNotes(invoice.notes),
            ),
          ],
          pw.SizedBox(height: _bodyPadBot),
        ],
      ),
    );

    return pdf;
  }

  /// Save to bytes (download / share)
  static Future<List<int>> generate(Invoice invoice) async {
    final doc = await buildDocument(invoice);
    return doc.save();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HEADER  — gradient bar with logo + company + invoice badge
  // Mirrors _A4Page._buildHeader() and _buildContHeader()
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildHeader(
      pw.MemoryImage? logo, String invNum, Invoice invoice, pw.Context ctx) {
    final isFirstPage = ctx.pageNumber == 1;

    if (isFirstPage) {
      // ── Full header (page 1) ─────────────────────────────────────────────
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        decoration: const pw.BoxDecoration(
          gradient: pw.LinearGradient(
            colors: [_hdrLeft, _hdrRight],
            begin: pw.Alignment.centerLeft,
            end: pw.Alignment.centerRight,
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Logo box
            pw.Container(
              width: 50, height: 50,
              decoration: pw.BoxDecoration(
                color: const PdfColor(1, 1, 1, 0.15),
                borderRadius: pw.BorderRadius.circular(9),
                border: pw.Border.all(color: const PdfColor(1, 1, 1, 0.3)),
              ),
              child: logo != null
                  ? pw.ClipRRect(horizontalRadius: 8, verticalRadius: 8,
                      child: pw.Image(logo, fit: pw.BoxFit.contain))
                  : pw.Center(
                      child: pw.Text('VT',
                          style: pw.TextStyle(color: _white, fontSize: 17,
                              fontWeight: pw.FontWeight.bold))),
            ),
            pw.SizedBox(width: 14),
            // Company info
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('VINEX TECHNOLOGY',
                      style: pw.TextStyle(color: _white, fontSize: 17,
                          fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                      'Baghdad, Yarmouk — Al-Fakhri 2 Building  |  07803662728',
                      style: pw.TextStyle(
                          color: const PdfColor(1, 1, 1, 0.8), fontSize: 9)),
                ],
              ),
            ),
            // Invoice badge
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor(1, 1, 1, 0.2),
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: const PdfColor(1, 1, 1, 0.4)),
                  ),
                  child: pw.Text(
                      invoice.isQuote ? 'QUOTATION' : 'INVOICE',
                      style: pw.TextStyle(color: _white, fontSize: 9,
                          fontWeight: pw.FontWeight.bold, letterSpacing: 2.5)),
                ),
                pw.SizedBox(height: 4),
                pw.Text('#$invNum',
                    style: pw.TextStyle(color: _white, fontSize: 20,
                        fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ],
        ),
      );
    } else {
      // ── Continuation mini-header (pages 2+) ──────────────────────────────
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 10),
        decoration: const pw.BoxDecoration(
          gradient: pw.LinearGradient(
            colors: [_hdrLeft, _hdrRight],
            begin: pw.Alignment.centerLeft,
            end: pw.Alignment.centerRight,
          ),
        ),
        child: pw.Row(
          children: [
            pw.Text('VINEX TECHNOLOGY',
                style: pw.TextStyle(color: _white, fontSize: 13,
                    fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
            pw.Spacer(),
            pw.Text(
              '${invoice.isQuote ? "QUOTATION" : "INVOICE"} #$invNum'
              '  —  Continued (Page ${ctx.pageNumber} / ${ctx.pagesCount})',
              style: pw.TextStyle(
                  color: const PdfColor(1, 1, 1, 0.85), fontSize: 9,
                  fontWeight: pw.FontWeight.bold, letterSpacing: 0.5),
            ),
          ],
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FOOTER  — mirrors _A4Page._buildFooter()
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildFooter(pw.Context ctx) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.8)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Thank you for your business!',
              style: pw.TextStyle(fontSize: 9, color: _grey,
                  fontStyle: pw.FontStyle.italic)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: _mid)),
          pw.Text('VINEX TECHNOLOGY © 2025',
              style: pw.TextStyle(fontSize: 9, color: _blue,
                  fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INFO ROW  — mirrors _A4Page._buildInfoRow()
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildInfoRow(
      Invoice invoice, String invNum, String dateStr) {
    return pw.SizedBox(
      height: _infoRowH,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // BILL TO card
          pw.Expanded(child: _infoCard(
            title: 'BILL TO',
            accent: _blue,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Customer',
                    style: pw.TextStyle(fontSize: 10,
                        fontWeight: pw.FontWeight.bold, color: _mid)),
                pw.SizedBox(height: 4),
                pw.Text(invoice.customerName,
                    style: pw.TextStyle(fontSize: 13,
                        fontWeight: pw.FontWeight.bold, color: _red)),
              ],
            ),
          )),
          pw.SizedBox(width: 14),
          // INVOICE DETAILS card
          pw.Expanded(child: _infoCard(
            title: 'INVOICE DETAILS',
            accent: _green,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _detailRow('Invoice No.', '#$invNum'),
                _detailRow('Date', dateStr),
                _detailRow('Items', '${invoice.items.length} item(s)'),
              ],
            ),
          )),
        ],
      ),
    );
  }

  static pw.Widget _infoCard({
    required String title,
    required PdfColor accent,
    required pw.Widget child,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _white,
        borderRadius: pw.BorderRadius.circular(7),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(6),
                topRight: pw.Radius.circular(6),
              ),
            ),
            child: pw.Text(title,
                style: pw.TextStyle(color: _white, fontSize: 10,
                    fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
          ),
          pw.Padding(padding: const pw.EdgeInsets.all(10), child: child),
        ],
      ),
    );
  }

  static pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(label,
            style: pw.TextStyle(fontSize: 10,
                fontWeight: pw.FontWeight.bold, color: _mid))),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 10,
                fontWeight: pw.FontWeight.bold, color: _red)),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ITEMS TABLE  — mirrors _A4Page._buildItemsTable()
  // Column widths, row height, bold cells, IQD-on-right — all identical.
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildItemsTable(Invoice invoice) {
    const headers   = ['#', 'ITEM NAME', 'QTY', 'UNIT PRICE', 'AMOUNT'];
    final hAligns   = [
      pw.Alignment.center,
      pw.Alignment.centerLeft,
      pw.Alignment.center,
      pw.Alignment.centerRight,
      pw.Alignment.centerRight,
    ];

    // ── Header row ────────────────────────────────────────────────────────
    pw.Widget hdrCell(int i) => pw.Container(
      height: _tableHdrH,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8),
      child: pw.Align(
        alignment: hAligns[i],
        child: pw.Text(headers[i],
            style: pw.TextStyle(color: _white, fontSize: 11,
                fontWeight: pw.FontWeight.bold, letterSpacing: 0.5)),
      ),
    );

    // ── Data rows ─────────────────────────────────────────────────────────
    List<pw.TableRow> dataRows = invoice.items.asMap().entries.map((e) {
      final idx    = e.key;
      final item   = e.value;
      final isEven = idx % 2 == 0;
      final qty    = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(2);
      final cells  = [
        '${idx + 1}',
        item.itemName,
        qty,
        CurrencyHelper.format(item.unitPrice),
        CurrencyHelper.format(item.totalPrice),
      ];

      return pw.TableRow(
        decoration: pw.BoxDecoration(
            color: isEven ? _rowEven : _white),
        children: List.generate(cells.length, (c) => pw.Container(
          height: _tableRowH,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8),
          child: pw.Align(
            alignment: hAligns[c],
            child: pw.Text(cells[c],
                // ← BOLD, exactly matching the Flutter widget
                style: pw.TextStyle(fontSize: 11, color: _dark,
                    fontWeight: pw.FontWeight.bold)),
          ),
        )),
      );
    }).toList();

    // ── Assemble table ────────────────────────────────────────────────────
    const bSide = pw.BorderSide(color: _border, width: 0.6);
    return pw.ClipRRect(
      horizontalRadius: 6, verticalRadius: 6,
      child: pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _border, width: 0.6),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Table(
          columnWidths: {
            0: const pw.FixedColumnWidth(_colW0),  // #
            1: const pw.FlexColumnWidth(1),         // ITEM NAME
            2: const pw.FixedColumnWidth(_colW2),  // QTY
            3: const pw.FixedColumnWidth(_colW3),  // UNIT PRICE
            4: const pw.FixedColumnWidth(_colW4),  // AMOUNT
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          border: const pw.TableBorder(
            verticalInside: bSide,
            horizontalInside: bSide,
          ),
          children: [
            // Header row
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _blue),
              children: List.generate(5, (i) => hdrCell(i)),
            ),
            // Data rows
            ...dataRows,
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TOTALS  — mirrors _A4Page._buildTotalsRow()
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildTotalsRow(Invoice invoice) {
    final hasDiscount = invoice.discount > 0;
    final hasDP       = invoice.hasDownPayment;

    return pw.Row(children: [
      pw.Expanded(child: pw.SizedBox()),
      pw.SizedBox(
        width: 210,  // ~280 Flutter px × 0.75 pt/px
        child: pw.Container(
          decoration: pw.BoxDecoration(
            color: _white,
            borderRadius: pw.BorderRadius.circular(7),
            border: pw.Border.all(color: _border),
          ),
          child: pw.Column(children: [
            if (hasDiscount) ...[
              _totalRow('Subtotal',
                  CurrencyHelper.format(invoice.subtotal), _mid, _dark),
              _totalRow('Discount',
                  '- ${CurrencyHelper.format(invoice.discount)}',
                  _orange, _orange),
              pw.Container(height: 0.8, color: _border),
            ],
            // TOTAL gradient bar
            pw.Container(
              decoration: pw.BoxDecoration(
                gradient: const pw.LinearGradient(
                    colors: [_green, _greenLight],
                    begin: pw.Alignment.centerLeft,
                    end: pw.Alignment.centerRight),
                borderRadius: pw.BorderRadius.only(
                  topLeft:  !hasDiscount
                      ? const pw.Radius.circular(6) : pw.Radius.zero,
                  topRight: !hasDiscount
                      ? const pw.Radius.circular(6) : pw.Radius.zero,
                  bottomLeft:  hasDP
                      ? pw.Radius.zero : const pw.Radius.circular(6),
                  bottomRight: hasDP
                      ? pw.Radius.zero : const pw.Radius.circular(6),
                ),
              ),
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14, vertical: 11),
              child: pw.Row(children: [
                pw.Expanded(child: pw.Text('TOTAL AMOUNT',
                    style: pw.TextStyle(color: _white, fontSize: 11,
                        fontWeight: pw.FontWeight.bold, letterSpacing: 0.6))),
                pw.Text(CurrencyHelper.format(invoice.totalAmount),
                    style: pw.TextStyle(color: _yellow, fontSize: 12,
                        fontWeight: pw.FontWeight.bold)),
              ]),
            ),
            if (hasDP) ...[
              _totalRow('Down Payment',
                  CurrencyHelper.format(invoice.downPayment),
                  _blueLight, _blueLight, bold: true),
              // REMAINING gradient bar
              pw.Container(
                decoration: const pw.BoxDecoration(
                  gradient: pw.LinearGradient(
                      colors: [_blueLight, _blueLighter],
                      begin: pw.Alignment.centerLeft,
                      end: pw.Alignment.centerRight),
                  borderRadius: pw.BorderRadius.only(
                    bottomLeft:  pw.Radius.circular(6),
                    bottomRight: pw.Radius.circular(6),
                  ),
                ),
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                child: pw.Row(children: [
                  pw.Expanded(child: pw.Text('Remaining Amount',
                      style: pw.TextStyle(color: _white, fontSize: 11,
                          fontWeight: pw.FontWeight.bold, letterSpacing: 0.5))),
                  pw.Text(CurrencyHelper.format(invoice.remainingAmount),
                      style: pw.TextStyle(color: _yellow, fontSize: 12,
                          fontWeight: pw.FontWeight.bold)),
                ]),
              ),
            ],
          ]),
        ),
      ),
    ]);
  }

  static pw.Widget _totalRow(
      String label, String value,
      PdfColor labelColor, PdfColor valueColor,
      {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(label,
            style: pw.TextStyle(fontSize: 10, color: labelColor,
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 11, color: valueColor,
                fontWeight: pw.FontWeight.bold)),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NOTES  — mirrors _A4Page._buildNotes()
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildNotes(String notes) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: _notesBg,
        borderRadius: pw.BorderRadius.circular(7),
        border: pw.Border.all(color: _notesBdr),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('NOTES',
              style: pw.TextStyle(fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _brown, letterSpacing: 1)),
          pw.SizedBox(height: 5),
          pw.Text(notes,
              style: pw.TextStyle(fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _dark, lineSpacing: 2)),
        ],
      ),
    );
  }
}
