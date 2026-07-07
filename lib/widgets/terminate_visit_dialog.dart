import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

class TerminateVisitResult {
  final Map<String, dynamic> body;
  TerminateVisitResult(this.body);
}

class TerminateVisitDialog extends StatefulWidget {
  final String visitorName;
  const TerminateVisitDialog({super.key, required this.visitorName});

  @override
  State<TerminateVisitDialog> createState() => _TerminateVisitDialogState();

  static Future<TerminateVisitResult?> show(BuildContext context, String visitorName) {
    return showDialog<TerminateVisitResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TerminateVisitDialog(visitorName: visitorName),
    );
  }
}

class _TerminateVisitDialogState extends State<TerminateVisitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _observationsCtrl = TextEditingController();
  final _incidentDescCtrl = TextEditingController();
  bool _hasIncident = false;
  String _incidentGravite = 'MOYENNE';

  late final SignatureController _signatureController;

  final _gravites = ['FAIBLE', 'MOYENNE', 'HAUTE', 'CRITIQUE'];

  @override
  void initState() {
    super.initState();
    _signatureController = SignatureController(
      penStrokeWidth: 2.5,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _observationsCtrl.dispose();
    _incidentDescCtrl.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  bool get _hasSignature => _signatureController.value.isNotEmpty;

  void _clearSignature() {
    _signatureController.clear();
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final dateDepart = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final heureDepart = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final body = <String, dynamic>{
      'date_depart': dateDepart,
      'heure_depart': heureDepart,
      'observations': _observationsCtrl.text.trim(),
    };

    if (_hasSignature) {
      final pngBytes = await _signatureController.toPngBytes();
      if (pngBytes != null) {
        body['signature_sortie'] = 'data:image/png;base64,${base64Encode(pngBytes)}';
      }
    }

    if (_hasIncident) {
      body['incident'] = true;
      body['incident_gravite'] = _incidentGravite;
      body['incident_description'] = _incidentDescCtrl.text.trim();
    }

    if (!mounted) return;
    Navigator.pop(context, TerminateVisitResult(body));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.check_circle, color: Colors.green, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Clôturer la visite',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(widget.visitorName,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Text('Observations', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _observationsCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Notes optionnelles...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Icon(Icons.draw, size: 18, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text('Signature de sortie', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    const Spacer(),
                    if (_hasSignature)
                      TextButton.icon(
                        onPressed: _clearSignature,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Effacer', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(foregroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _hasSignature
                          ? Colors.green.withValues(alpha: 0.4)
                          : Colors.grey.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Signature(
                      controller: _signatureController,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                if (!_hasSignature)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Signez dans le cadre ci-dessus',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Switch(
                      value: _hasIncident,
                      onChanged: (v) => setState(() => _hasIncident = v),
                      activeThumbColor: Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text('Déclarer un incident', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  ],
                ),

                if (_hasIncident) ...[
                  const SizedBox(height: 8),
                  Text('Gravité', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: _gravites.map((g) {
                      final selected = _incidentGravite == g;
                      final color = _graviteColor(g);
                      return ChoiceChip(
                        label: Text(g, style: TextStyle(
                            fontSize: 12,
                            color: selected ? Colors.white : color,
                            fontWeight: FontWeight.w600)),
                        selected: selected,
                        selectedColor: color,
                        backgroundColor: color.withValues(alpha: 0.08),
                        side: BorderSide(color: color.withValues(alpha: 0.3)),
                        onSelected: (_) => setState(() => _incidentGravite = g),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _incidentDescCtrl,
                    maxLines: 2,
                    validator: _hasIncident
                        ? (v) => (v == null || v.trim().isEmpty) ? 'Description requise' : null
                        : null,
                    decoration: InputDecoration(
                      hintText: 'Description de l\'incident...',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Clôturer', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _graviteColor(String gravite) {
    switch (gravite) {
      case 'FAIBLE':
        return Colors.blue;
      case 'MOYENNE':
        return Colors.orange;
      case 'HAUTE':
        return Colors.deepOrange;
      case 'CRITIQUE':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
