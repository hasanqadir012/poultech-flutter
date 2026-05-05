import 'package:flutter/material.dart';
import '../models/batch_model.dart';
import '../services/batch_service.dart';

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  final BatchService _batchService = BatchService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();

  BatchModel? _activeBatch;
  List<BatchModel> _batches = [];
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _batchService.getActiveBatch(),
      _batchService.getAllBatches(),
    ]);
    if (mounted) {
      setState(() {
        _activeBatch = results[0] as BatchModel?;
        _batches = results[1] as List<BatchModel>;
        _isLoading = false;
      });
    }
  }

  Future<void> _createBatch() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    final result = await _batchService.createBatch(
      _nameController.text.trim(),
      _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isCreating = false);

    if (result.isSuccess) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Failed to create batch.'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Batch Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: const Color(0xFF3B82F6),
              backgroundColor: const Color(0xFF1E293B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Create New Batch (only when no active batch)
                    if (_activeBatch == null) ...[
                      _buildCreateSection(),
                      const SizedBox(height: 28),
                    ],

                    // Section 2: Batch History (always shown)
                    _buildHistorySection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCreateSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.egg_outlined, color: Color(0xFF3B82F6), size: 22),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No Active Batch',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Create a batch to start tracking',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Form(
            key: _formKey,
            child: Column(
              children: [
                _buildTextField(
                  controller: _nameController,
                  label: 'Batch Name',
                  hint: 'e.g. Morning Run, Incubator A',
                  maxLength: 40,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Batch name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _notesController,
                  label: 'Notes (optional)',
                  hint: 'Any notes about this batch...',
                  maxLength: 200,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isCreating ? null : _createBatch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF3B82F6).withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isCreating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Create Batch',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required int maxLength,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        hintStyle: const TextStyle(color: Color(0xFF64748B)),
        counterStyle: const TextStyle(color: Color(0xFF64748B)),
        filled: true,
        fillColor: const Color(0xFF0F172A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
        ),
        errorStyle: const TextStyle(color: Color(0xFFEF4444)),
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BATCH HISTORY',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        if (_batches.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No batches yet',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 15,
                ),
              ),
            ),
          )
        else
          ...(_batches.map(_buildBatchCard)),
      ],
    );
  }

  Widget _buildBatchCard(BatchModel batch) {
    final isActive = batch.isActive;

    final cardContent = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                batch.name,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withOpacity(0.65),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${batch.formattedDate} · ${batch.totalDetections} '
                'detection${batch.totalDetections == 1 ? '' : 's'}',
                style:
                    const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              if (batch.notes != null && batch.notes!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  batch.notes!,
                  style: const TextStyle(
                      color: Color(0xFF64748B), fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF22C55E).withOpacity(0.12)
                : const Color(0xFF64748B).withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF22C55E).withOpacity(0.3)
                  : const Color(0xFF64748B).withOpacity(0.3),
            ),
          ),
          child: Text(
            isActive ? 'Active' : 'Closed',
            style: TextStyle(
              color: isActive
                  ? const Color(0xFF22C55E)
                  : const Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    if (isActive) {
      // Stack-based left accent: Flutter forbids non-uniform Border + borderRadius
      return Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: cardContent,
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 10, // matches margin bottom
            child: Container(
              width: 4,
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: cardContent,
    );
  }
}
