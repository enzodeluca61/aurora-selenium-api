import 'package:flutter/material.dart';
import '../models/attendance_model.dart';

class AttendanceStatusSelector extends StatelessWidget {
  final AttendanceStatus? selectedStatus;
  final Function(AttendanceStatus) onStatusChanged;

  const AttendanceStatusSelector({
    super.key,
    this.selectedStatus,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AttendanceStatus.values.map((status) {
        final isSelected = selectedStatus == status;
        final statusColor = _getStatusColor(status);
        
        return GestureDetector(
          onTap: () => onStatusChanged(status),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? statusColor : statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: statusColor,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  status.code,
                  style: TextStyle(
                    color: isSelected ? Colors.white : statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status.label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : statusColor,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Color _getStatusColor(AttendanceStatus status) {
    switch (status.color) {
      case 'green':
        return Colors.green;
      case 'orange':
        return Colors.orange;
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'purple':
        return Colors.purple;
      case 'grey':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }
}