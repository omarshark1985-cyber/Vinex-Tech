import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/invoice_model.dart';
import '../models/invoice_item_model.dart';
import '../utils/currency_helper.dart';

// ══════════════════════════════════════════════════════════════════════════════
// InvoicePdfGenerator
//
// SINGLE SOURCE OF TRUTH for all layout values.
// Every constant below is derived from the Flutter preview widget constants
// (invoice_detail_screen.dart) via:
//
//   pdf_pt = flutter_px × (595 / 794)      ← A4 width: 595pt = 794px @ 96dpi
//
// This guarantees the PDF output is a pixel-perfect mirror of the on-screen
// preview — same proportions, same colours, same column widths, same bold.
// ══════════════════════════════════════════════════════════════════════════════
class InvoicePdfGenerator {

  // ── Conversion factor (A4: 595pt wide / 794px wide) ──────────────────────
  static const double _s = 595 / 794; // ≈ 0.7494

  // ── Layout constants (all in PDF points, derived from Flutter px × _s) ───
  // Header / cont-header
  static const double _hdrPadH     = 32 * _s;  // 24.0 pt
  static const double _hdrPadV     = 18 * _s;  // 13.5 pt
  static const double _contHdrPadV = 10 * _s;  //  7.5 pt
  static const double _logoSize    = 50 * _s;  // 37.5 pt

  // Footer
  static const double _ftPadH = 32 * _s;  // 24.0 pt
  static const double _ftPadV = 10 * _s;  //  7.5 pt

  // Body padding
  static const double _bdPadH   = 32 * _s;  // 24.0 pt
  static const double _bdPadTop = 20 * _s;  // 15.0 pt
  static const double _bdPadBot = 20 * _s;  // 15.0 pt

  // Info cards
  static const double _infoH         = 90 * _s;  // 67.5 pt (card height)
  static const double _infoGap        = 14 * _s;  // 10.5 pt (gap between cards)
  static const double _infoTitlePadH  = 11 * _s;  //  8.2 pt
  static const double _infoTitlePadV  =  7 * _s;  //  5.2 pt
  static const double _infoBodyPad    = 10 * _s;  //  7.5 pt

  // Items table
  static const double _tblHdrH  = 36 * _s;   // 27.0 pt  (header row height)
  static const double _tblRowH  = 37 * _s;   // 27.7 pt  (data row height)
  static const double _tblPadH  =  8 * _s;   //  6.0 pt  (cell horizontal padding)
  static const double _col0     = 40 * _s;   // 30.0 pt  (#)
  static const double _col2     = 55 * _s;   // 41.2 pt  (QTY)
  static const double _col3     = 125 * _s;  // 93.7 pt  (UNIT PRICE)
  static const double _col4     = 125 * _s;  // 93.7 pt  (AMOUNT)

  // Totals block
  static const double _totW        = 280 * _s;  // 209.8 pt
  static const double _totPadH     = 14  * _s;  //  10.5 pt
  static const double _totPadV     =  8  * _s;  //   6.0 pt
  static const double _totBarPadH  = 14  * _s;  //  10.5 pt
  static const double _totBarPadV  = 11  * _s;  //   8.2 pt

  // Notes
  static const double _notesPad = 12 * _s;  //  9.0 pt

  // Gaps between sections
  static const double _sectionGap = 20 * _s;  // 15.0 pt

  // ── Colors (identical hex to _pv* constants in invoice_detail_screen.dart) ─
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

  // ── Public entry points ───────────────────────────────────────────────────
  static Future<pw.Document> buildDocument(Invoice invoice) async {
    pw.MemoryImage? logo;
    try {
      final data = await rootBundle.load('assets/images/company_logo.png');
      logo = pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {}

    final invNum  = invoice.invoiceNumber.toString().padLeft(4, '0');
    final dateStr = DateFormat('MMMM dd, yyyy').format(invoice.invoiceDate);

    final pdf = pw.Document(compress: true);

    // ── Hard cap: max 16 rows per page (mirrors Flutter _maxRowsPerPage) ────
    const int maxRows = 16;
    final allItems = invoice.items;

    // Chunk items into pages of ≤ maxRows.
    // The LAST chunk always includes totals + notes (kept together).
    // We determine how many rows belong to the "tail" chunk:
    //   – if total items ≤ maxRows → 1 chunk (all items + totals on page 1)
    //   – otherwise → head chunks of maxRows + tail chunk of remainder (≥1, ≤maxRows)
    // Orphan guard: tail chunk must have ≥ 2 rows unless there's only 1 item total.
    List<List<InvoiceItem>> chunks = [];
    int start = 0;
    while (start < allItems.length) {
      final end = (start + maxRows).clamp(0, allItems.length);
      chunks.add(allItems.sublist(start, end));
      start = end;
    }
    if (chunks.isEmpty) chunks.add([]);

    // Orphan-totals guard for PDF (same logic as Flutter _paginate):
    // ensure last chunk has ≥ 2 items so totals is never visually alone.
    while (chunks.length >= 2 &&
        chunks.last.length < 2 &&
        chunks[chunks.length - 2].length > 1) {
      final prev   = List<InvoiceItem>.from(chunks[chunks.length - 2]);
      final stolen = prev.removeLast();
      chunks[chunks.length - 2] = prev;
      chunks[chunks.length - 1] = [stolen, ...chunks.last];
    }

    // Head chunks: rendered as SpanningWidget tables (MultiPage can still
    // reflow them, but each chunk already fits ≤ maxRows so no splitting occurs).
    // Tail chunk: wrapped in pw.Container (non-spanning) to keep it together
    // with the totals + notes block on the same page.
    final headChunks = chunks.length > 1 ? chunks.sublist(0, chunks.length - 1) : <List<InvoiceItem>>[];
    final tailChunk  = chunks.last;

    // Build the list of widgets for MultiPage.build
    final List<pw.Widget> buildWidgets = [];

    // Info row (page 1 only)
    buildWidgets.add(pw.Padding(
      padding: pw.EdgeInsets.fromLTRB(_bdPadH, _bdPadTop, _bdPadH, 0),
      child: _buildInfoRow(invoice, invNum, dateStr),
    ));
    buildWidgets.add(pw.SizedBox(height: _sectionGap));

    // Head chunks — each preceded by a NewPage (except first) + info cards repeat
    int globalOffset = 0;
    for (int i = 0; i < headChunks.length; i++) {
      final chunk = headChunks[i];
      if (i > 0) {
        buildWidgets.add(pw.NewPage());
        // Repeat BILL TO + INVOICE DETAILS at top of every continuation page
        buildWidgets.add(pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(_bdPadH, _bdPadTop, _bdPadH, 0),
          child: _buildInfoRow(invoice, invNum, dateStr),
        ));
        buildWidgets.add(pw.SizedBox(height: _sectionGap));
      }
      buildWidgets.add(pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: _bdPadH),
        child: _buildItemsTable(chunk,
            isHead: true, globalOffset: globalOffset),
      ));
      globalOffset += chunk.length;
    }

    // Tail chunk + totals + notes — in a pw.Container so MultiPage won't split
    if (headChunks.isNotEmpty) {
      buildWidgets.add(pw.NewPage());
      // Repeat BILL TO + INVOICE DETAILS on last page too
      buildWidgets.add(pw.Padding(
        padding: pw.EdgeInsets.fromLTRB(_bdPadH, _bdPadTop, _bdPadH, 0),
        child: _buildInfoRow(invoice, invNum, dateStr),
      ));
      buildWidgets.add(pw.SizedBox(height: _sectionGap));
    }
    buildWidgets.add(pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: _bdPadH),
      child: pw.Container(
        child: pw.Column(children: [
          _buildItemsTable(tailChunk,
              isHead: true, globalOffset: globalOffset),
          pw.SizedBox(height: 16 * _s),
          _buildTotalsRow(invoice),
          if (invoice.notes.isNotEmpty) ...[
            pw.SizedBox(height: 12 * _s),
            _buildNotes(invoice.notes),
          ],
        ]),
      ),
    ));
    buildWidgets.add(pw.SizedBox(height: _bdPadBot));

    pdf.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        buildBackground: (_) => pw.Container(color: _white),
      ),
      header: (ctx) => _buildHeader(logo, invNum, dateStr, invoice, ctx),
      footer: (ctx) => _buildFooter(ctx),
      build:  (_) => buildWidgets,
    ));
    return pdf;
  }

  static Future<List<int>> generate(Invoice invoice) async =>
      (await buildDocument(invoice)).save();

  // ══════════════════════════════════════════════════════════════════════════
  // HEADER  (page 1 = full, pages 2+ = mini continuation)
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildHeader(pw.MemoryImage? logo, String invNum,
      String dateStr, Invoice invoice, pw.Context ctx) {
    final gradient = const pw.BoxDecoration(
      gradient: pw.LinearGradient(
        colors: [_hdrLeft, _hdrRight],
        begin: pw.Alignment.centerLeft,
        end: pw.Alignment.centerRight,
      ),
    );

    if (ctx.pageNumber == 1) {
      // ── Full header ──────────────────────────────────────────────────────
      return pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.symmetric(
            horizontal: _hdrPadH, vertical: _hdrPadV),
        decoration: gradient,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Logo box
            pw.Container(
              width: _logoSize, height: _logoSize,
              decoration: pw.BoxDecoration(
                color: const PdfColor(1, 1, 1, 0.15),
                borderRadius: pw.BorderRadius.circular(9 * _s),
                border: pw.Border.all(color: const PdfColor(1, 1, 1, 0.3)),
              ),
              child: logo != null
                  ? pw.ClipRRect(
                      horizontalRadius: 8 * _s, verticalRadius: 8 * _s,
                      child: pw.Image(logo, fit: pw.BoxFit.contain))
                  : pw.Center(child: pw.Text('VT',
                      style: pw.TextStyle(color: _white, fontSize: 17,
                          fontWeight: pw.FontWeight.bold))),
            ),
            pw.SizedBox(width: 14 * _s),
            // Company name + address
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('VINEX TECHNOLOGY',
                    style: pw.TextStyle(color: _white, fontSize: 17,
                        fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
                pw.SizedBox(height: 4 * _s),
                pw.Text(
                    'Baghdad, Yarmouk — Al-Fakhri 2 Building  |  07803662728',
                    style: pw.TextStyle(
                        color: const PdfColor(1, 1, 1, 0.8), fontSize: 9)),
              ],
            )),
            // Invoice badge
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Container(
                padding: pw.EdgeInsets.symmetric(
                    horizontal: 10 * _s, vertical: 3 * _s),
                decoration: pw.BoxDecoration(
                  color: const PdfColor(1, 1, 1, 0.2),
                  borderRadius: pw.BorderRadius.circular(4 * _s),
                  border: pw.Border.all(color: const PdfColor(1, 1, 1, 0.4)),
                ),
                child: pw.Text(invoice.isQuote ? 'QUOTATION' : 'INVOICE',
                    style: pw.TextStyle(color: _white, fontSize: 9,
                        fontWeight: pw.FontWeight.bold, letterSpacing: 2.5)),
              ),
              pw.SizedBox(height: 4 * _s),
              pw.Text('#$invNum',
                  style: pw.TextStyle(color: _white, fontSize: 20,
                      fontWeight: pw.FontWeight.bold)),
            ]),
          ],
        ),
      );
    } else {
      // ── Mini continuation header (with repeated invoice info) ─────────────
      return pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.symmetric(
            horizontal: _hdrPadH, vertical: _contHdrPadV),
        decoration: gradient,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Row 1: company name + page indicator
            pw.Row(children: [
              pw.Text('VINEX TECHNOLOGY',
                  style: pw.TextStyle(color: _white, fontSize: 12,
                      fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
              pw.Spacer(),
              pw.Text(
                '${invoice.isQuote ? "QUOTATION" : "INVOICE"} #$invNum'
                '  —  Continued (Page ${ctx.pageNumber} / ${ctx.pagesCount})',
                style: pw.TextStyle(
                    color: const PdfColor(1, 1, 1, 0.85), fontSize: 8,
                    fontWeight: pw.FontWeight.bold, letterSpacing: 0.5),
              ),
            ]),
            pw.SizedBox(height: 5 * _s),
            // Row 2: customer name | invoice # | date | items count
            pw.Container(
              padding: pw.EdgeInsets.symmetric(
                  horizontal: 8 * _s, vertical: 4 * _s),
              decoration: pw.BoxDecoration(
                color: const PdfColor(1, 1, 1, 0.12),
                borderRadius: pw.BorderRadius.circular(4 * _s),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _contInfoCell('Customer', invoice.customerName),
                  _contDivider(),
                  _contInfoCell('Invoice No.', '#$invNum'),
                  _contDivider(),
                  _contInfoCell('Date', dateStr),
                  _contDivider(),
                  _contInfoCell('Items', '${invoice.items.length} item(s)'),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FOOTER
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildFooter(pw.Context ctx) {
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.symmetric(
          horizontal: _ftPadH, vertical: _ftPadV),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            top: pw.BorderSide(color: _border, width: 0.8)),
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
  // INFO ROW  (BILL TO card + INVOICE DETAILS card)
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildInfoRow(
      Invoice invoice, String invNum, String dateStr) {
    return pw.SizedBox(
      height: _infoH,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // BILL TO
          pw.Expanded(child: _infoCard(
            title: 'BILL TO', accent: _blue,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Customer',
                    style: pw.TextStyle(fontSize: 10,
                        fontWeight: pw.FontWeight.bold, color: _mid)),
                pw.SizedBox(height: 4 * _s),
                pw.Text(invoice.customerName,
                    style: pw.TextStyle(fontSize: 13,
                        fontWeight: pw.FontWeight.bold, color: _red)),
              ],
            ),
          )),
          pw.SizedBox(width: _infoGap),
          // INVOICE DETAILS
          pw.Expanded(child: _infoCard(
            title: 'INVOICE DETAILS', accent: _green,
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
        borderRadius: pw.BorderRadius.circular(7 * _s),
        border: pw.Border.all(color: _border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
                horizontal: _infoTitlePadH, vertical: _infoTitlePadV),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.only(
                topLeft:  pw.Radius.circular(6 * _s),
                topRight: pw.Radius.circular(6 * _s),
              ),
            ),
            child: pw.Text(title,
                style: pw.TextStyle(color: _white, fontSize: 10,
                    fontWeight: pw.FontWeight.bold, letterSpacing: 1.2)),
          ),
          pw.Padding(
            padding: pw.EdgeInsets.all(_infoBodyPad),
            child: child,
          ),
        ],
      ),
    );
  }

  static pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 4 * _s),
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
  // ITEMS TABLE  — exact column widths, row heights, bold cells, IQD-suffix
  // [items]        — subset of items to render (head or tail slice)
  // [isHead]       — true  → include the blue header row
  //                  false → omit header row (continuation slice)
  // [globalOffset] — row-number offset so "#" column continues correctly
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildItemsTable(
    List<InvoiceItem> items, {
    bool isHead = true,
    int  globalOffset = 0,
  }) {
    const headers  = ['#', 'ITEM NAME', 'QTY', 'UNIT PRICE', 'AMOUNT'];
    final hAligns  = [
      pw.Alignment.center,
      pw.Alignment.centerLeft,
      pw.Alignment.center,
      pw.Alignment.centerRight,
      pw.Alignment.centerRight,
    ];

    // ── Header row ────────────────────────────────────────────────────────
    pw.Widget hdrCell(int i) => pw.Container(
      height: _tblHdrH,
      padding: pw.EdgeInsets.symmetric(horizontal: _tblPadH),
      child: pw.Align(
        alignment: hAligns[i],
        child: pw.Text(headers[i],
            style: pw.TextStyle(color: _white, fontSize: 9,
                fontWeight: pw.FontWeight.bold, letterSpacing: 0.5)),
      ),
    );

    // ── Data rows ─────────────────────────────────────────────────────────
    final dataRows = items.asMap().entries.map((e) {
      final idx    = e.key;
      final item   = e.value;
      // Global row index for alternating color and # number
      final gIdx   = globalOffset + idx;
      final isEven = gIdx % 2 == 0;
      final qty    = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(2);
      final cells  = [
        '${gIdx + 1}',
        item.itemName,
        qty,
        CurrencyHelper.format(item.unitPrice),
        CurrencyHelper.format(item.totalPrice),
      ];
      return pw.TableRow(
        decoration: pw.BoxDecoration(color: isEven ? _rowEven : _white),
        children: List.generate(cells.length, (c) => pw.Container(
          height: _tblRowH,
          padding: pw.EdgeInsets.symmetric(horizontal: _tblPadH),
          child: pw.Align(
            alignment: hAligns[c],
            child: pw.Text(cells[c],
                style: pw.TextStyle(fontSize: 9, color: _dark)),
          ),
        )),
      );
    }).toList();

    const bSide = pw.BorderSide(color: _border, width: 0.6);
    return pw.ClipRRect(
      horizontalRadius: 6 * _s, verticalRadius: 6 * _s,
      child: pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _border, width: 0.6),
          borderRadius: pw.BorderRadius.circular(6 * _s),
        ),
        child: pw.Table(
          columnWidths: {
            0: pw.FixedColumnWidth(_col0),   // #
            1: const pw.FlexColumnWidth(1),  // ITEM NAME
            2: pw.FixedColumnWidth(_col2),   // QTY
            3: pw.FixedColumnWidth(_col3),   // UNIT PRICE
            4: pw.FixedColumnWidth(_col4),   // AMOUNT
          },
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          border: const pw.TableBorder(
            verticalInside:   bSide,
            horizontalInside: bSide,
          ),
          children: [
            if (isHead)
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _blue),
                children: List.generate(5, hdrCell),
              ),
            ...dataRows,
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TOTALS BLOCK
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildTotalsRow(Invoice invoice) {
    final hasDiscount = invoice.discount > 0;
    final hasDP       = invoice.hasDownPayment;

    return pw.Row(children: [
      pw.Expanded(child: pw.SizedBox()),
      pw.SizedBox(
        width: _totW,
        child: pw.Container(
          decoration: pw.BoxDecoration(
            color: _white,
            borderRadius: pw.BorderRadius.circular(7 * _s),
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
                  topLeft:     !hasDiscount
                      ? pw.Radius.circular(6 * _s) : pw.Radius.zero,
                  topRight:    !hasDiscount
                      ? pw.Radius.circular(6 * _s) : pw.Radius.zero,
                  bottomLeft:  hasDP
                      ? pw.Radius.zero : pw.Radius.circular(6 * _s),
                  bottomRight: hasDP
                      ? pw.Radius.zero : pw.Radius.circular(6 * _s),
                ),
              ),
              padding: pw.EdgeInsets.symmetric(
                  horizontal: _totBarPadH, vertical: _totBarPadV),
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
                decoration: pw.BoxDecoration(
                  gradient: const pw.LinearGradient(
                      colors: [_blueLight, _blueLighter],
                      begin: pw.Alignment.centerLeft,
                      end: pw.Alignment.centerRight),
                  borderRadius: pw.BorderRadius.only(
                    bottomLeft:  pw.Radius.circular(6 * _s),
                    bottomRight: pw.Radius.circular(6 * _s),
                  ),
                ),
                padding: pw.EdgeInsets.symmetric(
                    horizontal: _totBarPadH, vertical: _totBarPadV),
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
      padding: pw.EdgeInsets.symmetric(
          horizontal: _totPadH, vertical: _totPadV),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(label,
            style: pw.TextStyle(fontSize: 9, color: labelColor,
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
        pw.Text(value,
            style: pw.TextStyle(fontSize: 10, color: valueColor,
                fontWeight: pw.FontWeight.bold)),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NOTES
  // ══════════════════════════════════════════════════════════════════════════
  static pw.Widget _buildNotes(String notes) {
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.all(_notesPad),
      decoration: pw.BoxDecoration(
        color: _notesBg,
        borderRadius: pw.BorderRadius.circular(7 * _s),
        border: pw.Border.all(color: _notesBdr),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('NOTES',
              style: pw.TextStyle(fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _brown, letterSpacing: 1)),
          pw.SizedBox(height: 5 * _s),
          pw.Text(notes,
              style: pw.TextStyle(fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _dark, lineSpacing: 2)),
        ],
      ),
    );
  }

  // ── Helpers for continuation header info bar ──────────────────────────────
  // A small two-line cell: grey label on top, white value below
  static pw.Widget _contInfoCell(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: pw.TextStyle(
                fontSize: 7,
                color: const PdfColor(1, 1, 1, 0.65),
                letterSpacing: 0.3)),
        pw.SizedBox(height: 1.5),
        pw.Text(value,
            style: pw.TextStyle(
                fontSize: 8,
                color: _white,
                fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  // Thin vertical separator between info cells
  static pw.Widget _contDivider() {
    return pw.Container(
      width: 0.6,
      height: 24 * _s,
      margin: pw.EdgeInsets.symmetric(horizontal: 8 * _s),
      color: const PdfColor(1, 1, 1, 0.3),
    );
  }
}
