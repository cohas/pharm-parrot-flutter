// MainScreen.dart
//
// [알림] 앱 루트(MaterialApp)에 로컬 로컬리제이션을 추가하세요.
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
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../services/native_tts_service.dart';
import '../services/com_port_service.dart';
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
  basic,        // 기본
  modern,       // 모던
  contrast,     // 고대비
  highContrast  // 최고대비
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
  late final ComPortService _comPortService;

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
  
  // COM Port 설정
  bool _useComPort = true;
  int _selectedComPort = 4; // 기본값: COM4

  @override
  void initState() {
    super.initState();
    _sb = SupabaseService(Supabase.instance.client);
    
    unawaited(_initialize());

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
    _comPortService.dispose();
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

  // 날짜 선택 다이얼로그(직접 CalendarDatePicker)
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
        onHeadSelected(_rxHeads.first);
        _setResult('처방 ${_rxHeads.length}건 로드 완료 ($d).');
      } else {
        _setResult('해당 날짜($d)의 처방이 없습니다.');
      }
    } catch (e) {
      _setResult('RxHead 조회 실패: $e', error: true);
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
        onHeadSelected(_rxHeads.first);
        _setResult('이름($q)으로 ${_rxHeads.length}건.');
      } else {
        _setResult('이름($q) 조회 결과 없음.');
      }
    } catch (e) {
      _setResult('이름으로 RxHead 조회 실패: $e', error: true);
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
      _setResult('RxRecipe 조회 실패: $e', error: true);
    }
  }

  // 상태별 색상 - 디자인 모드에 따라 변경
  Color _statusColor(int checked, int total) {
    switch (_pageDesignMode) {
      case PageDesignMode.basic:
        // 기본: 은은하고 부드러운
        if (checked > total) return const Color(0xFFFFE0B2); // 연한 주황색
        if (checked == total) return const Color(0xFFC8E6C9); // 연한 녹색
        if (checked >= 1) return const Color(0xFFBBDEFB); // 연한 파란색
        return const Color(0xFFF5F5F5); // 연한 회색
      
      case PageDesignMode.modern:
        // 모던: 세련된 그라데이션 느낌
        if (checked > total) return const Color(0xFFFF9800); // 선명하지만은 주황색
        if (checked == total) return const Color(0xFF66BB6A); // 부드러운 녹색
        if (checked >= 1) return const Color(0xFF42A5F5); // 밝은 파란색
        return const Color(0xFFECEFF1); // 밝은 회색
      
      case PageDesignMode.contrast:
        // 고대비: 명확한 구분
        if (checked > total) return const Color(0xFFFF6F00); // 진한 주황색
        if (checked == total) return const Color(0xFF43A047); // 진한 녹색
        if (checked >= 1) return const Color(0xFF1E88E5); // 진한 파란색
        return const Color(0xFFE0E0E0); // 중간 회색
      
      case PageDesignMode.highContrast:
        // 최고대비: 최대 가시성
        if (checked > total) return const Color(0xFFE65100); // 매우 진한 주황색
        if (checked == total) return const Color(0xFF2E7D32); // 매우 진한 녹색
        if (checked >= 1) return const Color(0xFF1565C0); // 매우 진한 파란색
        return const Color(0xFF424242); // 어두운 회색
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


  Future<void> handleBarcode(String input) async {
  // 0) 기본 가드
  var inputBarcode = input.trim().replaceAll('(', '').replaceAll(')', '');
  if (inputBarcode.isEmpty) return;
  if (inputBarcode.length >= 4 && inputBarcode.toLowerCase().startsWith('http')) return;
  if (inputBarcode.length < 13) return;

  // 1) 바코드 정규화
  final raw = inputBarcode;
  String baseBarcode;
  String packSerial = '';

  // C#: if (raw.Length >= 16) { base = raw.Substring(3, 13); pack = raw.Substring(16); } else base = raw;
  if (raw.length >= 16) {
    // substring(start, endExclusive) 이므로 3..15(포함) → end=16
    baseBarcode = raw.substring(3, 16);
    packSerial = raw.substring(16);
  } else {
    baseBarcode = raw;
  }

  // 2) 포장 단위(unit) 조회
  num unitDecimal = 1;
  try {
    final unitResp = await _sb.rpc('get_unit_from_pack_barcode', {'_pack_barcode': baseBarcode});
    final unitStr = unitResp?.toString().trim();
    if (unitStr != null && unitStr.isNotEmpty) {
      final parsed = num.tryParse(unitStr);
      if (parsed != null) unitDecimal = parsed;
    }
  } catch (_) {
    unitDecimal = 1;
  }
  final int delta = max(1, unitDecimal.round());

  // 3) RxRecipes에서 바코드 매칭
  // 요구사항 반영: type == 'E'는 12자리, 그 외(정제 T)는 11자리 비교
  final candidates = _rxRecipes.where((r) {
    final code = (r['pack_barcode'] ?? '').toString().trim();
    final t = (r['type'] ?? r['T'] ?? r['typeCode'] ?? '').toString().trim().toUpperCase();
    if (code.isEmpty) return false;

    if (t == 'E') {
      if (baseBarcode.length < 12 || code.length < 12) return false;
      return code.substring(0, 12) == baseBarcode.substring(0, 12);
    } else {
      final key11 = baseBarcode.length >= 11 ? baseBarcode.substring(0, 11) : baseBarcode;
      return code.length >= 11 && code.substring(0, 11) == key11;
    }
  }).toList();

  if (candidates.isEmpty) {
    await _tts.beep(1600, 1200);
    _setResult('바코드 매칭 실패: 일치하는 약품이 없습니다.', error: true);

    // 미스매치 후보 보여주기 (C#과 동일)
    try {
      final mm = await _sb.rpc('get_miss_mached_drug', {'_pack_barcode': baseBarcode});
      // 서버가 JSON 배열을 문자열로 줄 수도/이미 List로 줄 수도 있으니 방어적으로 처리
      if (mm != null) {
        final list = (mm is List) ? mm : [];
        for (final item in list) {
          final productName = item['product_name']?.toString() ?? '';
          final location = item['location']?.toString() ?? '';
          if (productName.isNotEmpty) {
            _setResult('$productName\n위치: $location');
          }
        }
      }
    } catch (e) {
      _setResult('미스매치 약품 정보 파싱 오류: $e');
    }
    return;
  }

  // 4) 타겟 선택: "완료되지 않은 항목"이 우선 (C#의 OrderBy(notComplete ? 0 : 1)와 동등)
  Map<String, dynamic> target = candidates.reduce((a, b) {
    final aChecked = asNum(a['checked_amount'] ?? a['Checked']);
    final aTotal   = asNum(a['total'] ?? a['Total']);
    final bChecked = asNum(b['checked_amount'] ?? b['Checked']);
    final bTotal   = asNum(b['total'] ?? b['Total']);

    final aNotComplete = aChecked < aTotal;
    final bNotComplete = bChecked < bTotal;

    if (aNotComplete && !bNotComplete) return a;
    if (!aNotComplete && bNotComplete) return b;
    return a; // 동률이면 a 유지(첫 번째 것)
  });

  // rxrecipe_id 보정(C#은 여러 키 시도)
  num rxrecipeId = asNum(target['rxrecipe_id']);
  if (rxrecipeId <= 0) rxrecipeId = asNum(target['rxRecipeID']);
  if (rxrecipeId <= 0) rxrecipeId = asNum(target['RxRecipeId']);

  if (rxrecipeId <= 0) {
    await _tts.beep(1500, 1200);
    _setResult('바코드 처리 실패: 선택된 항목의 rxrecipe_id를 찾을 수 없습니다.', error: true);
    return;
  }

  // 5) 성공 beep + TTS
  await _tts.beep(500, 500);

  final rawDrugName = (target['product_name'] ??
      target['약품명'] ??
      target['name'] ??
      '').toString();
  final drugName = rawDrugName.split(RegExp(r'[_(]')).first;
  final drugType = (target['type'] ?? target['T'] ?? '').toString().trim().toUpperCase();

  final dose  = asNum(target['dose'] ?? target['용량']);
  final times = asNum(target['times'] ?? target['횟수']);
  final days  = asNum(target['days'] ?? target['일수']);

  // C#: each = Math.Round(dose * times * days, 1, AwayFromZero)
  final num eachRaw = dose * times * days;
  final String eachOneDecimal = (eachRaw is double || eachRaw is int)
      ? (eachRaw.toDouble()).toStringAsFixed(1)
      : eachRaw.toString();

  if (drugType == 'E') {
    // C#은 "개!"로 읽음
    await _speak('$drugName, $eachOneDecimal개!');
  } else {
    await _speak('$drugName, ${fmtNum(dose)}정, ${fmtNum(times)}회, ${fmtNum(days)}일, 총 $eachOneDecimal개');
  }

  // 6) DB: checked_amount 증가
  try {
    final incResp = await _sb.rpc('update_checked_amount_and_packserial', {
      '_rxrecipe_id': rxrecipeId,
      '_delta': delta,
      '_pack_serial': packSerial,
    });

    int affected = 0;
    if (incResp != null) {
      affected = int.tryParse(incResp.toString().trim().replaceAll('"', '')) ?? 0;
    }

    // [1] 중복 처리 (affected == 0)
    if (affected == 0) {
      await _tts.beep(900, 300);
      // 음성 피드백(선택)
      await _speak('중복된 바코드입니다');
      _setResult('[중복] 이미 처리된 바코드입니다. ($drugName)', error: true);
      return;
    }

  // 현재 수치 읽기
  final checkedNow = asNum(target['checked_amount'] ?? target['Checked']);
  final totalVal   = asNum(target['total'] ?? target['Total']);
  // 제한 판단은 증가 전 상태로 결정: 이미 완료 상태였다면 이후 스캔은 제한으로 표시
  final bool wasCompleteBefore = packSerial.isEmpty && checkedNow >= totalVal;

  // [2] 정상 증가 처리 (UI 반영) - DB가 업데이트되었으므로 UI도 반영
  final int newChecked = max(0, min(32767, checkedNow.round() + affected));
    // 서로 다른 키 가능성 대응
    if (target.containsKey('checked_amount')) {
      target['checked_amount'] = newChecked;
    } else {
      target['Checked'] = newChecked;
    }

    // UI 갱신
    setState(() {});

    // [3] packSerial이 없는 경우: 증가 전 이미 전량 완료였다면 경고 메시지 표시 (UI는 이미 업데이트됨)
    if (wasCompleteBefore) {
      await _tts.beep(1000, 400);
      _setResult('[제한] $drugName 이미 ${fmtNum(newChecked)}/${fmtNum(totalVal)}개 완료됨.', error: true);
      return;
    }

    // [4] 정상 완료 메시지
    _setResult('체크 완료: $drugName +$delta (현재 ${fmtNum(newChecked)}/${fmtNum(totalVal)})');
  } catch (e) {
    await _tts.beep(1500, 900);
    _setResult('체크 수량 증가 실패: $e', error: true);
  }
}

// --- 선택 영역 변경 시 환자명 TTS 및 로딩 (C# OnHeadSelected 대응) -------------
void onHeadSelected(dynamic row) {
  setState(() {
    _selectedHead = row;
  });

  final patientName = (row['patient_name'] ?? row['name'] ?? row['환자명'] ?? '').toString();
  if (patientName.isNotEmpty) {
    // 환자명 읽기
    _speak(patientName);
  }

  final tfn = asNum(row['tfn']);
  _loadRecipesByTfn(tfn);
}

// --- C# RecalcDispenseTotals와 동등한 합계 계산 ------------------------------
Map<String, String> calculateTotals(int selectedSeparation) {
  num m = 0, a = 0, e = 0, n = 0;

  for (final it in _rxRecipes) {
    if (!asBool(it['use'], true)) continue;
    final sep = asNum(it['separate'], -999).toInt();
    if (selectedSeparation != 0 && sep != selectedSeparation) continue;

    final typeCode = (it['type']?.toString() ?? it['T']?.toString() ?? '').trim().toUpperCase();
    final isPill = typeCode == 'T';

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

  void _refreshSeparationOptions() {
    _separationOptions
      ..clear()
      ..addAll(
        _rxRecipes
            .where((e) => asBool(e['use'], false))
            .map((e) => asNum(e['separate'], -999).toInt())
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 라벨
                  Text(
                    item['label'] as String,
                    style: TextStyle(
                      fontSize: 9,
                      color: _pageDesignMode == PageDesignMode.highContrast 
                          ? Colors.white 
                          : Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 값
                  Container(
                    width: 42,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (item['key'] == 'dose')
                          ? getDoseColor(asNum(data[item['key']]))
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      fmtNum(asNum(data[item['key']])),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: (item['key'] == 'dose' && asNum(data[item['key']]) >= 2)
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Future<void> _showSettingsDialog() async {
    // 다이얼로그용 임시 변수
    int tempComPort = _selectedComPort;
    bool tempUseComPort = _useComPort;
    PageDesignMode tempDesignMode = _pageDesignMode;
    
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('설정'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '화면 디자인 모드',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  RadioListTile<PageDesignMode>(
                    title: const Text('기본'),
                    subtitle: const Text('은은하고 부드러운 느낌'),
                    value: PageDesignMode.basic,
                    groupValue: tempDesignMode,
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => tempDesignMode = val);
                      }
                    },
                  ),
                  RadioListTile<PageDesignMode>(
                    title: const Text('모던'),
                    subtitle: const Text('세련되고 현대적인 느낌'),
                    value: PageDesignMode.modern,
                    groupValue: tempDesignMode,
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => tempDesignMode = val);
                      }
                    },
                  ),
                  RadioListTile<PageDesignMode>(
                    title: const Text('고대비'),
                    subtitle: const Text('명확한 구분과 강한 색상'),
                    value: PageDesignMode.contrast,
                    groupValue: tempDesignMode,
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => tempDesignMode = val);
                      }
                    },
                  ),
                  RadioListTile<PageDesignMode>(
                    title: const Text('최고대비'),
                    subtitle: const Text('최대 가시성과 접근성'),
                    value: PageDesignMode.highContrast,
                    groupValue: tempDesignMode,
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => tempDesignMode = val);
                      }
                    },
                  ),
                  const Divider(height: 32),
                  const Text(
                    'COM Port 설정 (Windows)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('COM Port 사용'),
                    subtitle: const Text('바코드 스캐너를 COM Port로 연결'),
                    value: tempUseComPort,
                    onChanged: (val) {
                      setDialogState(() {
                        tempUseComPort = val;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Text('COM Port 번호:', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButton<int>(
                            value: tempComPort,
                            isExpanded: true,
                            items: List.generate(20, (i) => i + 1)
                                .map((port) => DropdownMenuItem(
                                      value: port,
                                      child: Text('COM$port'),
                                    ))
                                .toList(),
                            onChanged: tempUseComPort ? (val) {
                              if (val != null) {
                                setDialogState(() {
                                  tempComPort = val;
                                });
                              }
                            } : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                // 설정 저장
                setState(() {
                  _selectedComPort = tempComPort;
                  _useComPort = tempUseComPort;
                  _pageDesignMode = tempDesignMode;
                });
                
                // 디스크에 설정 저장
                _saveSettings();

                // COM Port 설정 업데이트
                _comPortService.updateSettings(
                  useComPort: tempUseComPort,
                  comPortNumber: tempComPort,
                );
                
                Navigator.of(ctx).pop();
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initialize() async {
    await _loadSettings();

    // COM Port 서비스 초기화
    _comPortService = ComPortService(
      useComPort: _useComPort,
      comPortNumber: _selectedComPort,
      onBarcodeReceived: (barcode) {
        // COM Port에서 수신된 원본 데이터 표시
        _setResult('COM Port: $barcode');
        // 잠시 후 바코드 처리 시작
        Future.delayed(const Duration(milliseconds: 500), () {
          handleBarcode(barcode);
        });
      },
    );
    
    // Windows 플랫폼이면 COM Port 자동 연결 시도
    if (Platform.isWindows && _useComPort) {
      _comPortService.connect();
    }
    
    await _loadByDate(_selectedDate);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useComPort = prefs.getBool('useComPort') ?? true;
      _selectedComPort = prefs.getInt('selectedComPort') ?? 4;
      final designModeName = prefs.getString('pageDesignMode');
      _pageDesignMode = PageDesignMode.values.firstWhere(
        (e) => e.name == designModeName,
        orElse: () => PageDesignMode.basic,
      );
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useComPort', _useComPort);
    await prefs.setInt('selectedComPort', _selectedComPort);
    await prefs.setString('pageDesignMode', _pageDesignMode.name);
  }

  @override
  Widget build(BuildContext context) {
    final totals = calculateTotals(_selectedSeparation);

    return GestureDetector(
      onTap: () {
        // 화면 아무곳이나 터치하면 바코드 입력창에 포커스
        _barcodeFocusNode.requestFocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PharmParrot'),
          backgroundColor: _getAppBarColor(),
          foregroundColor: Colors.white,
          elevation: _pageDesignMode == PageDesignMode.modern ? 0 : 4,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettingsDialog,
              tooltip: '설정',
            ),
          ],
        ),
        body: SafeArea(
        child: Column(
          children: [
            // 상단 검색(날짜)
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
                          child: const Text('오늘'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '이름',
                        isDense: true,
                      ),
                      onChanged: (v) => _nameQuery = v,
                      onSubmitted: (v) => _loadByName(v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _loadByName(_nameQuery),
                    child: const Text('이름 검색'),
                  ),
                ],
              ),
            ),

            // 중앙 영역(목록 + 결과/바코드스캔): 상단 영역 상대적으로 작게 할 flex:7
            Expanded(
              flex: 4,
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
                          final name = (h['patient_name'] ?? h['name'] ?? h['환자명'] ?? '').toString();
                          final birth = (h['patient_birth'] ?? h['birth_date'] ?? h['생년월일'] ?? '').toString();
                          final isComplete = asBool(h['is_complete']);
                          final isSelected = identical(h, _selectedHead);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: Text('[$no] $name ($birth)', style: const TextStyle(fontSize: 16, height: 1.2)),
                            selected: isSelected,
                            tileColor: isComplete ? _getCompleteBgColor() : null,
                            selectedTileColor: isSelected ? Colors.blue.shade200 : null,
                            onTap: () {
                              onHeadSelected(h);
                              // 항목 선택 후 바코드 입력창에 포커스 복원
                              _barcodeFocusNode.requestFocus();
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  // 우측 결과/바코드스캔
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
                                  const SnackBar(content: Text('결과 텍스트가 클립보드에 복사되었습니다.')),
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
                              labelText: '바코드 스캔',
                              hintText: '바코드를 스캔하세요',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.qr_code_scanner),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            onSubmitted: (value) async {
                              if (value.isNotEmpty) {
                                await handleBarcode(value);
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

            // 집계/분할 영역
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(8),
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
                          ? '환자명을 선택하세요'
                          : '${_selectedHead['patient_name'] ?? ''} ${_selectedHead['patient_birth'] ?? ''}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(height: 32, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 12)),
                  Expanded(
                    flex: 3,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(children: [const Text('아침', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(height: 2), Text(totals['m'] ?? '0', style: const TextStyle(fontSize: 14))]),
                        Column(children: [const Text('점심', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(height: 2), Text(totals['a'] ?? '0', style: const TextStyle(fontSize: 14))]),
                        Column(children: [const Text('저녁', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(height: 2), Text(totals['e'] ?? '0', style: const TextStyle(fontSize: 14))]),
                        Column(children: [const Text('자기전', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), const SizedBox(height: 2), Text(totals['n'] ?? '0', style: const TextStyle(fontSize: 14))]),
                      ],
                    ),
                  ),
                  Container(height: 32, width: 1, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 12)),
                  Expanded(
                    flex: 2,
                    child: Row(
                      children: [
                        const Text('분할 번호:', style: TextStyle(fontWeight: FontWeight.bold)),
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

            // RxRecipe 리스트: 더 크게(central이 더 2배) 할 flex:10
            Expanded(
              flex: 10,
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
                        // 다이얼로그 닫힌 후 바코드 입력창에 포커스 복원
                        _barcodeFocusNode.requestFocus();
                      },
                      onTap: () {
                        // 단순 클릭 시에도 바코드 입력창 포커스 유지
                        _barcodeFocusNode.requestFocus();
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
                                        // 순서
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
                                        // 체크/총량 뱃지
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
                                        // 이름/코드
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
                                  // Location 표시 (오른쪽)
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
                              // 칩들의 텍스트 색상도 조정(Theme override)
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
      ),
    );
  }
}
