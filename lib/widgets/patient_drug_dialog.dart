import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

num asNum(dynamic v, [num def = 0]) {
  if (v == null) return def;
  if (v is num) return v;
  if (v is String) {
    return num.tryParse(v.trim()) ?? def;
  }
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

class PatientDrugDialog extends StatefulWidget {
  final SupabaseService supabase;
  final String patientId;
  final Map<String, dynamic> row;
  const PatientDrugDialog({super.key, required this.supabase, required this.patientId, required this.row});

  @override
  State<PatientDrugDialog> createState() => _PatientDrugDialogState();
}

class _PatientDrugDialogState extends State<PatientDrugDialog> {
  late TextEditingController morning;
  late TextEditingController afternoon;
  late TextEditingController evening;
  late TextEditingController night;
  late TextEditingController special;
  late TextEditingController usageCode;
  late TextEditingController seperate;
  late TextEditingController memo;
  late TextEditingController location;
  bool isAtc = false;
  bool use = true;
  int? patientDrugId;

  @override
  void initState() {
    super.initState();
    morning = TextEditingController(text: asNum(widget.row['morning']).toString());
    afternoon = TextEditingController(text: asNum(widget.row['afternoon']).toString());
    evening = TextEditingController(text: asNum(widget.row['evening']).toString());
    night = TextEditingController(text: asNum(widget.row['night']).toString());
    special = TextEditingController(text: asNum(widget.row['special']).toString());
    usageCode = TextEditingController(text: asNum(widget.row['usage_code'], 1).toInt().toString());
    seperate = TextEditingController(text: asNum(widget.row['seperate'], 1).toInt().toString());
    memo = TextEditingController(text: (widget.row['patientdrugmemo'] ?? '').toString());
    location = TextEditingController(text: (widget.row['location'] ?? '').toString());
    isAtc = asBool(widget.row['is_atc'], false);
    use = asBool(widget.row['use'], true);
    final idVal = widget.row['patientdrug_id']?.toString();
    if (idVal != null) patientDrugId = int.tryParse(idVal);
  }

  @override
  void dispose() {
    morning.dispose(); afternoon.dispose(); evening.dispose(); night.dispose();
    special.dispose(); usageCode.dispose(); seperate.dispose(); memo.dispose(); location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final packBarcode = (widget.row['pack_barcode'] ?? '').toString();
      if (patientDrugId != null) {
        await widget.supabase.rpc('update_patientdrug_by_id', {
          '_patientdrug_id': patientDrugId,
          '_morning': double.tryParse(morning.text) ?? 0,
          '_afternoon': double.tryParse(afternoon.text) ?? 0,
          '_evening': double.tryParse(evening.text) ?? 0,
          '_night': double.tryParse(night.text) ?? 0,
          '_special': double.tryParse(special.text) ?? 0,
          '_usage_code': int.tryParse(usageCode.text) ?? 1,
          '_seperate': int.tryParse(seperate.text) ?? 1,
          '_use': use,
          '_patientdrugmemo': memo.text,
        });
      } else {
        final prodResp = await widget.supabase.rpc('get_product_id_by_pack_barcode', {
          '_pack_barcode': packBarcode,
        });
        final prodId = (prodResp?.toString() ?? '').replaceAll('"', '');
        if (prodId.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('제품 ID 를 찾지 못했습니다.')));
          }
          return;
        }
        final ins = await widget.supabase.rpc('insert_patientdrug', {
          '_patient_id': widget.patientId,
          '_product_id': prodId,
          '_morning': double.tryParse(morning.text) ?? 0,
          '_afternoon': double.tryParse(afternoon.text) ?? 0,
          '_evening': double.tryParse(evening.text) ?? 0,
          '_night': double.tryParse(night.text) ?? 0,
          '_special': double.tryParse(special.text) ?? 0,
          '_usage_code': int.tryParse(usageCode.text) ?? 1,
          '_seperate': int.tryParse(seperate.text) ?? 1,
          '_use': use,
          '_patientdrugmemo': memo.text,
        });
        final newId = int.tryParse(ins?.toString().trim() ?? '');
        if (newId != null) patientDrugId = newId;
      }

      // is_atc 변경
      final packBarcode2 = (widget.row['pack_barcode'] ?? '').toString();
      await widget.supabase.rpc('update_product_is_atc', {
        '_pack_barcode': packBarcode2,
        '_is_atc': isAtc,
      });

      // location 변경
      await widget.supabase.rpc('update_product_location_by_pack_barcode', {
        '_pack_barcode': packBarcode2,
        '_location': location.text,
      });

      // 반영된 row 반환
      final updated = Map<String, dynamic>.from(widget.row);
      updated['morning'] = double.tryParse(morning.text) ?? 0;
      updated['afternoon'] = double.tryParse(afternoon.text) ?? 0;
      updated['evening'] = double.tryParse(evening.text) ?? 0;
      updated['night'] = double.tryParse(night.text) ?? 0;
      updated['special'] = double.tryParse(special.text) ?? 0;
      updated['usage_code'] = int.tryParse(usageCode.text) ?? 1;
      updated['seperate'] = int.tryParse(seperate.text) ?? 1;
      updated['use'] = use;
      updated['patientdrugmemo'] = memo.text;
      updated['is_atc'] = isAtc;
      updated['location'] = location.text;
      if (patientDrugId != null) updated['patientdrug_id'] = patientDrugId;

      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = (widget.row['pack_barcode'] ?? '').toString();
    final drugName = (widget.row['substring'] ?? widget.row['product_name'] ?? widget.row['drug_name'] ?? '').toString();

    return AlertDialog(
      title: Text(drugName.isEmpty ? code : drugName),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [const Text('ATC'), const SizedBox(width: 8), Switch(value: isAtc, onChanged: (v) => setState(() => isAtc = v))]),
            const SizedBox(height: 8),
            _numField('아침', morning),
            _numField('점심', afternoon),
            _numField('저녁', evening),
            _numField('취침', night),
            _numField('특수', special),
            _intField('Usage Code', usageCode),
            _intField('분할', seperate),
            Row(children: [const Text('사용'), const SizedBox(width: 8), Switch(value: use, onChanged: (v) => setState(() => use = v))]),
            const SizedBox(height: 8),
            TextField(controller: location, decoration: const InputDecoration(labelText: '위치', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: memo, decoration: const InputDecoration(labelText: '메모', border: OutlineInputBorder()), maxLines: 3),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
        FilledButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }

  Widget _numField(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Widget _intField(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}

