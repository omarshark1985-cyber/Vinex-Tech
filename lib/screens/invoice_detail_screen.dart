import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';
import 'dart:convert' show base64Encode;
import '../utils/js_helper.dart';
import '../utils/responsive.dart';
import '../models/invoice_model.dart';
import '../models/invoice_item_model.dart';
import '../models/inventory_model.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../utils/currency_helper.dart';


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
  late Invoice _invoice;

  @override
  void initState() {
    super.initState();
    _invoice = widget.invoice;
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

  // ── Delete Confirmation Dialog ─────────────────────────────────────────────
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          // Title
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_forever_rounded,
                    color: Colors.red, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'حذف الفاتورة',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red),
                ),
              ),
            ],
          ),
          // Content
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(height: 20),
                // Warning
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'هل أنت متأكد من حذف الفاتورة رقم #${_invoice.invoiceNumber}؟',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Info rows
                _DetailInfoRow(
                  icon: Icons.person_outline_rounded,
                  label: 'العميل',
                  value: _invoice.customerName,
                ),
                _DetailInfoRow(
                  icon: Icons.calendar_today_rounded,
                  label: 'التاريخ',
                  value: DateFormat('dd/MM/yyyy').format(_invoice.invoiceDate),
                ),
                _DetailInfoRow(
                  icon: Icons.attach_money_rounded,
                  label: 'الإجمالي',
                  value: CurrencyHelper.format(_invoice.totalAmount),
                  valueColor: AppTheme.salesColor,
                ),
                const SizedBox(height: 10),
                // Items to restore
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
                      Row(
                        children: const [
                          Icon(Icons.inventory_2_outlined,
                              color: AppTheme.primaryBlue, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'المواد التي ستُعاد للمخزن:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppTheme.primaryBlue),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._invoice.items.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.add_circle_outline_rounded,
                                    color: Colors.green, size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(item.itemName,
                                      style: const TextStyle(fontSize: 13)),
                                ),
                                Text(
                                  '+${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 1)}',
                                  style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'لا يمكن التراجع عن هذا الإجراء.',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
                ),
                const SizedBox(height: 16),
                // ── Buttons ───────────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('لا، تراجع',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          foregroundColor: AppTheme.textGrey,
                          side: const BorderSide(color: AppTheme.textGrey),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(dialogCtx).pop();
                          setState(() => _deleting = true);
                          await DatabaseService.deleteInvoice(_invoice.id);
                          DatabaseService.refreshData();
                          if (mounted) {
                            setState(() => _deleting = false);
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '✅ تم حذف الفاتورة #${_invoice.invoiceNumber} وإعادة المواد للمخزن'),
                                backgroundColor: Colors.green,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.delete_forever_rounded),
                        label: const Text('نعم، احذف',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
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
            backgroundColor: AppTheme.salesColor,
            title: Text('Invoice #${_invoice.invoiceNumber.toString().padLeft(4, '0')}'),
            actions: [
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
              // Print button
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded),
                tooltip: 'Print View (A4)',
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
        if (_deleting)
          Container(
            color: Colors.black26,
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('جاري حذف الفاتورة\nوإعادة المواد للمخزن...',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14)),
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
  String? _logoBase64; // loaded once in initState

  @override
  void initState() {
    super.initState();
    _loadLogo();
  }

  Future<void> _loadLogo() async {
    try {
      final bytes = await rootBundle
          .load('assets/images/company_logo.png');
      final b64 = base64Encode(bytes.buffer.asUint8List());
      if (mounted) setState(() => _logoBase64 = b64);
    } catch (_) {
      // logo not available – fallback to emoji handled in HTML
    }
  }

  // ── Build a standalone HTML page for the invoice ─────────────────────────
  String _buildInvoiceHtml() {
    final invoice = widget.invoice;
    final invNum = invoice.invoiceNumber.toString().padLeft(4, '0');
    final dateStr = DateFormat('MMMM dd, yyyy').format(invoice.invoiceDate);
    final printedStr =
        DateFormat('MMM dd, yyyy – hh:mm a').format(DateTime.now());

    // Build items rows HTML
    final itemsHtml = invoice.items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      final bg = i % 2 == 0 ? '#ffffff' : '#f0f4ff';
      final qty = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toStringAsFixed(2);
      return '''
        <tr style="background:$bg;">
          <td style="padding:10px 14px;text-align:center;">
            <span style="display:inline-flex;align-items:center;justify-content:center;
              width:22px;height:22px;border-radius:50%;background:rgba(37,99,235,0.12);
              font-size:10px;font-weight:700;color:#1d4ed8;">${item.sequence}</span>
          </td>
          <td style="padding:10px 14px;font-size:12px;font-weight:600;color:#000000;">${_esc(item.itemName)}</td>
          <td style="padding:10px 14px;text-align:center;font-size:12px;color:#333333;">$qty</td>
          <td style="padding:10px 14px;text-align:right;font-size:11px;color:#444444;">${CurrencyHelper.format(item.unitPrice)}</td>
          <td style="padding:10px 14px;text-align:right;font-size:12px;font-weight:700;color:#000000;">${CurrencyHelper.format(item.totalPrice)}</td>
        </tr>''';
    }).join('\n');

    // Totals section
    final subtotal = invoice.subtotal;
    final hasDiscount = invoice.discount > 0;
    final discountHtml = hasDiscount ? '''
        <tr>
          <td colspan="4" style="padding:6px 14px;text-align:right;font-size:11px;color:#444444;">Subtotal</td>
          <td style="padding:6px 14px;text-align:right;font-size:11px;color:#000000;">${CurrencyHelper.format(subtotal)}</td>
        </tr>
        <tr>
          <td colspan="4" style="padding:6px 14px;text-align:right;font-size:11px;color:#cc0000;font-weight:600;">Discount</td>
          <td style="padding:6px 14px;text-align:right;font-size:11px;color:#cc0000;font-weight:700;">- ${CurrencyHelper.format(invoice.discount)}</td>
        </tr>''' : '';

    // Notes HTML
    final notesHtml = invoice.notes.isNotEmpty ? '''
      <div style="margin:0 40px 20px;padding:14px;background:#fffde7;border:1px solid #ffecb3;border-radius:8px;">
        <div style="font-size:10px;font-weight:700;color:#795548;letter-spacing:1px;margin-bottom:6px;">NOTES</div>
        <div style="font-size:12px;color:#000000;line-height:1.5;">${_esc(invoice.notes)}</div>
      </div>''' : '';

    // Logo HTML: use real logo if loaded, otherwise fallback icon
    final logoHtml = _logoBase64 != null
        ? '<img src="data:image/png;base64,$_logoBase64" '
          'style="width:56px;height:56px;object-fit:contain;border-radius:8px;" />'
        : '<span style="color:white;font-size:28px;">🏢</span>';

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Invoice #$invNum</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #d0d0d0;
      display: flex;
      justify-content: center;
      padding: 24px;
    }
    .page {
      width: 794px;
      min-height: 1123px;
      background: white;
      box-shadow: 0 6px 20px rgba(0,0,0,0.25);
      display: flex;
      flex-direction: column;
    }
    @media print {
      body { background: white !important; padding: 0 !important; }
      .page { box-shadow: none !important; width: 100% !important; }
      @page { size: A4 portrait; margin: 0; }
    }
  </style>
</head>
<body>
  <div class="page">

    <!-- ── HEADER ── -->
    <div style="background:linear-gradient(to right,#1e3a5f,#2e7d32);padding:28px 40px;display:flex;align-items:center;">
      <div style="width:64px;height:64px;background:rgba(255,255,255,0.15);border-radius:12px;
                  border:1.5px solid rgba(255,255,255,0.3);display:flex;align-items:center;justify-content:center;
                  flex-shrink:0;overflow:hidden;">
        $logoHtml
      </div>
      <div style="margin-left:16px;flex:1;">
        <div style="color:white;font-size:22px;font-weight:700;letter-spacing:2px;">VINEX TECHNOLOGY</div>

        <div style="margin-top:8px;display:flex;flex-direction:column;gap:3px;">
          <div style="display:flex;align-items:center;gap:5px;">
            <span style="color:rgba(255,255,255,0.6);font-size:10px;">&#128205;</span>
            <span style="color:rgba(255,255,255,0.85);font-size:10px;letter-spacing:0.3px;">Baghdad, Yarmouk, Al-Fakhri 2 Building</span>
          </div>
          <div style="display:flex;align-items:center;gap:5px;">
            <span style="color:rgba(255,255,255,0.6);font-size:10px;">&#128222;</span>
            <span style="color:rgba(255,255,255,0.85);font-size:10px;letter-spacing:0.5px;">07803662728</span>
          </div>
        </div>
      </div>
      <div style="text-align:right;">
        <div style="background:rgba(255,255,255,0.2);border:1px solid rgba(255,255,255,0.4);
                    border-radius:6px;padding:5px 14px;display:inline-block;
                    color:white;font-weight:700;font-size:12px;letter-spacing:3px;">INVOICE</div>
        <div style="color:white;font-size:24px;font-weight:700;margin-top:6px;">#$invNum</div>
      </div>
    </div>

    <!-- ── BILL TO / INVOICE DETAILS ── -->
    <div style="display:flex;gap:16px;padding:24px 40px 0;">
      <div style="flex:1;border:1px solid #e5e7eb;border-radius:8px;overflow:hidden;">
        <div style="background:#2563eb;padding:8px 12px;">
          <span style="color:white;font-size:10px;font-weight:700;letter-spacing:1.2px;">BILL TO</span>
        </div>
        <div style="padding:12px;">
          <div style="font-size:10px;font-weight:700;color:#444444;margin-bottom:4px;">Customer</div>
          <div style="font-size:15px;font-weight:700;color:#cc0000;">${_esc(invoice.customerName)}</div>
        </div>
      </div>
      <div style="flex:1;border:1px solid #e5e7eb;border-radius:8px;overflow:hidden;">
        <div style="background:#2e7d32;padding:8px 12px;">
          <span style="color:white;font-size:10px;font-weight:700;letter-spacing:1.2px;">INVOICE DETAILS</span>
        </div>
        <div style="padding:12px;">
          <table style="width:100%;font-size:11px;border-collapse:collapse;">
            <tr><td style="color:#444444;font-weight:700;padding-bottom:5px;">Invoice No.</td>
                <td style="color:#cc0000;font-weight:700;text-align:right;font-size:13px;">#$invNum</td></tr>
            <tr><td style="color:#444444;font-weight:700;padding-bottom:5px;">Date</td>
                <td style="color:#cc0000;font-weight:700;text-align:right;">$dateStr</td></tr>
            <tr><td style="color:#444444;font-weight:700;padding-bottom:5px;">Items</td>
                <td style="color:#000000;font-weight:700;text-align:right;">${invoice.items.length} item(s)</td></tr>
            <tr><td style="color:#444444;font-weight:700;">Printed</td>
                <td style="color:#000000;font-weight:600;text-align:right;font-size:10px;">$printedStr</td></tr>
          </table>
        </div>
      </div>
    </div>

    <!-- ── ITEMS TABLE ── -->
    <div style="margin:24px 40px 0;">
      <table style="width:100%;border-collapse:collapse;border:1px solid #e5e7eb;border-radius:8px;overflow:hidden;">
        <thead>
          <tr style="background:#2563eb;">
            <th style="padding:10px 14px;color:white;font-size:10px;font-weight:700;letter-spacing:0.5px;text-align:center;width:40px;">#</th>
            <th style="padding:10px 14px;color:white;font-size:10px;font-weight:700;letter-spacing:0.5px;text-align:left;">ITEM NAME</th>
            <th style="padding:10px 14px;color:white;font-size:10px;font-weight:700;letter-spacing:0.5px;text-align:center;width:60px;">QTY</th>
            <th style="padding:10px 14px;color:white;font-size:10px;font-weight:700;letter-spacing:0.5px;text-align:right;width:110px;">UNIT PRICE</th>
            <th style="padding:10px 14px;color:white;font-size:10px;font-weight:700;letter-spacing:0.5px;text-align:right;width:110px;">AMOUNT</th>
          </tr>
        </thead>
        <tbody>
          $itemsHtml
          <!-- divider before totals -->
          <tr><td colspan="5" style="border-top:2px solid #e5e7eb;padding:0;"></td></tr>
          $discountHtml
          <tr>
            <td colspan="4">&nbsp;</td>
            <td style="padding:0;"></td>
          </tr>
        </tbody>
        <tfoot>
          <tr style="background:linear-gradient(to right,#16a34a,#43a047);">
            <td colspan="4" style="padding:14px;color:white;font-size:11px;font-weight:700;letter-spacing:0.8px;">TOTAL AMOUNT</td>
            <td style="padding:14px;color:#ffff00;font-size:18px;font-weight:700;text-align:right;text-shadow:0 1px 3px rgba(0,0,0,0.3);">${CurrencyHelper.format(invoice.totalAmount)}</td>
          </tr>
        </tfoot>
      </table>
    </div>

    $notesHtml

    <!-- ── SPACER ── -->
    <div style="flex:1;"></div>

    <!-- ── FOOTER ── -->
    <div style="padding:14px 40px;border-top:1px solid #e5e7eb;display:flex;justify-content:space-between;align-items:center;">
      <div style="display:flex;flex-direction:column;gap:3px;">
        <span style="font-size:10px;color:#94a3b8;font-style:italic;">Thank you for your business!</span>
        <div style="display:flex;align-items:center;gap:12px;margin-top:2px;">
          <span style="font-size:9px;color:#94a3b8;">&#128205; Baghdad, Yarmouk, Al-Fakhri 2 Building</span>
          <span style="font-size:9px;color:#94a3b8;">&#128222; 07803662728</span>
        </div>
      </div>
      <span style="font-size:10px;color:#2563eb;font-weight:700;">VINEX TECHNOLOGY © 2025</span>
    </div>

  </div>
</body>
</html>''';
  }

  /// Escape HTML special characters
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ── Open HTML preview in new browser tab (unchanged) ────────────────────
  void _doPrint() {
    if (!kIsWeb) return;
    final html = _buildInvoiceHtml();
    final encoded = Uri.encodeFull(html)
        .replaceAll("'", "%27")
        .replaceAll('"', '%22');
    evalJs("window.__invHtml = '$encoded';");
    evalJs('''
      (function(){
        var decoded = decodeURI(window.__invHtml);
        var blob = new Blob([decoded], {type: 'text/html'});
        var url  = URL.createObjectURL(blob);
        var a    = document.createElement('a');
        a.href   = url;
        a.target = '_blank';
        a.rel    = 'noopener noreferrer';
        document.body.appendChild(a);
        a.click();
        setTimeout(function(){ URL.revokeObjectURL(url); document.body.removeChild(a); }, 1000);
      })();
    ''');
  }

  // ── Export Invoice as Image (PNG) ─────────────────────────────────────────
  final GlobalKey _invoiceKey = GlobalKey();
  bool _exportingImg = false;

  Future<void> _exportImage() async {
    if (_exportingImg) return;
    setState(() => _exportingImg = true);
    try {
      // Give Flutter one extra frame to finish painting
      await Future.delayed(const Duration(milliseconds: 120));

      final boundary = _invoiceKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('لم يتم العثور على الفاتورة في الشاشة');
      }

      // Capture widget at 3× resolution → high quality
      final ui.Image uiImage = await boundary.toImage(pixelRatio: 3.0);

      // toByteData with png gives a valid PNG binary directly — no codec needed
      final ByteData? pngData =
          await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (pngData == null) throw Exception('فشل تحويل الصورة');

      final Uint8List pngBytes = pngData.buffer.asUint8List();
      final invNum   = widget.invoice.invoiceNumber.toString().padLeft(4, '0');
      final fileName = 'Invoice_$invNum.jpg'; // saved as .jpg, content is PNG

      if (kIsWeb) {
        _downloadImageWeb(pngBytes, fileName);
      } else {
        _shareImageMobile(pngBytes, fileName);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم تصدير الفاتورة كصورة: $fileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('exportImage error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل تصدير الصورة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingImg = false);
    }
  }

  void _downloadImageWeb(Uint8List bytes, String fileName) {
    final b64 = base64Encode(bytes);
    evalJs("""
      (function(){
        var b64='$b64';
        var bin=atob(b64);
        var len=bin.length;
        var buf=new ArrayBuffer(len);
        var arr=new Uint8Array(buf);
        for(var i=0;i<len;i++){ arr[i]=bin.charCodeAt(i); }
        var blob=new Blob([arr],{type:'image/jpeg'});
        var url=URL.createObjectURL(blob);
        var a=document.createElement('a');
        a.href=url; a.download='$fileName';
        document.body.appendChild(a);
        a.click();
        setTimeout(function(){URL.revokeObjectURL(url);document.body.removeChild(a);},2000);
      })();
    """);
  }

  void _shareImageMobile(Uint8List bytes, String fileName) {
    if (kDebugMode) debugPrint('Share image: $fileName (${bytes.length} bytes)');
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final invNum = invoice.invoiceNumber.toString().padLeft(4, '0');
    final dateStr = DateFormat('MMMM dd, yyyy').format(invoice.invoiceDate);
    final printedStr = DateFormat('MMM dd, yyyy – hh:mm a').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFD0D0D0),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlueDark,
        foregroundColor: Colors.white,
        title: Text('Invoice Preview  #$invNum'),
        actions: [
            // ── Export Invoice as Image ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 12),
            child: ElevatedButton(
              onPressed: _exportingImg ? null : _exportImage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _exportingImg
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('جاري التصدير...',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/company_logo.png',
                          width: 22,
                          height: 22,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.image_rounded, size: 18),
                        ),
                        const SizedBox(width: 8),
                        const Text('Export Image',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
            ),
          ),
        ],
      ),
      // ── Body: A4 preview + bottom Export button ───────────────────────
      body: Column(
        children: [
          // Top hint bar
          Container(
            width: double.infinity,
            color: AppTheme.primaryBlueDark,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white60, size: 15),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Preview your invoice below. Press "Export Image" to download as JPEG.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          // A4 invoice preview
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  children: [
                    RepaintBoundary(
                      key: _invoiceKey,
                      child: SizedBox(
                        width: _kA4W,
                        child: _A4InvoicePage(
                          invoice: invoice,
                          invNum: invNum,
                          dateStr: dateStr,
                          printedStr: printedStr,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── A4 Invoice Page ──────────────────────────────────────────────────────────
// A4 dimensions at 96 dpi
const double _kA4W = 794;
const double _kA4H = 1123;

class _A4InvoicePage extends StatelessWidget {
  final Invoice invoice;
  final String invNum;
  final String dateStr;
  final String printedStr;

  const _A4InvoicePage({
    required this.invoice,
    required this.invNum,
    required this.dateStr,
    required this.printedStr,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kA4W,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kA4H),
        child: IntrinsicHeight(
          child: Container(
            width: _kA4W,
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
          // ── TOP HEADER ─────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryBlueDark, Color(0xFF1B5E20)],
                begin: Alignment.topLeft,
                end: Alignment.topRight,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo + company name
                Image.asset(
                  'assets/images/company_logo.png',
                  width: 64,
                  height: 64,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.business_rounded,
                      color: Colors.white,
                      size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('VINEX TECHNOLOGY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          )),
                      const SizedBox(height: 8),
                      // Address
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 11,
                              color: Colors.white.withValues(alpha: 0.65)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Baghdad, Yarmouk, Al-Fakhri 2 Building',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 10,
                                  letterSpacing: 0.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Phone
                      Row(
                        children: [
                          Icon(Icons.phone_outlined,
                              size: 11,
                              color: Colors.white.withValues(alpha: 0.65)),
                          const SizedBox(width: 4),
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
                // Invoice badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4)),
                      ),
                      child: const Text('INVOICE',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 3)),
                    ),
                    const SizedBox(height: 6),
                    Text('#$invNum',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          // ── INFO ROW (Bill To + Invoice Details) ───────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bill To
                Expanded(
                  child: _InfoCard(
                    title: 'BILL TO',
                    accentColor: AppTheme.primaryBlue,
                    rows: [
                      _FieldRow('Customer', invoice.customerName),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Invoice Details
                Expanded(
                  child: _InfoCard(
                    title: 'INVOICE DETAILS',
                    accentColor: const Color(0xFF2E7D32),
                    rows: [
                      _FieldRow('Invoice No.', '#$invNum'),
                      _FieldRow('Date', dateStr),
                      _FieldRow('Items', '${invoice.items.length} item(s)'),
                      _FieldRow('Printed', printedStr),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── ITEMS TABLE ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: _ItemsTable(invoice: invoice),
          ),

          const SizedBox(height: 20),

          // ── NOTES + TOTALS ROW ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Notes (left side)
                if (invoice.notes.isNotEmpty)
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDE7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFECB3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('NOTES',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF795548),
                                  letterSpacing: 1)),
                          const SizedBox(height: 6),
                          Text(invoice.notes,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textDark,
                                  height: 1.4)),
                        ],
                      ),
                    ),
                  )
                else
                  const Expanded(flex: 3, child: SizedBox()),
                const SizedBox(width: 16),
                // Totals (right side)
                Expanded(
                  flex: 2,
                  child: _TotalsBox(invoice: invoice),
                ),
              ],
            ),
          ),

          const Spacer(),

          // ── FOOTER ────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Thank you for your business!',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textGrey,
                        fontStyle: FontStyle.italic)),
                Text('VINEX TECHNOLOGY © 2025',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
          ),
        ),
      ),
    );
  }
}

// ── Info Card (Bill To / Invoice Details) ────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final String title;
  final Color accentColor;
  final List<_FieldRow> rows;

  const _InfoCard(
      {required this.title,
      required this.accentColor,
      required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: rows
                  .map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 70,
                              child: Text(r.label,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textGrey)),
                            ),
                            const Text(': ',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textGrey)),
                            Expanded(
                              child: Text(r.value,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: (r.label == 'Customer' ||
                                              r.label == 'Invoice No.' ||
                                              r.label == 'Date')
                                          ? const Color(0xFFCC0000)
                                          : Colors.black)),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow {
  final String label;
  final String value;
  const _FieldRow(this.label, this.value);
}

// ── Items Table ───────────────────────────────────────────────────────────────
class _ItemsTable extends StatelessWidget {
  final Invoice invoice;
  const _ItemsTable({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: const Row(
              children: [
                SizedBox(
                    width: 32,
                    child: Text('#',
                        style: _thStyle,
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 5,
                    child: Text('ITEM NAME', style: _thStyle)),
                SizedBox(
                    width: 60,
                    child: Text('QTY',
                        style: _thStyle,
                        textAlign: TextAlign.center)),
                SizedBox(
                    width: 110,
                    child: Text('UNIT PRICE',
                        style: _thStyle,
                        textAlign: TextAlign.right)),
                SizedBox(
                    width: 110,
                    child: Text('AMOUNT',
                        style: _thStyle,
                        textAlign: TextAlign.right)),
              ],
            ),
          ),
          // Data rows
          ...invoice.items.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final isEven = idx % 2 == 0;
            final isLast = idx == invoice.items.length - 1;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isEven ? Colors.white : const Color(0xFFF0F4FF),
                borderRadius: isLast
                    ? const BorderRadius.vertical(
                        bottom: Radius.circular(7))
                    : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue
                            .withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${item.sequence}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryBlue)),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(item.itemName,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark)),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      item.quantity % 1 == 0
                          ? item.quantity.toInt().toString()
                          : item.quantity.toStringAsFixed(2),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF333333)),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(CurrencyHelper.format(item.unitPrice),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF555555))),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(CurrencyHelper.format(item.totalPrice),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

const _thStyle = TextStyle(
  color: Colors.white,
  fontSize: 10,
  fontWeight: FontWeight.bold,
  letterSpacing: 0.5,
);

// ── Totals Box ────────────────────────────────────────────────────────────────
class _TotalsBox extends StatelessWidget {
  final Invoice invoice;
  const _TotalsBox({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final hasDiscount = invoice.discount > 0;
    final subtotal = invoice.subtotal;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          // Subtotal row (only show when discount exists)
          if (hasDiscount) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subtotal',
                      style: TextStyle(
                          fontSize: 10, color: AppTheme.textGrey)),
                  Text(CurrencyHelper.format(subtotal),
                      style: const TextStyle(
                          fontSize: 10, color: Colors.black)),
                ],
              ),
            ),
            // Discount row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.discount_outlined,
                          size: 11, color: Color(0xFFE65100)),
                      const SizedBox(width: 4),
                      const Text('Discount',
                          style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFFE65100),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Text('- ${CurrencyHelper.format(invoice.discount)}',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFE65100),
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 14, thickness: 0.8),
            ),
          ] else
            const SizedBox(height: 4),
          // Grand total
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                begin: Alignment.topLeft,
                end: Alignment.topRight,
              ),
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(7)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8)),
                Text(CurrencyHelper.format(invoice.totalAmount),
                    style: const TextStyle(
                        color: Color(0xFFFFFF00),
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
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
                              fontSize: 11,
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
                            fontSize: 13, color: Colors.black, height: 1.4)),
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
                                  fontSize: 22)),
                        ],
                      ),
                    ),
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
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('GRAND TOTAL',
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    letterSpacing: 1)),
                            SizedBox(height: 2),
                            Text('After discount',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 10)),
                          ],
                        ),
                        Text(
                          CurrencyHelper.format(_grandTotal),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
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
