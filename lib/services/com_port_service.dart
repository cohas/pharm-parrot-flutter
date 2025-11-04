import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ComPortService extends ChangeNotifier {
  static const platform =
      MethodChannel('com.example.pharm_parrot_flutter/comport');

  String _incomingData = '';
  bool _isConnected = false;
  int _comPortNumber = 4;
  bool _useComPort = false;

  bool get isConnected => _isConnected;
  String get incomingData => _incomingData;
  int get comPortNumber => _comPortNumber;
  bool get useComPort => _useComPort;

  // 바코드 수신 콜백
  Function(String)? _onBarcodeReceived;

  ComPortService({
    bool useComPort = false,
    int comPortNumber = 4,
    Function(String)? onBarcodeReceived,
  }) {
    _useComPort = useComPort;
    _comPortNumber = comPortNumber;
    _onBarcodeReceived = onBarcodeReceived;
  }

  /// COM Port 설정 업데이트
  void updateSettings({
    required bool useComPort,
    required int comPortNumber,
  }) {
    _useComPort = useComPort;
    _comPortNumber = comPortNumber;
    notifyListeners();

    if (useComPort && !_isConnected) {
      connect();
    } else if (!useComPort && _isConnected) {
      disconnect();
    }
  }

  /// 바코드 수신 콜백 설정
  void setOnBarcodeReceived(Function(String) callback) {
    _onBarcodeReceived = callback;
  }

  /// COM Port에 연결
  Future<void> connect() async {
    if (!_useComPort) {
      debugPrint('COM Port 사용 안 함');
      return;
    }

    try {
      final bool result = await platform.invokeMethod('openComPort', {
        'portNumber': _comPortNumber,
        'baudRate': 9600,
      });

      if (result) {
        _isConnected = true;
        debugPrint('COM Port 연결 성공: COM${_comPortNumber}');
        _startListening();
        notifyListeners();
      } else {
        _isConnected = false;
        debugPrint('COM Port 연결 실패');
        notifyListeners();
      }
    } on PlatformException catch (e) {
      debugPrint('COM Port 연결 오류: ${e.message}');
      _isConnected = false;
      notifyListeners();
    }
  }

  /// COM Port에서 데이터 수신 시작
  void _startListening() {
    // 100ms 주기로 포트에서 데이터 읽기
    Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) async {
        if (!_isConnected) {
          timer.cancel();
          return;
        }

        try {
          final String? data =
              await platform.invokeMethod('readComPort') as String?;
          if (data != null && data.isNotEmpty) {
            _handleReceivedData(data);
          }
        } catch (e) {
          debugPrint('포트 읽기 오류: $e');
        }
      },
    );
  }

  /// 수신된 데이터 처리
  void _handleReceivedData(String data) {
    try {
      _incomingData += data;

      // 엔터 또는 CR/LF로 완전한 바코드 판단
      if (_incomingData.contains('\n') || _incomingData.contains('\r')) {
        String barcode = _incomingData
            .replaceAll('\r', '')
            .replaceAll('\n', '')
            .trim();

        if (barcode.isNotEmpty) {
          debugPrint('바코드 수신: $barcode');
          _onBarcodeReceived?.call(barcode);
        }

        _incomingData = '';
      }
    } catch (e) {
      debugPrint('데이터 처리 오류: $e');
    }
  }

  /// COM Port 연결 해제
  Future<void> disconnect() async {
    try {
      await platform.invokeMethod('closeComPort');
      _isConnected = false;
      debugPrint('COM Port 연결 해제');
      notifyListeners();
    } on PlatformException catch (e) {
      debugPrint('COM Port 연결 해제 오류: ${e.message}');
    }
  }

  /// 데이터 전송
  Future<void> sendData(String data) async {
    if (!_isConnected) {
      debugPrint('COM Port 연결 안 됨');
      return;
    }

    try {
      await platform.invokeMethod('writeComPort', {'data': data});
      debugPrint('데이터 전송: $data');
    } on PlatformException catch (e) {
      debugPrint('데이터 전송 오류: ${e.message}');
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

