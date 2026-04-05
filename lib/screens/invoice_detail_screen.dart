import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';
import 'dart:convert' show base64Encode;
import 'package:path_provider/path_provider.dart';
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
  // ── حالات التصدير على الموبايل ───────────────────────────────────────────
  _ExportState _exportState = _ExportState.idle;
  Uint8List?   _generatedBytes;

  @override
  void initState() {
    super.initState();
    // على الموبايل: نبدأ توليد الصورة تلقائياً بعد أول frame
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _generateA4Image());
    }
  }

  // ── توليد ملف PDF في الخلفية (الموبايل) ─────────────────────────────────
  Future<void> _generateA4Image() async {
    if (!mounted) return;
    setState(() { _exportState = _ExportState.generating; });
    try {
      final invNum     = widget.invoice.invoiceNumber.toString().padLeft(4, '0');
      final dateStr    = DateFormat('MMMM dd, yyyy').format(widget.invoice.invoiceDate);

      // التقاط A4 كاملة بدقة 3× خارج الشاشة
      final bytes = await _captureFullA4(
        invNum: invNum, dateStr: dateStr,
      );
      if (mounted) setState(() { _generatedBytes = bytes; _exportState = _ExportState.ready; });
    } catch (e) {
      if (kDebugMode) debugPrint('generateA4 error: $e');
      if (mounted) setState(() { _exportState = _ExportState.error; });
    }
  }


  // ── خيارات مسارات الحفظ ───────────────────────────────────────────────────
  /// يجمع المسارات المتاحة على الجهاز ويعرض ديالوج الاختيار
  Future<void> _saveToGallery() async {
    if (_generatedBytes == null || !mounted) return;

    final invNum   = widget.invoice.invoiceNumber.toString().padLeft(4, '0');
    final fileName = 'Invoice_$invNum.pdf';

    // ── جمع المسارات المتاحة ────────────────────────────────────────────────
    final List<_SaveLocation> locations = [];

    if (Platform.isAndroid) {
      // 1) Downloads العام (متاح دائماً على Android)
      try {
        final dl = Directory('/storage/emulated/0/Download');
        if (await dl.exists()) {
          locations.add(_SaveLocation(
            label: 'مجلد التنزيلات',
            sublabel: 'Download/',
            icon: Icons.download_rounded,
            color: const Color(0xFF1565C0),
            path: dl.path,
          ));
        }
      } catch (_) {}

      // 2) Documents العام
      try {
        final dc = Directory('/storage/emulated/0/Documents');
        if (!await dc.exists()) await dc.create(recursive: true);
        locations.add(_SaveLocation(
          label: 'مجلد المستندات',
          sublabel: 'Documents/',
          icon: Icons.folder_rounded,
          color: const Color(0xFF6A1B9A),
          path: dc.path,
        ));
      } catch (_) {}

      // 3) مجلد خاص بالتطبيق داخل Downloads
      try {
        final extDirs = await getExternalStorageDirectories(
            type: StorageDirectory.downloads);
        if (extDirs != null && extDirs.isNotEmpty) {
          locations.add(_SaveLocation(
            label: 'مجلد التطبيق (Downloads)',
            sublabel: 'Android/data/.../files/downloads/',
            icon: Icons.inventory_2_rounded,
            color: const Color(0xFF2E7D32),
            path: extDirs.first.path,
          ));
        }
      } catch (_) {}

      // 4) مجلد المستندات الداخلي للتطبيق (دائماً متاح)
      try {
        final appDocs = await getApplicationDocumentsDirectory();
        locations.add(_SaveLocation(
          label: 'مجلد مستندات التطبيق',
          sublabel: 'Internal storage (private)',
          icon: Icons.storage_rounded,
          color: const Color(0xFF795548),
          path: appDocs.path,
        ));
      } catch (_) {}
    } else {
      final appDocs = await getApplicationDocumentsDirectory();
      locations.add(_SaveLocation(
        label: 'مجلد المستندات',
        sublabel: appDocs.path,
        icon: Icons.folder_rounded,
        color: const Color(0xFF1565C0),
        path: appDocs.path,
      ));
    }

    if (locations.isEmpty || !mounted) return;

    // ── عرض ديالوج الاختيار ────────────────────────────────────────────────
    final chosen = await showModalBottomSheet<_SaveLocation>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SaveLocationSheet(
        fileName: fileName,
        locations: locations,
      ),
    );

    if (chosen == null || !mounted) return;

    // ── الحفظ الفعلي ───────────────────────────────────────────────────────
    setState(() => _exportState = _ExportState.saving);
    try {
      await _writePdfToPath(_generatedBytes!, chosen.path, fileName);
      if (mounted) setState(() => _exportState = _ExportState.saved);
    } catch (e) {
      if (kDebugMode) debugPrint('savePDF error: $e');
      if (mounted) {
        setState(() => _exportState = _ExportState.error);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ فشل الحفظ: $e'), backgroundColor: Colors.red,
        ));
      }
    }
  }

  /// يكتب ملف PDF في المسار المحدد ويعرض رسالة نجاح
  Future<void> _writePdfToPath(
      Uint8List bytes, String dirPath, String fileName) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final file = File('$dirPath/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              '✅ تم حفظ الفاتورة بنجاح\n🖼 $fileName',
              style: const TextStyle(fontSize: 12),
            )),
          ]),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Export Image (ويب فقط) ────────────────────────────────────────────────
  final GlobalKey _invoiceKey = GlobalKey();
  bool _exportingWeb = false;

  Future<void> _exportImageWeb() async {
    if (_exportingWeb || !kIsWeb) return;
    setState(() => _exportingWeb = true);
    try {
      final invNum   = widget.invoice.invoiceNumber.toString().padLeft(4, '0');
      final fileName = 'Invoice_$invNum';
      await Future.delayed(const Duration(milliseconds: 200));
      final boundary = _invoiceKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('لم يتم العثور على الفاتورة');
      final ui.Image uiImage = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? pngData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (pngData == null) throw Exception('فشل تحويل الصورة');
      _downloadImageWeb(pngData.buffer.asUint8List(), '$fileName.jpg');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تم تحميل الفاتورة: $fileName.jpg'),
          backgroundColor: Colors.green, duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('exportImageWeb error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل تصدير الصورة: $e'), backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _exportingWeb = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return kIsWeb ? _buildWebView(context) : _buildMobileView(context);
  }

  // ════════════════════════════════════════════════════════════════
  // واجهة الويب — معاينة + تنزيل JPEG
  // ════════════════════════════════════════════════════════════════
  Widget _buildWebView(BuildContext context) {
    final invoice    = widget.invoice;
    final invNum     = invoice.invoiceNumber.toString().padLeft(4, '0');
    final dateStr    = DateFormat('MMMM dd, yyyy').format(invoice.invoiceDate);

    return Scaffold(
      backgroundColor: const Color(0xFFD0D0D0),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlueDark,
        foregroundColor: Colors.white,
        title: Text(
          invoice.isQuote
              ? 'معاينة عرض السعر  #$invNum'
              : 'معاينة الفاتورة  #$invNum',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 10),
            child: ElevatedButton.icon(
              onPressed: _exportingWeb ? null : _exportImageWeb,
              icon: _exportingWeb
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.image_outlined, size: 18),
              label: Text(_exportingWeb ? 'جاري التنزيل...' : 'Export Image',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: invoice.isQuote
                    ? const Color(0xFF6A1B9A)
                    : const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: invoice.isQuote
              ? const Color(0xFF7B5EA7)
              : AppTheme.primaryBlueDark,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Row(children: [
            Icon(
              invoice.isQuote
                  ? Icons.request_quote_outlined
                  : Icons.picture_as_pdf_rounded,
              color: Colors.white60, size: 15,
            ),
            const SizedBox(width: 8),
            Text(
              invoice.isQuote
                  ? 'معاينة عرض السعر — اضغط "Export Image" للتنزيل بصيغة JPEG'
                  : 'معاينة الفاتورة — اضغط "Export Image" للتنزيل بصيغة JPEG',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Center(child: RepaintBoundary(
            key: _invoiceKey,
            child: SizedBox(width: _kA4W, child: _A4InvoicePage(
              invoice: invoice, invNum: invNum,
              dateStr: dateStr,
            )),
          )),
        )),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // واجهة الموبايل — معاينة A4 كاملة مع تدوير وطباعة
  // ════════════════════════════════════════════════════════════════
  Widget _buildMobileView(BuildContext context) {
    final invoice    = widget.invoice;
    final invNum     = invoice.invoiceNumber.toString().padLeft(4, '0');
    final dateStr    = DateFormat('MMMM dd, yyyy').format(invoice.invoiceDate);

    // حساب الـ scale بحيث تملأ صفحة A4 العرض المتاح
    final screenW = MediaQuery.of(context).size.width;
    // هامش 12px من كل جانب = 24px إجمالاً
    const double hPad  = 12.0;
    final double availW = screenW - hPad * 2;
    final double scale  = availW / _kA4W;          // نسبة تصغير بحيث العرض يملأ الشاشة
    final double scaledPageH = _kA4H * scale;       // الارتفاع الفعلي للصفحة المصغرة

    return Scaffold(
      backgroundColor: const Color(0xFFCFD8DC),
      appBar: AppBar(
        backgroundColor: invoice.isQuote
            ? const Color(0xFF7B5EA7)
            : AppTheme.primaryBlueDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          invoice.isQuote
              ? 'معاينة عرض السعر  #$invNum'
              : 'معاينة الفاتورة  #$invNum',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [

          // ── شريط حالة التوليد ──────────────────────────────────
          _buildStatusBanner(),

          // ── معاينة A4 مع سكرول عمودي ──────────────────────────
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    // ظل خارجي يحاكي ورقة على سطح مكتب
                    Container(
                      width: availW,
                      height: scaledPageH,
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 18,
                            spreadRadius: 2,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      // نُقيّد الـ overflow ونُطبّق الـ scale
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          maxWidth:  _kA4W,
                          maxHeight: _kA4H,
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width:  _kA4W,
                              height: _kA4H,
                              // RepaintBoundary لالتقاط الصورة لاحقاً
                              child: RepaintBoundary(
                                key: _mobilePreviewKey,
                                child: _A4InvoicePage(
                                  invoice: invoice,
                                  invNum: invNum,
                                  dateStr: dateStr,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // تلميح صغير
                    Text(
                      'A4  ${_kA4W.toInt()} × ${_kA4H.toInt()} px',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),

          // ── زر الحفظ / التصدير ─────────────────────────────────
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: invoice.isQuote
                    ? const Color(0xFF7B5EA7)
                    : AppTheme.primaryBlueDark,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8, offset: const Offset(0, -3),
                  )
                ],
              ),
              child: _buildSaveButton(),
            ),
          ),
        ],
      ),
    );
  }

  // مفتاح للـ RepaintBoundary في المعاينة المصغرة (موبايل)
  final GlobalKey _mobilePreviewKey = GlobalKey();

  Widget _buildStatusBanner() {
    switch (_exportState) {
      case _ExportState.generating:
        return Container(
          width: double.infinity,
          color: const Color(0xFF1565C0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: const Row(children: [
            SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)),
            SizedBox(width: 10),
            Text('جاري تجهيز صورة A4 بدقة عالية…',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        );
      case _ExportState.ready:
        return Container(
          width: double.infinity, color: const Color(0xFF2E7D32),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Colors.white70, size: 16),
            SizedBox(width: 8),
            Text('صورة A4 جاهزة — اضغط زر الحفظ أدناه',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        );
      case _ExportState.saving:
        return Container(
          width: double.infinity, color: const Color(0xFF1565C0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: const Row(children: [
            SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)),
            SizedBox(width: 10),
            Text('جاري حفظ صورة A4 …',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        );
      case _ExportState.saved:
        return Container(
          width: double.infinity, color: const Color(0xFF1B5E20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: const Row(children: [
            Icon(Icons.image_rounded, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('✅ تم حفظ صورة A4 في المستندات',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
        );
      case _ExportState.error:
        return Container(
          width: double.infinity, color: const Color(0xFFB71C1C),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'خطأ في التوليد — اضغط "إعادة المحاولة"',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            )),
          ]),
        );
      case _ExportState.idle:
        return Container(
          width: double.infinity, color: AppTheme.primaryBlueDark,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: const Row(children: [
            Icon(Icons.crop_original_rounded, color: Colors.white60, size: 15),
            SizedBox(width: 8),
            Text('جاري تجهيز صورة A4…',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        );
    }
  }

  Widget _buildSaveButton() {
    final bool isGenerating = _exportState == _ExportState.generating;
    final bool isSaving     = _exportState == _ExportState.saving;
    final bool isSaved      = _exportState == _ExportState.saved;
    final bool isReady      = _exportState == _ExportState.ready;
    final bool isError      = _exportState == _ExportState.error;
    final bool isDisabled   = isGenerating || isSaving || isSaved;

    final Color btnColor = isSaved
        ? const Color(0xFF1B5E20)
        : isError ? const Color(0xFFB71C1C) : Colors.green.shade700;

    final Widget btnIcon = (isGenerating || isSaving)
        ? const SizedBox(width: 22, height: 22,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
        : isSaved
            ? const Icon(Icons.check_circle_rounded, size: 24)
            : const Icon(Icons.image_rounded, size: 24);

    final String btnLabel = isGenerating
        ? 'جاري تجهيز صورة A4…'
        : isSaving
            ? 'جاري حفظ الصورة…'
            : isSaved
                ? 'تم حفظ الصورة بنجاح ✔'
                : isError
                    ? 'إعادة المحاولة'
                    : 'حفظ الفاتورة كصورة PNG';

    return ElevatedButton.icon(
      onPressed: isDisabled ? null
          : isError ? _generateA4Image
          : isReady  ? _saveToGallery
          : null,
      icon: btnIcon,
      label: Text(btnLabel,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: btnColor,
        foregroundColor: Colors.white,
        disabledBackgroundColor: btnColor.withValues(alpha: 0.6),
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// يرسم الفاتورة بحجم A4 الكامل (794px) خارج الشاشة ويلتقطها
  /// النتيجة: صورة بحجم 2382 × ~3369 px (pixelRatio 3×) — جودة عالية
  Future<Uint8List> _captureFullA4({
    required String invNum,
    required String dateStr,
  }) async {
    // أنشئ RepaintBoundary خارج الشاشة داخل OverlayEntry مؤقت
    final completer = Completer<Uint8List>();
    final offKey = GlobalKey();

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        // خارج منطقة الرؤية تماماً
        left: -(_kA4W + 200),
        top: 0,
        child: RepaintBoundary(
          key: offKey,
          child: SizedBox(
            width: _kA4W,
            child: _A4InvoicePage(
              invoice: widget.invoice,
              invNum: invNum,
              dateStr: dateStr,
            ),
          ),
        ),
      ),
    );

    // أضف الـ overlay
    if (!mounted) throw Exception('Widget not mounted');
    Overlay.of(context).insert(entry);

    // انتظر عدة frames حتى يكتمل الرسم
    await Future.delayed(const Duration(milliseconds: 400));
    await WidgetsBinding.instance.endOfFrame;

    try {
      final boundary =
          offKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('لم يتم رسم الفاتورة');

      // التقاط بدقة 3× = 2382×~3369 px
      final img = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('فشل تحويل الصورة');
      completer.complete(byteData.buffer.asUint8List());
    } catch (e) {
      completer.completeError(e);
    } finally {
      entry.remove();
    }

    return completer.future;
  }

  // ── تنزيل الصورة على الويب ────────────────────────────────────────────────
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

}

// ── Export State Enum ──────────────────────────────────────────────────────
enum _ExportState { idle, generating, ready, saving, saved, error }

// ── نموذج بيانات موقع الحفظ ───────────────────────────────────────────────
class _SaveLocation {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final String path;
  const _SaveLocation({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.path,
  });
}

// ── BottomSheet اختيار مكان الحفظ ────────────────────────────────────────
class _SaveLocationSheet extends StatelessWidget {
  final String fileName;
  final List<_SaveLocation> locations;
  const _SaveLocationSheet({required this.fileName, required this.locations});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── مقبض السحب ─────────────────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── العنوان ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A3A5C).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.save_alt_rounded,
                      color: Color(0xFF1A3A5C), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('اختر مكان الحفظ',
                          style: TextStyle(fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A))),
                      Text(fileName,
                          style: TextStyle(fontSize: 11,
                              color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ]),
            ),

            const Divider(height: 20, indent: 20, endIndent: 20),

            // ── قائمة المواقع ───────────────────────────────────────────
            ...locations.map((loc) => _LocationTile(
              loc: loc,
              onTap: () => Navigator.pop(context, loc),
            )),

            // ── زر الإلغاء ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('إلغاء'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),

            // مسافة أمان للـ notch
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

// ── عنصر واحد في قائمة المواقع ───────────────────────────────────────────
class _LocationTile extends StatelessWidget {
  final _SaveLocation loc;
  final VoidCallback onTap;
  const _LocationTile({required this.loc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: loc.color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: loc.color.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: loc.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(loc.icon, color: loc.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.label,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold,
                        color: Colors.grey.shade900)),
                const SizedBox(height: 2),
                Text(loc.sublabel,
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade500),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            )),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.grey.shade400),
          ]),
        ),
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

  const _A4InvoicePage({
    required this.invoice,
    required this.invNum,
    required this.dateStr,
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
                      child: const Text(
                        'INVOICE',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 3),
                      ),
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

          // ── QUOTE BANNER (عرض السعر) ───────────────────────────────────
          if (invoice.isQuote)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: const BoxDecoration(
                color: Color(0xFF7B5EA7),
              ),
              child: const Center(
                child: Text(
                  'عرض سعر — Price Quotation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
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
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF795548),
                                  letterSpacing: 1)),
                          const SizedBox(height: 6),
                          Text(invoice.notes,
                              style: const TextStyle(
                                  fontSize: 14,
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
                        fontSize: 12,
                        color: AppTheme.textGrey,
                        fontStyle: FontStyle.italic)),
                Text('VINEX TECHNOLOGY © 2025',
                    style: TextStyle(
                        fontSize: 12,
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
                    fontSize: 13,
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
                              width: 80,
                              child: Text(r.label,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textGrey)),
                            ),
                            const Text(': ',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textGrey)),
                            Expanded(
                              child: Text(r.value,
                                  style: TextStyle(
                                      fontSize: 13,
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
                            fontWeight: FontWeight.bold,
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
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF333333)),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(CurrencyHelper.format(item.unitPrice),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF333333))),
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
                          fontSize: 13, color: AppTheme.textGrey)),
                  Text(CurrencyHelper.format(subtotal),
                      style: const TextStyle(
                          fontSize: 13, color: Colors.black)),
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
                              fontSize: 13,
                              color: Color(0xFFE65100),
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text('- ${CurrencyHelper.format(invoice.discount)}',
                      style: const TextStyle(
                          fontSize: 13,
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
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                begin: Alignment.topLeft,
                end: Alignment.topRight,
              ),
              borderRadius: invoice.hasDownPayment
                  ? BorderRadius.zero
                  : const BorderRadius.vertical(bottom: Radius.circular(7)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('TOTAL AMOUNT',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5)),
                Text(CurrencyHelper.format(invoice.totalAmount),
                    style: const TextStyle(
                        color: Color(0xFFFFFF00),
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // Down Payment & Remaining Amount
          if (invoice.hasDownPayment) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const Icon(Icons.payments_outlined,
                        size: 13, color: Color(0xFF1565C0)),
                    const SizedBox(width: 4),
                    const Text('Down Payment',
                        style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1565C0),
                            fontWeight: FontWeight.bold)),
                  ]),
                  Text(CurrencyHelper.format(invoice.downPayment),
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 14, thickness: 0.8),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.topRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Remaining Amount',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                  Text(CurrencyHelper.format(invoice.remainingAmount),
                      style: const TextStyle(
                          color: Color(0xFFFFFF00),
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
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
