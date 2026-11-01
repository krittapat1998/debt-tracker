import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';

final _decimalInput = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.required = false,
    this.allowZero = true,
    this.suffix = 'บาท',
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool required;
  final bool allowZero;
  final String suffix;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_decimalInput],
      decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3, suffixText: suffix),
      onChanged: onChanged,
      validator: (v) {
        final value = parseAmount(v);
        if (v == null || v.trim().isEmpty) return required ? 'กรุณากรอก' : null;
        if (value == null) return 'ตัวเลขไม่ถูกต้อง';
        if (value < 0) return 'ต้องไม่ติดลบ';
        if (!allowZero && value == 0) return 'ต้องมากกว่า 0';
        return null;
      },
    );
  }
}

class IntField extends StatelessWidget {
  const IntField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.min = 0,
    this.max = 1200,
    this.suffix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final int min;
  final int max;
  final String? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3, suffixText: suffix),
      onChanged: onChanged,
      validator: (v) {
        final n = int.tryParse(v ?? '');
        if (n == null) return 'กรุณากรอกตัวเลข';
        if (n < min || n > max) return 'ต้องอยู่ระหว่าง $min–$max';
        return null;
      },
    );
  }
}

class DayOfMonthField extends StatelessWidget {
  const DayOfMonthField({super.key, required this.value, required this.label, required this.onChanged, this.helper});
  final int? value;
  final String label;
  final String? helper;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, helperText: helper),
      items: [
        const DropdownMenuItem(value: null, child: Text('ไม่ระบุ')),
        for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('วันที่ $d')),
      ],
      onChanged: onChanged,
    );
  }
}

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.clearable = false,
    this.helper,
    this.firstDate,
  });

  final DateTime? value;
  final String label;
  final String? helper;
  final bool clearable;

  /// Earliest date the picker offers; defaults to 15 years back.
  final DateTime? firstDate;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: firstDate ?? DateTime(now.year - 15),
          lastDate: DateTime(now.year + 15),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          suffixIcon: clearable && value != null
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () => onChanged(null))
              : const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(value == null ? 'ไม่ระบุ' : fmtDate(value!)),
      ),
    );
  }
}

/// Vertical spacing between form fields.
const formGap = SizedBox(height: 14);
