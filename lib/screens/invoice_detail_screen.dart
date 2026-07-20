import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';
import 'dart:convert' show base64Encode;
import 'package:printing/printing.dart';
import '../utils/js_helper.dart';
import '../utils/responsive.dart';
import '../models/invoice_model.dart';
import '../models/invoice_item_model.dart';
import '../models/inventory_model.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_helper.dart';
import '../utils/invoice_pdf_generator.dart';


// ══════════════════════════════════════════════════════════════════════════════
// INVOICE DETAIL SCREEN  (View + Print + Delete)
// ══════════════════════════════════════════════════════════════════════════════
class InvoiceDetailScreen extends StatefulWidget {
  final Invoice invoice;
  const InvoiceDetailScreen({super.key, required this.invoice});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  bool _deleting = false;
  bool _converting = false;
  late Invoice _invoice;

  @override
  void initState() {
    super.initState();
    _invoice = widget.invoice;
  }

  // ── تحويل فاتورة العرض إلى بيع ────────────────────────────────────────────
  Future<void> _convertToSale(BuildContext context) async {
    setState(() => _converting = true);
    final error = await DatabaseService.convertQuoteToSale(_invoice);
    if (!mounted) return;
    setState(() => _converting = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } else {
      setState(() => _invoice = Invoice(
        id: _invoice.id, invoiceNumber: _invoice.invoiceNumber,
        customerName: _invoice.customerName, invoiceDate: _invoice.invoiceDate,
        items: _invoice.items, notes: _invoice.notes,
        discount: _invoice.discount, totalAmount: _invoice.totalAmount,
        invoiceType: 'sale',
      ));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('✅ تم تحويل الفاتورة إلى فاتورة بيع بنجاح'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _printInvoice(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePrintScreen(invoice: _invoice),
      ),
    );
  }

  void _openEdit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceEditScreen(invoice: _invoice),
      ),
    ).then((updatedInvoice) {
      if (updatedInvoice is Invoice && mounted) {
        setState(() => _invoice = updatedInvoice);
      }
    });
  }

  // ── Delete Confirmation — native screen ────────────────────────────────────
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DetailDeleteDialog(
          invoice: _invoice,
          onConfirmed: () async {
            setState(() => _deleting = true);
            await DatabaseService.deleteInvoice(_invoice.id);
            DatabaseService.refreshData();
            if (mounted) {
              setState(() => _deleting = false);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ تم حذف الفاتورة #${_invoice.invoiceNumber} وإعادة المواد للمخزن'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: _invoice.isQuote
                ? const Color(0xFF7B5EA7)
                : AppTheme.salesColor,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Invoice #${_invoice.invoiceNumber.toString().padLeft(4, '0')}'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _invoice.isQuote ? 'عرض' : 'بيع',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            actions: [
              // زر تحويل العرض إلى بيع
              if (_invoice.isQuote)
                _converting
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                    : IconButton(
                        icon: const Icon(Icons.swap_horiz_rounded),
                        tooltip: 'تحويل إلى فاتورة بيع',
                        onPressed: () => _convertToSale(context),
                      ),
              // Edit button
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                tooltip: 'Edit Invoice',
                onPressed: () => _openEdit(context),
              ),
              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_forever_rounded),
                tooltip: 'حذف الفاتورة',
                onPressed: () => _confirmDelete(context),
                style: IconButton.styleFrom(foregroundColor: Colors.red[100]),
              ),
              // Print button — متاح لكلا النوعين (بيع وعرض)
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded),
                tooltip: _invoice.isQuote ? 'عرض ومعاينة عرض السعر' : 'Print View (A4)',
                onPressed: () => _printInvoice(context),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Builder(
            builder: (context) {
              final r = R.of(context);
              return SingleChildScrollView(
                padding: EdgeInsets.all(r.hPad),
                child: Column(
                  children: [
                    // ── Invoice Document ──────────────────────────────────────
                    _InvoiceDocument(invoice: _invoice),
                    SizedBox(height: r.gap),
                  ],
                ),
              );
            },
          ),
        ),
        // Loading overlay while deleting
        if (_deleting || _converting)
          Container(
            color: Colors.black26,
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _converting
                            ? 'جاري تحويل الفاتورة إلى بيع\nوخصم المواد من المخزن...'
                            : 'جاري حذف الفاتورة\nوإعادة المواد للمخزن...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// INVOICE PRINT SCREEN  – A4 web page for browser print/save as PDF
// ══════════════════════════════════════════════════════════════════════════════
class InvoicePrintScreen extends StatefulWidget {
  final Invoice invoice;
  const InvoicePrintScreen({super.key, required this.invoice});

  @override
  State<InvoicePrintScreen> createState() => _InvoicePrintScreenState();
}

class _InvoicePrintScreenState extends State<InvoicePrintScreen> {
  bool _exporting = false;

  Color get _accentColor => widget.invoice.isQuote
      ? const Color(0xFF7B5EA7)
      : AppTheme.primaryBlueDark;

  String get _invNum =>
      widget.invoice.invoiceNumber.toString().padLeft(4, '0');

  // ── Export PDF ──────────────────────────────────────────────────────────────
  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await InvoicePdfGenerator.generate(widget.invoice);
      final fileName = 'Invoice_$_invNum.pdf';
      if (kIsWeb) {
        final b64 = base64Encode(Uint8List.fromList(bytes));
        evalJs("""
          (function(){
            var b64='$b64';
            var bin=atob(b64); var len=bin.length;
            var buf=new ArrayBuffer(len); var arr=new Uint8Array(buf);
            for(var i=0;i<len;i++){ arr[i]=bin.charCodeAt(i); }
            var blob=new Blob([arr],{type:'application/pdf'});
            var url=URL.createObjectURL(blob);
            var a=document.createElement('a');
            a.href=url; a.download='$fileName';
            document.body.appendChild(a); a.click();
            setTimeout(function(){URL.revokeObjectURL(url);document.body.removeChild(a);},2000);
          })();
        """);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Downloading $fileName'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 3),
        ));
      } else {
        await Printing.sharePdf(
            bytes: Uint8List.fromList(bytes), filename: fileName);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('exportPdf error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Export failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Print (mobile only) ─────────────────────────────────────────────────────
  Future<void> _printPdf() async {
    try {
      await Printing.layoutPdf(
        onLayout: (_) => InvoicePdfGenerator.generate(widget.invoice)
            .then((list) => Uint8List.fromList(list)),
        name: 'Invoice_$_invNum',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('print error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('❌ Print failed: $e'), backgroundColor: Colors.red));
    }
  }

  List<Widget> _buildActions() => [
    if (!kIsWeb)
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: TextButton.icon(
          onPressed: _printPdf,
          icon: const Icon(Icons.print_rounded, size: 18, color: Colors.white),
          label: const Text('Print',
              style: TextStyle(color: Colors.white, fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ElevatedButton.icon(
        onPressed: _exporting ? null : _exportPdf,
        icon: _exporting
            ? const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.picture_as_pdf_rounded, size: 16),
        label: Text(_exporting ? 'Exporting…' : 'Export PDF',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.invoice.isQuote
              ? const Color(0xFF4A148C) : const Color(0xFFB71C1C),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final invNum  = _invNum;
    final dateStr = DateFormat('MMMM dd, yyyy').format(widget.invoice.invoiceDate);
    return Scaffold(
      backgroundColor: const Color(0xFFCFD8DC),
      appBar: AppBar(
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.invoice.isQuote
              ? 'Preview Quotation  #$invNum'
              : 'Preview Invoice  #$invNum',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        actions: _buildActions(),
      ),
      // ── Body: Flutter-widget preview (identical layout to the PDF) ──────────
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: _InvoicePreviewWidget(
              invoice: widget.invoice,
              invNum: invNum,
              dateStr: dateStr,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// INVOICE DOCUMENT WIDGET  (shared between view & print)
// ══════════════════════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════════════════════
// INVOICE PREVIEW WIDGET
// Pure Flutter widget that exactly mirrors the pw.MultiPage PDF layout.
// Used as the web preview body (no rasterization needed — instant, crisp).
// ══════════════════════════════════════════════════════════════════════════════

// ── Color constants matching InvoicePdfGenerator ─────────────────────────────
const Color _pvHdrLeft    = Color(0xFF1E3A5F);
const Color _pvHdrRight   = Color(0xFF1B5E20);
const Color _pvBlue       = Color(0xFF2563EB);
const Color _pvGreen      = Color(0xFF2E7D32);
const Color _pvGreenLight = Color(0xFF43A047);
const Color _pvBlueLight  = Color(0xFF1A65C0);
const Color _pvBlueLighter= Color(0xFF1F80E6);
const Color _pvRed        = Color(0xFFCC0000);
const Color _pvDark       = Color(0xFF1A1A1A);
const Color _pvMid        = Color(0xFF555555);
const Color _pvBorder     = Color(0xFFE0E0E0);
const Color _pvRowEven    = Color(0xFFF0F4FF);
const Color _pvNotesBg    = Color(0xFFFFFDE7);
const Color _pvNotesBdr   = Color(0xFFFFECB3);
const Color _pvGrey       = Color(0xFF94A3B8);
const Color _pvYellow     = Color(0xFFFFFF00);
const Color _pvOrange     = Color(0xFFE65100);
const Color _pvBrown      = Color(0xFF795548);

class _InvoicePreviewWidget extends StatelessWidget {
  final Invoice invoice;
  final String invNum;
  final String dateStr;

  const _InvoicePreviewWidget({
    required this.invoice,
    required this.invNum,
    required this.dateStr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER ─────────────────────────────────────────────────────────
          _buildHeader(context),
          // ── BODY ───────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info row
                _buildInfoRow(),
                const SizedBox(height: 20),
                // Items table
                _buildItemsTable(),
                const SizedBox(height: 16),
                // Totals
                _buildTotalsRow(),
                // Notes
                if (invoice.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildNotes(),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
          // ── FOOTER ─────────────────────────────────────────────────────────
          _buildFooter(),
        ],
      ),
    );
  }

  // ── HEADER ──────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_pvHdrLeft, _pvHdrRight],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Logo
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/company_logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(
                  child: Text('VT', style: TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Company info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('VINEX TECHNOLOGY',
                    style: TextStyle(
                      color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.bold, letterSpacing: 2,
                    )),
                const SizedBox(height: 5),
                Text(
                  'Baghdad, Yarmouk — Al-Fakhri 2 Building  |  📞 07803662728',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8), fontSize: 9),
                ),
              ],
            ),
          ),
          // Invoice badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                ),
                child: Text(
                  invoice.isQuote ? 'QUOTATION' : 'INVOICE',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.bold, letterSpacing: 2.5),
                ),
              ),
              const SizedBox(height: 4),
              Text('#$invNum',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 20,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  // ── FOOTER ──────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _pvBorder, width: 0.8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Thank you for your business!',
              style: TextStyle(fontSize: 10, color: _pvGrey,
                  fontStyle: FontStyle.italic)),
          const Text('VINEX TECHNOLOGY © 2025',
              style: TextStyle(fontSize: 10, color: _pvBlue,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── INFO ROW ────────────────────────────────────────────────────────────────
  Widget _buildInfoRow() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // BILL TO
          Expanded(child: _infoCard(
            title: 'BILL TO',
            accent: _pvBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Customer', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold,
                    color: _pvMid)),
                const SizedBox(height: 5),
                Text(invoice.customerName, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold,
                    color: _pvRed)),
              ],
            ),
          )),
          const SizedBox(width: 14),
          // INVOICE DETAILS
          Expanded(child: _infoCard(
            title: 'INVOICE DETAILS',
            accent: _pvGreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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

  Widget _infoCard({
    required String title,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _pvBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Text(title, style: const TextStyle(
                color: Colors.white, fontSize: 10,
                fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          Padding(padding: const EdgeInsets.all(11), child: child),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: _pvMid))),
        Text(value, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: _pvRed)),
      ]),
    );
  }

  // ── ITEMS TABLE ─────────────────────────────────────────────────────────────
  Widget _buildItemsTable() {
    const headers = ['#', 'ITEM NAME', 'QTY', 'UNIT PRICE', 'AMOUNT'];
    const aligns  = [
      TextAlign.center,
      TextAlign.left,
      TextAlign.center,
      TextAlign.right,
      TextAlign.right,
    ];
    const borderSide = BorderSide(color: _pvBorder, width: 0.6);

    // ── Header row cells ──────────────────────────────────────────────────────
    List<Widget> headerCells = List.generate(headers.length, (i) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      child: Text(
        headers[i],
        textAlign: aligns[i],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    ));

    // ── Data rows ─────────────────────────────────────────────────────────────
    List<TableRow> dataRows = invoice.items.asMap().entries.map((e) {
      final item = e.value;
      final isEven = e.key % 2 == 0; // even index → light-blue tint
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(2);
      final cells = [
        '${e.key + 1}',
        item.itemName,
        qty,
        CurrencyHelper.format(item.unitPrice),
        CurrencyHelper.format(item.totalPrice),
      ];

      return TableRow(
        decoration: BoxDecoration(
          color: isEven ? _pvRowEven : Colors.white,
        ),
        children: List.generate(cells.length, (c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Text(
            cells[c],
            textAlign: aligns[c],
            style: const TextStyle(fontSize: 11, color: _pvDark),
          ),
        )),
      );
    }).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: _pvBorder, width: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Table(
          // ── Column widths ────────────────────────────────────────────────
          // #: fixed 40px | Item Name: flex (takes remaining space)
          // QTY: fixed 55px | Unit Price: fixed 125px | Amount: fixed 125px
          columnWidths: const {
            0: FixedColumnWidth(40),
            1: FlexColumnWidth(1),
            2: FixedColumnWidth(55),
            3: FixedColumnWidth(125),
            4: FixedColumnWidth(125),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(
            verticalInside: borderSide,
            horizontalInside: borderSide,
          ),
          children: [
            // ── Header ──────────────────────────────────────────────────────
            TableRow(
              decoration: const BoxDecoration(color: _pvBlue),
              children: headerCells,
            ),
            // ── Data rows ───────────────────────────────────────────────────
            ...dataRows,
          ],
        ),
      ),
    );
  }


  // ── TOTALS ──────────────────────────────────────────────────────────────────
  Widget _buildTotalsRow() {
    final hasDiscount = invoice.discount > 0;
    final hasDP       = invoice.hasDownPayment;

    return Row(children: [
      const Spacer(),
      SizedBox(
        width: 260,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _pvBorder),
          ),
          child: Column(children: [
            if (hasDiscount) ...[
              _totalRow('Subtotal',
                  CurrencyHelper.format(invoice.subtotal),
                  _pvMid, _pvDark),
              _totalRow('Discount',
                  '− ${CurrencyHelper.format(invoice.discount)}',
                  _pvOrange, _pvOrange),
              Container(height: 0.8, color: _pvBorder),
            ],
            // TOTAL gradient bar
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_pvGreen, _pvGreenLight],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft:     !hasDiscount ? const Radius.circular(6) : Radius.zero,
                  topRight:    !hasDiscount ? const Radius.circular(6) : Radius.zero,
                  bottomLeft:  hasDP ? Radius.zero : const Radius.circular(6),
                  bottomRight: hasDP ? Radius.zero : const Radius.circular(6),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                const Expanded(child: Text('TOTAL AMOUNT',
                    style: TextStyle(color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.bold, letterSpacing: 0.6))),
                Text(CurrencyHelper.format(invoice.totalAmount),
                    style: const TextStyle(color: _pvYellow, fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
            if (hasDP) ...[
              _totalRow('Down Payment',
                  CurrencyHelper.format(invoice.downPayment),
                  _pvBlueLight, _pvBlueLight, bold: true),
              // Remaining gradient bar
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_pvBlueLight, _pvBlueLighter],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(children: [
                  const Expanded(child: Text('Remaining Amount',
                      style: TextStyle(color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.bold, letterSpacing: 0.5))),
                  Text(CurrencyHelper.format(invoice.remainingAmount),
                      style: const TextStyle(color: _pvYellow, fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ],
          ]),
        ),
      ),
    ]);
  }

  Widget _totalRow(String label, String value,
      Color labelColor, Color valueColor, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 10, color: labelColor,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
        Text(value,
            style: TextStyle(fontSize: 11, color: valueColor,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }

  // ── NOTES ───────────────────────────────────────────────────────────────────
  Widget _buildNotes() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _pvNotesBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _pvNotesBdr),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('NOTES',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                color: _pvBrown, letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(invoice.notes,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                color: _pvDark, height: 1.5)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// INVOICE DOCUMENT WIDGET  (shared between view & print)
// ══════════════════════════════════════════════════════════════════════════════
class _InvoiceDocument extends StatelessWidget {
  final Invoice invoice;
  const _InvoiceDocument({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final r = R.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(r.cardPad),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryBlueDark, AppTheme.salesColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Image.asset(
                  'assets/images/company_logo.png',
                  width: r.isMobile ? 44 : 58,
                  height: r.isMobile ? 44 : 58,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                      Icons.inventory_2_rounded,
                      color: Colors.white,
                      size: r.iconLg),
                ),
                SizedBox(width: r.gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vinex Technology',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: r.fs18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          )),
                      SizedBox(height: r.gapS),
                      // Address
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 11,
                              color: Colors.white.withValues(alpha: 0.65)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'Baghdad, Yarmouk, Al-Fakhri 2 Building',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Phone
                      Row(
                        children: [
                          Icon(Icons.phone_outlined,
                              size: 11,
                              color: Colors.white.withValues(alpha: 0.65)),
                          const SizedBox(width: 3),
                          Text(
                            '07803662728',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 10,
                                letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4)),
                      ),
                      child: const Text('INVOICE',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 2)),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '#${invoice.invoiceNumber.toString().padLeft(4, '0')}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Customer + Date ───────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(r.hPad, r.gap, r.hPad, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _InfoBlock(
                    title: 'BILL TO',
                    icon: Icons.person_outline_rounded,
                    lines: [invoice.customerName],
                  ),
                ),
                Expanded(
                  child: _InfoBlock(
                    title: 'INVOICE DATE',
                    icon: Icons.calendar_today_rounded,
                    lines: [
                      DateFormat('MMMM dd, yyyy').format(invoice.invoiceDate),
                    ],
                    align: CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: r.gap),
          Divider(height: 1, indent: r.hPad, endIndent: r.hPad),
          SizedBox(height: r.gapS + 4),

          // ── Items table header ────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.hPad),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: r.gapS + 4, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.salesColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(width: r.isMobile ? 24 : 30, child: const Text('#', style: _tableHeaderStyle)),
                  const Expanded(flex: 5, child: Text('Item Name', style: _tableHeaderStyle)),
                  SizedBox(width: r.isMobile ? 38 : 55, child: const Text('Qty', textAlign: TextAlign.center, style: _tableHeaderStyle)),
                  if (!r.isMobile)
                    const SizedBox(width: 80, child: Text('Unit Price', textAlign: TextAlign.right, style: _tableHeaderStyle)),
                  SizedBox(width: r.isMobile ? 70 : 85, child: const Text('Amount', textAlign: TextAlign.right, style: _tableHeaderStyle)),
                ],
              ),
            ),
          ),
          SizedBox(height: r.gapS),

          // ── Item rows ─────────────────────────────────────────────────
          ...invoice.items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            return Container(
              margin: EdgeInsets.symmetric(horizontal: r.hPad, vertical: 1),
              padding: EdgeInsets.symmetric(horizontal: r.gapS + 4, vertical: 8),
              decoration: BoxDecoration(
                color: i % 2 == 0 ? Colors.transparent : AppTheme.background,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: r.isMobile ? 24 : 30,
                    child: Container(
                      width: r.isMobile ? 18 : 22, height: r.isMobile ? 18 : 22,
                      decoration: BoxDecoration(
                        color: AppTheme.salesColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${item.sequence}',
                            style: TextStyle(
                                fontSize: r.fs11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.salesColor)),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(item.itemName,
                        style: TextStyle(
                            fontSize: r.fs14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black)),
                  ),
                  SizedBox(
                    width: r.isMobile ? 38 : 55,
                    child: Text(
                      item.quantity % 1 == 0
                          ? item.quantity.toInt().toString()
                          : item.quantity.toStringAsFixed(2),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: r.fs13, color: const Color(0xFF333333)),
                    ),
                  ),
                  if (!r.isMobile)
                    SizedBox(
                      width: 80,
                      child: Text(CurrencyHelper.format(item.unitPrice),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: r.fs12, color: const Color(0xFF555555))),
                    ),
                  SizedBox(
                    width: r.isMobile ? 70 : 85,
                    child: Text(CurrencyHelper.format(item.totalPrice),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: r.fs13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black)),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),
          const Divider(height: 1, indent: 20, endIndent: 20),
          const SizedBox(height: 12),

          // ── Notes ─────────────────────────────────────────────────────
          if (invoice.notes.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: r.hPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.note_outlined, size: 16, color: AppTheme.textGrey),
                      SizedBox(width: 6),
                      Text('NOTES',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textGrey,
                              letterSpacing: 1)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFDE7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFECB3)),
                    ),
                    child: Text(invoice.notes,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black, height: 1.4)),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],

          // ── Total ─────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.hPad),
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  children: [
                    // Subtotal line
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal',
                            style: TextStyle(
                                color: Color(0xFF444444), fontSize: 13)),
                        Text(CurrencyHelper.format(invoice.subtotal),
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black)),
                      ],
                    ),
                    // Discount line (only when > 0)
                    if (invoice.discount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.discount_outlined,
                                  size: 14,
                                  color: Color(0xFFE65100)),
                              const SizedBox(width: 4),
                              const Text('Discount',
                                  style: TextStyle(
                                      color: Color(0xFFE65100),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Text(
                            '- ${CurrencyHelper.format(invoice.discount)}',
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFFE65100),
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.salesColor, Color(0xFF43A047)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL AMOUNT',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 0.5)),
                          Text(CurrencyHelper.format(invoice.totalAmount),
                              style: const TextStyle(
                                  color: Color(0xFFFFFF00),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                    // Down Payment & Remaining Amount
                    if (invoice.hasDownPayment) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            const Icon(Icons.payments_outlined,
                                size: 14, color: Color(0xFF1565C0)),
                            const SizedBox(width: 4),
                            const Text('Down Payment',
                                style: TextStyle(
                                    color: Color(0xFF1565C0),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ]),
                          Text(CurrencyHelper.format(invoice.downPayment),
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF1565C0),
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Remaining Amount',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    letterSpacing: 0.5)),
                            Text(CurrencyHelper.format(invoice.remainingAmount),
                                style: const TextStyle(
                                    color: Color(0xFFFFFF00),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ── Footer ────────────────────────────────────────────────────
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: r.hPad, vertical: r.gap),
            decoration: const BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Text(
              'Thank you for your business! — Vinex Technology © 2025',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textGrey, fontSize: r.fs12, letterSpacing: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// INVOICE EDIT SCREEN
// ══════════════════════════════════════════════════════════════════════════════
class InvoiceEditScreen extends StatefulWidget {
  final Invoice invoice;
  const InvoiceEditScreen({super.key, required this.invoice});

  @override
  State<InvoiceEditScreen> createState() => _InvoiceEditScreenState();
}

class _InvoiceEditScreenState extends State<InvoiceEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _customerCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _discountCtrl;
  late TextEditingController _downPaymentCtrl;
  late DateTime _invoiceDate;
  late List<_EditRowController> _rows;
  List<InventoryItem> _inventoryItems = [];

  @override
  void initState() {
    super.initState();
    _customerCtrl =
        TextEditingController(text: widget.invoice.customerName);
    _notesCtrl = TextEditingController(text: widget.invoice.notes);
    _discountCtrl = TextEditingController(
        text: widget.invoice.discount > 0
            ? widget.invoice.discount.toStringAsFixed(
                widget.invoice.discount % 1 == 0 ? 0 : 2)
            : '');
    _downPaymentCtrl = TextEditingController(
        text: widget.invoice.downPayment > 0
            ? widget.invoice.downPayment.toStringAsFixed(
                widget.invoice.downPayment % 1 == 0 ? 0 : 2)
            : '');
    _invoiceDate = widget.invoice.invoiceDate;
    _loadInventoryAndRows();
  }

  Future<void> _loadInventoryAndRows() async {
    final items = await DatabaseService.getAllInventoryItemsAsync();
    // Pre-fill rows from existing invoice items
    final rows = widget.invoice.items.asMap().entries.map((e) {
      final item = e.value;
      InventoryItem? invItem;
      try {
        invItem = items.firstWhere(
          (inv) =>
              inv.itemName.trim().toLowerCase() ==
              item.itemName.trim().toLowerCase(),
        );
      } catch (_) {
        invItem = null;
      }
      return _EditRowController(
        sequence: e.key + 1,
        selectedItem: invItem,
        manualItemName: invItem == null ? item.itemName : null,
        qty: item.quantity,
        price: item.unitPrice,
      );
    }).toList();
    if (mounted) {
      setState(() {
        _inventoryItems = items;
        _rows = rows;
      });
    }
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _notesCtrl.dispose();
    _discountCtrl.dispose();
    _downPaymentCtrl.dispose();
    for (final r in _rows) { r.dispose(); }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _rows.add(_EditRowController(sequence: _rows.length + 1));
    });
  }

  void _removeRow(int index) {
    if (_rows.length == 1) return;
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
      for (int i = 0; i < _rows.length; i++) { _rows[i].sequence = i + 1; }
    });
  }

  double get _subtotal => _rows.fold(0.0, (s, r) => s + r.lineTotal);
  double get _discountValue => double.tryParse(_discountCtrl.text) ?? 0;
  double get _grandTotal => (_subtotal - _discountValue).clamp(0, double.infinity);
  double get _downPaymentValue => double.tryParse(_downPaymentCtrl.text) ?? 0;
  double get _remainingAmount => (_grandTotal - _downPaymentValue).clamp(0, double.infinity);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: const ColorScheme.light(primary: AppTheme.salesColor)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _invoiceDate = picked);
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate rows
    for (int i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final name = r.selectedItem?.itemName ?? r.manualItemName ?? '';
      if (name.trim().isEmpty) {
        _showError('Row ${i + 1}: Please select an item');
        return;
      }
      if (r.quantity <= 0) {
        _showError('Row ${i + 1}: Quantity must be > 0');
        return;
      }
      if (r.unitPrice <= 0) {
        _showError('Row ${i + 1}: Price must be > 0');
        return;
      }
    }

    final newItems = _rows.asMap().entries.map((e) {
      final r = e.value;
      final name = r.selectedItem?.itemName ?? r.manualItemName ?? '';
      return InvoiceItem(
        sequence: e.key + 1,
        itemName: name,
        quantity: r.quantity,
        unitPrice: r.unitPrice,
        totalPrice: r.lineTotal,
      );
    }).toList();

    final newInvoice = Invoice(
      id: widget.invoice.id,
      invoiceNumber: widget.invoice.invoiceNumber,
      customerName: _customerCtrl.text.trim(),
      invoiceDate: _invoiceDate,
      items: newItems,
      notes: _notesCtrl.text.trim(),
      discount: _discountValue,
      totalAmount: _grandTotal,
      invoiceType: widget.invoice.invoiceType,
      downPayment: _downPaymentValue,
    );

    final error = await DatabaseService.updateInvoiceWithStockAdjustment(
        widget.invoice, newInvoice);

    if (error != null) {
      if (!mounted) return;
      _showError(error);
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(children: [
          Icon(Icons.check_circle, color: Colors.white),
          SizedBox(width: 8),
          Text('Invoice updated successfully!'),
        ]),
        backgroundColor: AppTheme.salesColor,
        behavior: SnackBarBehavior.floating,
      ),
    );

    Navigator.pop(context, newInvoice);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppTheme.errorColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        title: Text(
            'Edit Invoice #${widget.invoice.invoiceNumber.toString().padLeft(4, '0')}'),
        actions: [
          TextButton.icon(
            onPressed: _saveChanges,
            icon: const Icon(Icons.save_rounded, color: Colors.white),
            label: const Text('Save',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Builder(builder: (context) {
          final r = R.of(context);
          return ListView(
          padding: EdgeInsets.all(r.hPad),
          children: [
            // ── Invoice Info ────────────────────────────────────────────
            _EditSectionCard(
              title: 'Invoice Information',
              icon: Icons.info_outline_rounded,
              children: [
                TextFormField(
                  controller: _customerCtrl,
                  decoration:
                      _inputDeco('Customer Name *', Icons.person_outline_rounded),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Customer name is required'
                      : null,
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _pickDate,
                  child: AbsorbPointer(
                    child: TextFormField(
                      decoration:
                          _inputDeco('Invoice Date *', Icons.calendar_today_rounded)
                              .copyWith(
                        hintText: DateFormat('MMM dd, yyyy').format(_invoiceDate),
                        suffixIcon: const Icon(Icons.arrow_drop_down_rounded,
                            color: AppTheme.salesColor),
                      ),
                      controller: TextEditingController(
                          text: DateFormat('MMM dd, yyyy').format(_invoiceDate)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Items Table ─────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.salesColor.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                      ),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 28, child: Text('#', style: _editHeaderStyle)),
                        Expanded(flex: 5, child: Text('Item (Storage)', style: _editHeaderStyle)),
                        Expanded(flex: 2, child: Text('Qty', textAlign: TextAlign.center, style: _editHeaderStyle)),
                        Expanded(flex: 2, child: Text('Price', textAlign: TextAlign.center, style: _editHeaderStyle)),
                        Expanded(flex: 2, child: Text('Total', textAlign: TextAlign.right, style: _editHeaderStyle)),
                        SizedBox(width: 32),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Rows
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) => _EditRowWidget(
                      rowCtrl: _rows[i],
                      inventoryItems: _inventoryItems,
                      canDelete: _rows.length > 1,
                      onDelete: () => _removeRow(i),
                      onChanged: () => setState(() {}),
                    ),
                  ),

                  // Add Row
                  InkWell(
                    onTap: _addRow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.salesColor.withValues(alpha: 0.04),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(14),
                          bottomRight: Radius.circular(14),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_circle_outline_rounded,
                              color: AppTheme.salesColor, size: 18),
                          SizedBox(width: 6),
                          Text('Add Item Row',
                              style: TextStyle(
                                  color: AppTheme.salesColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ── Notes ───────────────────────────────────────────────────
            _EditSectionCard(
              title: 'Notes',
              icon: Icons.note_outlined,
              children: [
                TextFormField(
                  controller: _notesCtrl,
                  minLines: 2,
                  maxLines: 4,
                  decoration: _inputDeco(
                      'Additional notes (optional)', Icons.edit_note_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Discount + Totals summary
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6,
                      offset: Offset(0, 2))
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textGrey)),
                      Text(CurrencyHelper.format(_subtotal),
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.textDark)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.discount_outlined,
                          size: 18, color: AppTheme.purchasesColor),
                      const SizedBox(width: 8),
                      const Text('Discount',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.purchasesColor)),
                      const Spacer(),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: _discountCtrl,
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.purchasesColor,
                              fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: '0',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: AppTheme.purchasesColor)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                    color: AppTheme.purchasesColor,
                                    width: 1.5)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                    color: AppTheme.purchasesColor
                                        .withValues(alpha: 0.5))),
                            prefixText: '- ',
                            prefixStyle: const TextStyle(
                                color: AppTheme.purchasesColor,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Down Payment
                  if (!widget.invoice.isQuote) ...[
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined,
                            size: 18, color: Color(0xFF1565C0)),
                        const SizedBox(width: 8),
                        const Text('Down Payment',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1565C0))),
                        const Spacer(),
                        SizedBox(
                          width: 130,
                          child: TextField(
                            controller: _downPaymentCtrl,
                            onChanged: (_) => setState(() {}),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1565C0),
                                fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              hintText: '0',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF90CAF9))),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF1565C0), width: 1.5)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF90CAF9))),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.salesColor, Color(0xFF43A047)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.salesColor.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL AMOUNT',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                letterSpacing: 0.5)),
                        Text(
                          CurrencyHelper.format(_grandTotal),
                          style: const TextStyle(
                            color: Color(0xFFFFFF00),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Remaining Amount
                  if (!widget.invoice.isQuote && _downPaymentValue > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Remaining Amount',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 0.5)),
                          Text(
                            CurrencyHelper.format(_remainingAmount),
                            style: const TextStyle(
                              color: Color(0xFFFFFF00),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Save Button
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.salesColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save Changes',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 30),
          ],
          );
        }),
      ),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.salesColor, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}

// ─── Edit Row Controller ──────────────────────────────────────────────────────
class _EditRowController {
  int sequence;
  InventoryItem? selectedItem;
  String? manualItemName;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;

  _EditRowController({
    required this.sequence,
    this.selectedItem,
    this.manualItemName,
    double qty = 0,
    double price = 0,
  })  : qtyCtrl = TextEditingController(
            text: qty > 0 ? qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2) : ''),
        priceCtrl = TextEditingController(
            text: price > 0
                ? price.toStringAsFixed(price % 1 == 0 ? 0 : 2)
                : '');

  double get quantity => double.tryParse(qtyCtrl.text) ?? 0;
  double get unitPrice => double.tryParse(priceCtrl.text) ?? 0;
  double get lineTotal => quantity * unitPrice;

  void dispose() {
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

// ─── Edit Row Widget ──────────────────────────────────────────────────────────
class _EditRowWidget extends StatefulWidget {
  final _EditRowController rowCtrl;
  final List<InventoryItem> inventoryItems;
  final bool canDelete;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _EditRowWidget({
    required this.rowCtrl,
    required this.inventoryItems,
    required this.canDelete,
    required this.onDelete,
    required this.onChanged,
  });

  @override
  State<_EditRowWidget> createState() => _EditRowWidgetState();
}

class _EditRowWidgetState extends State<_EditRowWidget> {
  @override
  Widget build(BuildContext context) {
    final selected = widget.rowCtrl.selectedItem;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Sequence
              SizedBox(
                width: 28,
                child: Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.salesColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('${widget.rowCtrl.sequence}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.salesColor)),
                  ),
                ),
              ),

              // Item dropdown
              Expanded(
                flex: 5,
                child: widget.inventoryItems.isEmpty
                    ? Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text('No items',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textGrey)),
                        ),
                      )
                    : DropdownButtonFormField<InventoryItem>(
                        initialValue: selected,
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: widget.rowCtrl.manualItemName ?? 'Select item',
                          hintStyle: const TextStyle(
                              fontSize: 12, color: AppTheme.textGrey),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AppTheme.divider)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AppTheme.divider)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: AppTheme.salesColor, width: 1.5)),
                        ),
                        items: widget.inventoryItems.map((item) {
                          return DropdownMenuItem<InventoryItem>(
                            value: item,
                            child: Text(item.itemName,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (item) {
                          setState(() {
                            widget.rowCtrl.selectedItem = item;
                            widget.rowCtrl.manualItemName = null;
                            if (item != null) {
                              widget.rowCtrl.priceCtrl.text =
                                  item.unitPrice.toStringAsFixed(0);
                            }
                          });
                          widget.onChanged();
                        },
                      ),
              ),
              const SizedBox(width: 6),

              // Qty
              Expanded(
                flex: 2,
                child: _compactField(
                    widget.rowCtrl.qtyCtrl, 'Qty', widget.onChanged,
                    number: true),
              ),
              const SizedBox(width: 6),

              // Price
              Expanded(
                flex: 2,
                child: _compactField(
                    widget.rowCtrl.priceCtrl, 'Price', widget.onChanged,
                    number: true),
              ),
              const SizedBox(width: 6),

              // Line total
              Expanded(
                flex: 2,
                child: Text(
                  CurrencyHelper.format(widget.rowCtrl.lineTotal),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppTheme.salesColor),
                ),
              ),

              // Delete
              SizedBox(
                width: 32,
                child: widget.canDelete
                    ? IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded,
                            color: AppTheme.errorColor, size: 18),
                        padding: EdgeInsets.zero,
                        onPressed: widget.onDelete,
                      )
                    : const SizedBox(),
              ),
            ],
          ),

          // Stock badge
          if (selected != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: selected.quantity > 0
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected.quantity > 0
                        ? Colors.green.shade300
                        : Colors.red.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected.quantity > 0
                          ? Icons.inventory_2_outlined
                          : Icons.warning_amber_rounded,
                      size: 13,
                      color: selected.quantity > 0
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Available: ${selected.quantity.toStringAsFixed(0)} ${selected.unit}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected.quantity > 0
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _compactField(
    TextEditingController ctrl,
    String hint,
    VoidCallback onChange, {
    bool number = false,
  }) {
    return TextField(
      controller: ctrl,
      onChanged: (_) => onChange(),
      keyboardType:
          number ? const TextInputType.numberWithOptions(decimal: true) : null,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(fontSize: 12, color: AppTheme.textGrey),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.divider)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: AppTheme.salesColor, width: 1.5)),
      ),
    );
  }
}

// ─── Edit Section Card ────────────────────────────────────────────────────────
class _EditSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _EditSectionCard(
      {required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.salesColor.withValues(alpha: 0.07),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.salesColor, size: 18),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.salesColor)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Styles ────────────────────────────────────────────────────────────
const _tableHeaderStyle = TextStyle(
  fontWeight: FontWeight.bold,
  fontSize: 12,
  color: AppTheme.salesColor,
  letterSpacing: 0.3,
);

const _editHeaderStyle = TextStyle(
  fontWeight: FontWeight.bold,
  fontSize: 13,
  color: AppTheme.salesColor,
);

// ── شاشة تأكيد حذف الفاتورة الأصيلة (invoice detail) ─────────────────────────
class _DetailDeleteDialog extends StatelessWidget {
  final dynamic invoice; // Invoice type
  final Future<void> Function() onConfirmed;
  const _DetailDeleteDialog({required this.invoice, required this.onConfirmed});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: const Row(
            children: [
              Icon(Icons.delete_forever_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('حذف الفاتورة', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'هل أنت متأكد من حذف الفاتورة رقم #${invoice.invoiceNumber}؟',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _DetailInfoRow(icon: Icons.person_outline_rounded, label: 'العميل', value: invoice.customerName),
              _DetailInfoRow(icon: Icons.calendar_today_rounded, label: 'التاريخ', value: DateFormat('dd/MM/yyyy').format(invoice.invoiceDate)),
              _DetailInfoRow(icon: Icons.attach_money_rounded, label: 'الإجمالي', value: CurrencyHelper.format(invoice.totalAmount), valueColor: AppTheme.salesColor),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.inventory_2_outlined, color: AppTheme.primaryBlue, size: 16),
                      SizedBox(width: 6),
                      Text('المواد التي ستُعاد للمخزن:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryBlue)),
                    ]),
                    const SizedBox(height: 8),
                    ...invoice.items.map<Widget>((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.add_circle_outline_rounded, color: Colors.green, size: 14),
                          const SizedBox(width: 6),
                          Expanded(child: Text(item.itemName, style: const TextStyle(fontSize: 13))),
                          Text('+${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 1)}',
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    )).toList(),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text('لا يمكن التراجع عن هذا الإجراء.', style: TextStyle(color: AppTheme.textGrey, fontSize: 12)),
              const SizedBox(height: 8),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('لا، تراجع', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    foregroundColor: AppTheme.textGrey,
                    side: const BorderSide(color: AppTheme.textGrey),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await onConfirmed();
                  },
                  icon: const Icon(Icons.delete_forever_rounded, size: 18),
                  label: const Text('نعم، احذف', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> lines;
  final CrossAxisAlignment align;

  const _InfoBlock({
    required this.title,
    required this.icon,
    required this.lines,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Row(
          mainAxisAlignment: align == CrossAxisAlignment.end
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Icon(icon, size: 12, color: AppTheme.textGrey),
            const SizedBox(width: 4),
            Text(title,
                style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textGrey,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ],
        ),
        const SizedBox(height: 5),
        ...lines.map(
          (l) => Text(l,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFCC0000))),
        ),
      ],
    );
  }
}

// Helper to generate UUID for updated invoices
// ignore: unused_element
String _newUuid() => const Uuid().v4();

// ── Delete Dialog Info Row ─────────────────────────────────────────────────
class _DetailInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textGrey),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textGrey,
                  fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? AppTheme.textDark),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
