// MainScreen.dart
//
// [�˸�] �� ��Ʈ(MaterialApp)�� ��Ķ ��������Ʈ�� �߰��ϼ���.
// import 'package:flutter_localizations/flutter_localizations.dart';
// return MaterialApp(
//   localizationsDelegates: const [
//     GlobalMaterialLocalizations.delegate,
//     GlobalWidgetsLocalizations.delegate,
//     GlobalCupertinoLocalizations.delegate,
//   ],
//   supportedLocales: const [Locale('ko'), Locale('en')],
//   // home: MainScreen(),
// );

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../services/native_tts_service.dart';
import '../widgets/patient_drug_dialog.dart';

num asNum(dynamic v, [num def = 0]) {
  if (v == null) return def;
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim()) ?? def;
  return def;
}

bool asBool(dynamic v, [bool def = false]) {
  if (v == null) return def;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return def;
}

String fmtNum(num v) {
  final n = v is double ? double.parse(v.toStringAsFixed(2)) : v;
  if (n is int || (n is double && n == n.roundToDouble())) {
    return n.round().toString();
  }
  return NumberFormat('0.##').format(n);
}

enum PageDesignMode {
  basic,        // �⺻
  modern,       // ���
  contrast,     // ���
  highContrast  // ����
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final SupabaseService _sb;
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final NativeTtsService _tts = NativeTtsService();
  final ScrollController _scrollController = ScrollController();

  static const double kTabletBreakpoint = 768.0;
  static const double kDesktopBreakpoint = 1024.0;

  bool get isDesktop => MediaQuery.of(context).size.width >= kDesktopBreakpoint;
  bool get isTablet =>
      MediaQuery.of(context).size.width >= kTabletBreakpoint &&
      MediaQuery.of(context).size.width < kDesktopBreakpoint;

  DateTime _selectedDate = DateTime.now();
  String _nameQuery = '';

  List<dynamic> _rxHeads = [];
  List<dynamic> _rxRecipes = [];
  dynamic _selectedHead;

  String _resultText = '';
  Color _resultColor = Colors.grey.shade300;

  final List<int> _separationOptions = [];
  int _selectedSeparation = 0; // 0 means none

  PageDesignMode _pageDesignMode = PageDesignMode.basic;

  @override
  void initState() {
    super.initState();
    _sb = SupabaseService(Supabase.instance.client);
    unawaited(_loadByDate(_selectedDate));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocusNode.requestFocus();
    });

    SystemChannels.lifecycle.setMessageHandler((msg) async {
      if (msg == AppLifecycleState.resumed.toString()) {
        _barcodeFocusNode.requestFocus();
      }
      return null;
    });
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TTS Error] $e');
      debugPrint('[TTS] $text');
    }
  }

  void _setResult(String msg, {bool error = false}) {
    setState(() {
      _resultText = '[${DateFormat('HH:mm:ss').format(DateTime.now())}] $msg';
      _resultColor = _getResultBgColor(error);
    });
  }

  // ��¥ ���� ���̾�α�(���� CalendarDatePicker)
  Future<void> _pickDateFix() async {
    await showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        return Dialog(
          child: Theme(
            data: ThemeData(
              datePickerTheme: const DatePickerThemeData(
                headerForegroundColor: Colors.black87,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    DateFormat('yyyy-MM').format(_selectedDate),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(
                  width: 360,
                  height: 360,
                  child: CalendarDatePicker(
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    onDateChanged: (DateTime date) {
                      setState(() => _selectedDate = date);
                      unawaited(_loadByDate(date));
                      Navigator.of(ctx).pop();
                    },
                    currentDate: DateTime.now(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadByDate(DateTime date) async {
    try {
      final d = DateFormat('yyyy-MM-dd').format(date);
      final resp =
          await _sb.rpc('select_rxhead_bydate', {'_selected_date': d});
      final list = (resp as List?) ?? [];
      setState(() {
        _rxHeads = list;
        _rxRecipes = [];
      });

      if (_rxHeads.isNotEmpty) {
        _onHeadSelected(_rxHeads.first);
        _setResult('ó�� ${_rxHeads.length}�� �ε� �Ϸ� ($d).');
      } else {
        _setResult('�ش� ��¥($d)�� ó���� �����ϴ�.');
      }
    } catch (e) {
      _setResult('RxHead ��ȸ ����: $e', error: true);
    }
  }

  Future<void> _loadByName(String name) async {
    final q = name.trim();
    if (q.isEmpty) return;
    try {
      final resp =
          await _sb.rpc('select_rxhead_by_name', {'_patient_name': q});
      final list = (resp as List?) ?? [];
      setState(() {
        _rxHeads = list;
        _rxRecipes = [];
      });
      if (_rxHeads.isNotEmpty) {
        _onHeadSelected(_rxHeads.first);
        _setResult('�̸�($q)���� ${_rxHeads.length}��.');
      } else {
        _setResult('�̸�($q) ��ȸ ��� ����.');
      }
    } catch (e) {
      _setResult('�̸����� RxHead ��ȸ ����: $e', error: true);
    }
  }

  Future<void> _loadRecipesByTfn(num tfn) async {
    try {
      final resp = await _sb
          .rpc('select_rxrecipe_by_textfile_number', {'_textfile_number': tfn});
      final list = (resp as List?) ?? [];
      setState(() {
        _rxRecipes = list;
      });
      _refreshSeparationOptions();
      _barcodeFocusNode.requestFocus();
    } catch (e) {
      _setResult('RxRecipe ��ȸ ����: $e', error: true);
    }
  }

  // ���º� ���� - ������ ���ο� ������
  Color _statusColor(int checked, int total) {
    switch (_pageDesignMode) {
      case PageDesignMode.basic:
        // �⺻: �ε巯�� �Ľ���
        if (checked > total) return const Color(0xFFFFE0B2); // ���� ������
        if (checked == total) return const Color(0xFFC8E6C9); // ���� ���
        if (checked >= 1) return const Color(0xFFBBDEFB); // ���� �Ķ�
        return const Color(0xFFF5F5F5); // ���� ���
      
      case PageDesignMode.modern:
        // ���: ���õ� �׶��̼� ����
        if (checked > total) return const Color(0xFFFF9800); // �������ִ� ������
        if (checked == total) return const Color(0xFF66BB6A); // �ż��� ���
        if (checked >= 1) return const Color(0xFF42A5F5); // ������ �Ķ�
        return const Color(0xFFECEFF1); // ������ ȸ��
      
      case PageDesignMode.contrast:
        // ���: ��Ȯ�� ����
        if (checked > total) return const Color(0xFFFF6F00); // ���� ������
        if (checked == total) return const Color(0xFF43A047); // ���� ���
        if (checked >= 1) return const Color(0xFF1E88E5); // ���� �Ķ�
        return const Color(0xFFE0E0E0); // �߰� ȸ��
      
      case PageDesignMode.highContrast:
        // ����: �ִ� ���μ�
        if (checked > total) return const Color(0xFFE65100); // �ſ� ���� ������
        if (checked == total) return const Color(0xFF2E7D32); // �ſ� ���� ���
        if (checked >= 1) return const Color(0xFF1565C0); // �ſ� ���� �Ķ�
        return const Color(0xFF424242); // ���� ȸ��
    }
  }

  Color _onColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance < 0.5 ? Colors.white : Colors.black87;
  }

  Color _getResultBgColor(bool error) {
    if (error) {
      switch (_pageDesignMode) {
        case PageDesignMode.basic:
          return const Color(0xFFFFCDD2);
        case PageDesignMode.modern:
          return const Color(0xFFEF5350);
        case PageDesignMode.contrast:
          return const Color(0xFFE53935);
        case PageDesignMode.highContrast:
          return const Color(0xFFC62828);
      }
    } else {
      switch (_pageDesignMode) {
        case PageDesignMode.basic:
          return const Color(0xFFF5F5F5);
        case PageDesignMode.modern:
          return const Color(0xFFECEFF1);
        case PageDesignMode.contrast:
          return const Color(0xFFE0E0E0);
        case PageDesignMode.highContrast:
          return const Color(0xFF616161);
      }
    }
  }

  Color _getCompleteBgColor() {
    switch (_pageDesignMode) {
      case PageDesignMode.basic:
        return const Color(0xFFFFF9C4);
      case PageDesignMode.modern:
        return const Color(0xFFFFEB3B);
      case PageDesignMode.contrast:
        return const Color(0xFFFDD835);
      case PageDesignMode.highContrast:
        return const Color(0xFFF57F17);
    }
  }

  Color _getAppBarColor() {
    switch (_pageDesignMode) {
      case PageDesignMode.basic:
        return const Color(0xFF90CAF9);
      case PageDesignMode.modern:
        return const Color(0xFF1976D2);
      case PageDesignMode.contrast:
        return const Color(0xFF1565C0);
      case PageDesignMode.highContrast:
        return const Color(0xFF0D47A1);
    }
  }

  Color _getCardBorderColor() {
    switch (_pageDesignMode) {
      case PageDesignMode.basic:
        return const Color(0xFFE0E0E0);
      case PageDesignMode.modern:
        return const Color(0xFF90A4AE);
      case PageDesignMode.contrast:
        return const Color(0xFF757575);
      case PageDesignMode.highContrast:
        return const Color(0xFF424242);
    }
  }

  Color _getLocationBgColor() {
    switch (_pageDesignMode) {
      case PageDesignMode.basic:
        return const Color(0xFFFFE082).withOpacity(0.4);
      case PageDesignMode.modern:
        return const Color(0xFFFF9800).withOpacity(0.2);
      case PageDesignMode.contrast:
        return const Color(0xFFFFA726);
      case PageDesignMode.highContrast:
        return const Color(0xFFF57C00);
    }
  }


  Future<void> _handleBarcode(String input) async {
    var inputBarcode = input.trim().replaceAll('(', '').replaceAll(')', '');
    if (inputBarcode.isEmpty) return;
    if (inputBarcode.length >= 4 &&
        inputBarcode.toLowerCase().startsWith('http')) return;
    if (inputBarcode.length < 13) return;

    // 1) ����ȭ
    final raw = inputBarcode;
    String baseBarcode;
    String packSerial = '';
    if (raw.length >= 16) {
      baseBarcode = raw.substring(3, 16);
      packSerial = raw.substring(16);
    } else {
      baseBarcode = raw;
    }

    // 2) ���� ��ȸ
    num unitDecimal = 1;
    try {
      final unitResp = await _sb
          .rpc('get_unit_from_pack_barcode', {'_pack_barcode': baseBarcode});
      final unitStr = unitResp?.toString().trim();
      if (unitStr != null && unitStr.isNotEmpty) {
        unitDecimal = num.tryParse(unitStr) ?? 1;
      }
    } catch (_) {
      unitDecimal = 1;
    }
    int delta = max(1, unitDecimal.round());

    // 3) �ĺ� ��Ī (T=11�ڸ�, E=12�ڸ�)
    final candidates = _rxRecipes.where((r) {
      final code = (r['pack_barcode'] ?? '').toString().trim();
      final t = (r['type'] ?? '').toString().trim().toUpperCase();
      if (code.isEmpty) return false;

      if (t == 'E') {
        if (baseBarcode.length < 12 || code.length < 12) return false;
        return code.substring(0, 12) == baseBarcode.substring(0, 12);
      } else {
        final key11 =
            baseBarcode.length >= 11 ? baseBarcode.substring(0, 11) : baseBarcode;
        return code.length >= 11 && code.substring(0, 11) == key11;
      }
    }).toList();

    if (candidates.isEmpty) {
      await _tts.beep(1600, 1200);
      _setResult('���ڵ� ��Ī ����: ��ġ�ϴ� ��ǰ�� �����ϴ�.', error: true);
      try {
        final mm =
            await _sb.rpc('get_miss_mached_drug', {'_pack_barcode': baseBarcode});
        if (mm != null) {
          for (final item in (mm as List? ?? [])) {
            final productName = item['product_name']?.toString() ?? '';
            final location = item['location']?.toString() ?? '';
            _setResult('$productName\n��ġ: $location');
          }
        }
      } catch (e) {
        _setResult('�̽���ġ ��ǰ ���� �Ľ� ����: $e');
      }
      return;
    }

    // 4) Ÿ�� ����(�̿Ϸ� �켱)
    var target = candidates.reduce((a, b) {
      final aChecked = asNum(a['checked_amount']);
      final aTotal = asNum(a['total']);
      final bChecked = asNum(b['checked_amount']);
      final bTotal = asNum(b['total']);
      final aNotComplete = aChecked < aTotal;
      final bNotComplete = bChecked < bTotal;
      if (aNotComplete && !bNotComplete) return a;
      if (!aNotComplete && bNotComplete) return b;
      return a;
    });

    final rxrecipeId = asNum(target['rxrecipe_id']);
    if (rxrecipeId <= 0) {
      await _tts.beep(1500, 1200);
      _setResult('���ڵ� ó�� ����: ���� �׸��� rxrecipe_id ����.', error: true);
      return;
    }

    // ���� beep
    await _tts.beep(500, 500);

    final drugName =
        (target['product_name'] ?? '').toString().split(RegExp(r'[_(]'))[0];
    final drugType = (target['type'] ?? '').toString().trim();

    // 5) TTS �ȳ�
    final dose = asNum(target['dose']);
    final times = asNum(target['times']);
    final days = asNum(target['days']);
    final each = (dose * times * days).round();
    
    if (drugType == 'E') {
      await _speak('$drugName, $each��');
    } else {
      await _speak('$drugName, $dose��, $timesȸ, $days��, �� $each��');
    }

    // 6) DB �ݿ�
    try {
      final incResp = await _sb.rpc('update_checked_amount_and_packserial', {
        '_rxrecipe_id': rxrecipeId,
        '_delta': delta,
        '_pack_serial': packSerial
      });

      int affected = 0;
      if (incResp != null) {
        affected = int.tryParse(incResp.toString().trim()) ?? 0;
      }

      // [1] �ߺ� ó�� (affected = 0)
      if (affected == 0) {
        await _tts.beep(900, 300);
        await _speak('�ߺ��� ���ڵ��Դϴ�');
        _setResult('[�ߺ�] �̹� ó���� ���ڵ��Դϴ�. ($drugName)', error: true);
        return;
      }

      // [2] DB�� ���������Ƿ� UI ������Ʈ
      final checkedNow = asNum(target['checked_amount']);
      final totalVal = asNum(target['total']);
      final newChecked = max(0, min(32767, (checkedNow + delta).round()));
      target['checked_amount'] = newChecked;
      setState(() {});

      // [3] packSerial�� ���� ���� �ʰ� �� ���
      if (packSerial.isEmpty && newChecked >= totalVal) {
        await _tts.beep(1000, 1200);
        _setResult('[����] $drugName �̹� $newChecked/$totalVal�� �Ϸ��.', error: true);
        return;
      }

      // [4] ���� �Ϸ� �޽���
      _setResult('üũ �Ϸ�: $drugName +$delta (���� $newChecked/$totalVal)');
    } catch (e) {
      await _tts.beep(1500, 900);
      _setResult('üũ ���� ���� ����: $e', error: true);
    }
  }

  void _onHeadSelected(dynamic row) {
    setState(() {
      _selectedHead = row;
    });
    
    // ȯ�� �̸� �о��ֱ�
    final patientName = (row['patient_name'] ?? row['name'] ?? row['ȯ�ڸ�'] ?? '').toString();
    if (patientName.isNotEmpty) {
      unawaited(_speak(patientName));
    }
    
    final tfn = asNum(row['tfn']);
    unawaited(_loadRecipesByTfn(tfn));
  }

  void _refreshSeparationOptions() {
    _separationOptions
      ..clear()
      ..addAll(
        _rxRecipes
            .where((e) => asBool(e['use'], false))
            .map((e) => asNum(e['seperate'], -999).toInt())
            .where((v) => v != -999)
            .toSet()
            .toList()
          ..sort(),
      );

    if (_separationOptions.isEmpty) {
      _selectedSeparation = 0;
    } else if (!_separationOptions.contains(_selectedSeparation)) {
      _selectedSeparation = _separationOptions.first;
    }
  }

  Map<String, String> _calculateTotals() {
    num m = 0, a = 0, e = 0, n = 0;
    for (final it in _rxRecipes) {
      if (!asBool(it['use'], true)) continue;
      if (_selectedSeparation != 0 &&
          asNum(it['seperate'], -999).toInt() != _selectedSeparation) continue;

      final typeCode = (it['type']?.toString() ?? '').trim();
      final isPill = typeCode.toUpperCase() == 'T';

      num vm = asNum(it['morning']);
      num va = asNum(it['afternoon']);
      num ve = asNum(it['evening']);
      num vn = asNum(it['night']);
      if (isPill) {
        vm = vm.ceil();
        va = va.ceil();
        ve = ve.ceil();
        vn = vn.ceil();
      }
      m += vm;
      a += va;
      e += ve;
      n += vn;
    }
    return {
      'm': fmtNum(m),
      'a': fmtNum(a),
      'e': fmtNum(e),
      'n': fmtNum(n),
    };
  }

  Widget _buildKeyValueChips(Map<String, dynamic> data) {
    final orderedKeysWithLabels = [
      {'key': 'seperate', 'label': 'Sprt'},
      {'key': 'checked_amount', 'label': 'Check'},
      {'key': 'total', 'label': 'Total'},
      {'key': 'dose', 'label': 'Dose'},
      {'key': 'times', 'label': 'Times'},
      {'key': 'days', 'label': 'Days'},
    ];

    Color getDoseColor(num dose) {
      if (dose >= 3) return Colors.purple.shade700;
      if (dose >= 2) return Colors.red.shade700;
      if (dose < 1) return Colors.blue.shade700;
      return Colors.grey.shade500;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        for (final item in orderedKeysWithLabels)
          if (data.containsKey(item['key'] as String))
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                width: 42,
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                decoration: BoxDecoration(
                  color: (item['key'] == 'dose')
                      ? getDoseColor(asNum(data['dose']))
                      : Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item['label'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${data[item['key'] as String] ?? ''}',
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.1,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _showSettingsDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('����'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '������ ������',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              RadioListTile<PageDesignMode>(
                title: const Text('�⺻'),
                subtitle: const Text('�ε巯�� �Ľ��� ����'),
                value: PageDesignMode.basic,
                groupValue: _pageDesignMode,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _pageDesignMode = val);
                    Navigator.of(ctx).pop();
                  }
                },
              ),
              RadioListTile<PageDesignMode>(
                title: const Text('���'),
                subtitle: const Text('���õǰ� ������ �ִ� ����'),
                value: PageDesignMode.modern,
                groupValue: _pageDesignMode,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _pageDesignMode = val);
                    Navigator.of(ctx).pop();
                  }
                },
              ),
              RadioListTile<PageDesignMode>(
                title: const Text('���'),
                subtitle: const Text('��Ȯ�� ���а� �߰� ���'),
                value: PageDesignMode.contrast,
                groupValue: _pageDesignMode,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _pageDesignMode = val);
                    Navigator.of(ctx).pop();
                  }
                },
              ),
              RadioListTile<PageDesignMode>(
                title: const Text('����'),
                subtitle: const Text('�ִ� ���μ��� ���� ���'),
                value: PageDesignMode.highContrast,
                groupValue: _pageDesignMode,
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _pageDesignMode = val);
                    Navigator.of(ctx).pop();
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('�ݱ�'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totals = _calculateTotals();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PharmParrot'),
        backgroundColor: _getAppBarColor(),
        foregroundColor: Colors.white,
        elevation: _pageDesignMode == PageDesignMode.modern ? 0 : 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
            tooltip: '����',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ��� ����(����)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickDateFix,
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final today = DateTime.now();
                            setState(() => _selectedDate = today);
                            unawaited(_loadByDate(today));
                          },
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(60, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text('����'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '�̸�',
                        isDense: true,
                      ),
                      onChanged: (v) => _nameQuery = v,
                      onSubmitted: (v) => _loadByName(v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _loadByName(_nameQuery),
                    child: const Text('�̸� �˻�'),
                  ),
                ],
              ),
            ),

            // �߾� ����(��� + ���/��ĳ��): ���� ���� �������� ��� �� flex:1
            Expanded(
              flex: 1,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // RxHead list
                  Expanded(
                    flex: 7,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: _getCardBorderColor(), width: 2),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      margin: const EdgeInsets.all(12),
                      child: ListView.separated(
                        itemCount: _rxHeads.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final h = _rxHeads[i];
                          final no = (h['no'] ?? '').toString();
                          final name = (h['patient_name'] ?? h['name'] ?? h['ȯ�ڸ�'] ?? '').toString();
                          final birth = (h['patient_birth'] ?? h['birth_date'] ?? h['�������'] ?? '').toString();
                          final isComplete = asBool(h['is_complete']);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Text('[$no] $name ($birth)', style: const TextStyle(fontSize: 16, height: 1.2)),
                            selected: identical(h, _selectedHead),
                            tileColor: isComplete ? _getCompleteBgColor() : null,
                            onTap: () => _onHeadSelected(h),
                          );
                        },
                      ),
                    ),
                  ),

                  // ���� ���/��ĳ��
                  Expanded(
                    flex: 3,
                    child: Container(
                      margin: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
                      child: Column(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onDoubleTap: () {
                                Clipboard.setData(ClipboardData(text: _resultText));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('��� �ؽ�Ʈ�� Ŭ�����忡 �����߾��.')),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _resultColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: _getCardBorderColor()),
                                ),
                                child: Text(
                                  _resultText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _onColor(_resultColor),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _barcodeController,
                            focusNode: _barcodeFocusNode,
                            decoration: const InputDecoration(
                              labelText: '���ڵ� ��ĵ',
                              hintText: '���ڵ带 ��ĵ�ϼ���',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.qr_code_scanner),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            onSubmitted: (value) async {
                              if (value.isNotEmpty) {
                                await _handleBarcode(value);
                                _barcodeController.clear();
                                _barcodeFocusNode.requestFocus();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // �հ�/�и� ����
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _pageDesignMode == PageDesignMode.modern 
                    ? const Color(0xFFECEFF1) 
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _getCardBorderColor()),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      _selectedHead == null
                          ? 'ȯ�ڸ� �����ϼ���'
                          : '${_selectedHead['patient_name'] ?? ''} ${_selectedHead['patient_birth'] ?? ''}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(height: 40, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 16)),
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(children: [const Text('��ħ', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(totals['m'] ?? '0', style: const TextStyle(fontSize: 16))]),
                        Column(children: [const Text('����', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(totals['a'] ?? '0', style: const TextStyle(fontSize: 16))]),
                        Column(children: [const Text('����', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(totals['e'] ?? '0', style: const TextStyle(fontSize: 16))]),
                        Column(children: [const Text('��ħ', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(totals['n'] ?? '0', style: const TextStyle(fontSize: 16))]),
                      ],
                    ),
                  ),
                  Container(height: 40, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 16)),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        const Text('�и� ����:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<int>(
                            isExpanded: true,
                            value: _separationOptions.contains(_selectedSeparation)
                                ? _selectedSeparation
                                : (_separationOptions.isNotEmpty ? _separationOptions.first : 0),
                            items: _separationOptions
                                .map((e) => DropdownMenuItem(value: e, child: Text(e.toString())))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedSeparation = v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // RxRecipe ����Ʈ: �� ũ��(central�� �� 2��) �� flex:2
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: _getCardBorderColor(), width: 2),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                margin: const EdgeInsets.all(12),
                child: ListView.separated(
                  controller: _scrollController,
                  itemCount: _rxRecipes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (ctx, i) {
                    final r = _rxRecipes[i];
                    final name = (r['product_name'] ?? '').toString();
                    final code = (r['pack_barcode'] ?? '').toString();
                    final location = (r['location'] ?? '').toString();
                    final checkedV = asNum(r['checked_amount']).toInt();
                    final totalV = asNum(r['total']);
                    final use = asBool(r['use'], true);
                    final isAtc = asBool(r['is_atc']);

                    final bg = _statusColor(checkedV, totalV.ceil());
                    final on = _onColor(bg);

                    return InkWell(
                      onDoubleTap: () async {
                        final updated = await showDialog(
                          context: context,
                          builder: (_) => PatientDrugDialog(
                            supabase: _sb,
                            patientId: (_selectedHead?['pid'] ?? '').toString(),
                            row: Map<String, dynamic>.from(r),
                          ),
                        );
                        if (updated is Map<String, dynamic>) {
                          setState(() => _rxRecipes[i] = updated);
                          _refreshSeparationOptions();
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 1),
                        decoration: BoxDecoration(
                          color: bg,
                          border: Border(
                            left: BorderSide(width: 4, color: on.withOpacity(0.9)),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        // ����
                                        Container(
                                          width: 30,
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${asNum(r["recipe_order"])}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: on.withOpacity(0.85),
                                            ),
                                          ),
                                        ),
                                        // üũ/�Ѱ� ����
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: on.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(width: 1.5, color: on.withOpacity(0.9)),
                                          ),
                                          child: Text(
                                            '$checkedV/${totalV.ceil()}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: on,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // �̸�/�ڵ�
                                        Flexible(
                                          child: Text(
                                            name.isEmpty ? code : name,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: !use
                                                  ? Colors.yellowAccent
                                                  : isAtc
                                                      ? Colors.blueAccent.shade100
                                                      : on,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (code.isNotEmpty) ...[
                                          const SizedBox(width: 12),
                                          Text(
                                            code,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: on.withOpacity(0.7),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // Location ǥ�� (������)
                                  if (location.isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      margin: const EdgeInsets.only(left: 8),
                                      decoration: BoxDecoration(
                                        color: _getLocationBgColor(),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: _pageDesignMode == PageDesignMode.highContrast 
                                              ? on.withOpacity(0.8) 
                                              : on.withOpacity(0.3),
                                          width: _pageDesignMode == PageDesignMode.highContrast ? 2 : 1,
                                        ),
                                      ),
                                      child: Text(
                                        location,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: on,
                                        ),
                                      ),
                                    ),
                                  ],
                                  Icon(Icons.edit, size: 18, color: on.withOpacity(0.9)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              // Ĩ ���� �ؽ�Ʈ ������ ����(Theme override)
                              Theme(
                                data: Theme.of(context).copyWith(
                                  textTheme: Theme.of(context).textTheme.apply(
                                        bodyColor: on,
                                        displayColor: on,
                                      ),
                                ),
                                child: _buildKeyValueChips(Map<String, dynamic>.from(r)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
