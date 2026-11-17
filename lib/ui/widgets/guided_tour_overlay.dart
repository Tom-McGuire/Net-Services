import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Describes a single spotlight step in a [GuidedTourOverlay] walkthrough.
class GuidedTourStep {
  /// Key of the widget to highlight with the spotlight cutout.
  final GlobalKey targetKey;

  /// Short heading displayed at the top of the walkthrough tooltip card.
  final String title;

  /// Explanatory body copy displayed inside the walkthrough tooltip card.
  final String description;

  /// Optional callback invoked before measuring [targetKey] on step entry.
  final FutureOr<void> Function()? onStepEnter;

  const GuidedTourStep({
    required this.targetKey,
    required this.title,
    required this.description,
    this.onStepEnter,
  });
}

/// Interactive spotlight walkthrough overlay that dims the surrounding UI,
/// highlights each [GuidedTourStep.targetKey], and displays step navigation.
class GuidedTourOverlay extends StatefulWidget {
  /// Ordered list of walkthrough steps to present while [isActive] is true.
  final List<GuidedTourStep> steps;

  /// Callback invoked when the tour is completed, skipped, or dismissed.
  final VoidCallback onFinish;

  /// Underlying application UI wrapped by the spotlight overlay.
  final Widget child;

  /// Whether the guided tour overlay is currently visible.
  final bool isActive;

  /// Optional key for an exit control (such as a top-bar Exit Demo button)
  /// that remains clickable while the dimmed overlay is active.
  final GlobalKey? exitTargetKey;

  const GuidedTourOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
    required this.child,
    required this.isActive,
    this.exitTargetKey,
  });

  @override
  State<GuidedTourOverlay> createState() => _GuidedTourOverlayState();
}

class _GuidedTourOverlayState extends State<GuidedTourOverlay> {
  int _currentIndex = 0;
  Rect? _targetRect;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _activateStep(0);
    }
  }

  @override
  void didUpdateWidget(covariant GuidedTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _activateStep(0);
    } else if (!widget.isActive && oldWidget.isActive) {
      _targetRect = null;
      _currentIndex = 0;
    } else if (widget.isActive &&
        widget.steps.isNotEmpty &&
        _currentIndex >= widget.steps.length) {
      _activateStep(widget.steps.length - 1);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _activateStep(int index) async {
    if (index < 0 || index >= widget.steps.length) return;
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }

    final step = widget.steps[index];
    if (step.onStepEnter != null) {
      final result = step.onStepEnter!();
      if (result is Future) {
        await result;
      }
    }

    if (!mounted || !widget.isActive) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Skip measurement if the widget unmounted or moved to a newer step.
      if (!mounted || !widget.isActive || _currentIndex != index) return;
      _measureTarget();
      _focusNode.requestFocus();
    });
  }

  void _measureTarget() {
    if (_currentIndex < 0 || _currentIndex >= widget.steps.length) {
      setState(() => _targetRect = null);
      return;
    }
    final step = widget.steps[_currentIndex];
    final targetContext = step.targetKey.currentContext;
    if (targetContext == null) {
      setState(() => _targetRect = null);
      return;
    }
    final renderBox = targetContext.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null ||
        !renderBox.hasSize ||
        !renderBox.attached ||
        overlayBox == null ||
        !overlayBox.attached) {
      setState(() => _targetRect = null);
      return;
    }
    final topLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    setState(() {
      _targetRect = (topLeft & renderBox.size).inflate(6);
    });
  }

  void _nextStep() {
    if (_currentIndex + 1 < widget.steps.length) {
      _activateStep(_currentIndex + 1);
    } else {
      widget.onFinish();
    }
  }

  void _prevStep() {
    if (_currentIndex > 0) {
      _activateStep(_currentIndex - 1);
    }
  }

  void _handleOverlayTapUp(TapUpDetails details) {
    final exitContext = widget.exitTargetKey?.currentContext;
    if (exitContext == null) return;
    final box = exitContext.findRenderObject() as RenderBox?;
    if (box != null && box.attached && box.hasSize) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(details.globalPosition)) {
        widget.onFinish();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive || widget.steps.isEmpty) {
      return widget.child;
    }

    final safeIndex = _currentIndex.clamp(0, widget.steps.length - 1);

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onFinish();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _nextStep();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _prevStep();
          }
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
          final step = widget.steps[safeIndex];
          final isLast = safeIndex == widget.steps.length - 1;

          return Stack(
            children: [
              widget.child,
              // Dimmed Spotlight Cutout Layer
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {}, // Block stray clicks outside controls
                  onTapUp: _handleOverlayTapUp,
                  child: CustomPaint(
                    painter: _SpotlightPainter(
                      targetRect: _targetRect,
                      isDark: AppTheme.isDark,
                      accentColor: AppTheme.accent,
                      borderColor: AppTheme.isDark
                          ? const Color(0xFF38BDF8)
                          : AppTheme.accent,
                    ),
                  ),
                ),
              ),
              // Floating Tooltip Card
              _buildTooltipCard(screenSize, step, safeIndex, isLast),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTooltipCard(
    Size screenSize,
    GuidedTourStep step,
    int stepIndex,
    bool isLast,
  ) {
    const double margin = 16.0;
    final double cardWidth = math.min(
      420.0,
      math.max(240.0, screenSize.width - margin * 2),
    );
    const double estimatedCardHeight = 250.0;

    double left = (screenSize.width - cardWidth) / 2;
    double top = (screenSize.height - estimatedCardHeight) / 2;

    if (_targetRect != null) {
      final rect = _targetRect!;
      // Horizontal alignment clamped inside viewport
      left = rect.left.clamp(
        margin,
        math.max(margin, screenSize.width - cardWidth - margin),
      );

      // Prefer placing below target; if insufficient room, place above or inside
      final spaceBelow = screenSize.height - rect.bottom;
      final spaceAbove = rect.top;

      if (spaceBelow >= estimatedCardHeight + margin) {
        top = rect.bottom + 12;
      } else if (spaceAbove >= estimatedCardHeight + margin) {
        top = rect.top - estimatedCardHeight - 12;
      } else {
        // Target is a large full-height panel: place card inside top-right or center
        top = math.max(margin + 60, rect.top + 24);
        left = math
            .min(
              rect.right - cardWidth - 24,
              screenSize.width - cardWidth - margin,
            )
            .clamp(
              margin,
              math.max(margin, screenSize.width - cardWidth - margin),
            );
      }
    }

    // Clamp inside viewport so the tooltip card never overflows offscreen.
    left = left.clamp(
      margin,
      math.max(margin, screenSize.width - cardWidth - margin),
    );
    top = top.clamp(
      margin,
      math.max(margin, screenSize.height - estimatedCardHeight - margin),
    );

    return Positioned(
      left: left,
      top: top,
      width: cardWidth,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.accent, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.isDark
                    ? Colors.black87
                    : Colors.black.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(
                          alpha: AppTheme.isDark ? 0.2 : 0.12,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        'DEMO WALKTHROUGH • STEP ${stepIndex + 1} OF ${widget.steps.length}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: widget.onFinish,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                step.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                step.description,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: widget.onFinish,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.warning,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'End Demo',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (stepIndex > 0) ...[
                        OutlinedButton(
                          onPressed: _prevStep,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: BorderSide(color: AppTheme.inputBorder),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Back',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      FilledButton.icon(
                        onPressed: _nextStep,
                        style: FilledButton.styleFrom(
                          backgroundColor: isLast
                              ? AppTheme.success
                              : AppTheme.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          isLast
                              ? Icons.check_circle_outline
                              : Icons.arrow_forward,
                          size: 14,
                        ),
                        label: Text(
                          isLast ? 'Finish & Clear' : 'Next',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final bool isDark;
  final Color accentColor;
  final Color borderColor;

  _SpotlightPainter({
    required this.targetRect,
    required this.isDark,
    required this.accentColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullPath = Path()..addRect(Offset.zero & size);
    final dimPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.72 : 0.52)
      ..style = PaintingStyle.fill;

    if (targetRect == null) {
      canvas.drawPath(fullPath, dimPaint);
      return;
    }

    final rrect = RRect.fromRectAndRadius(
      targetRect!,
      const Radius.circular(8),
    );
    final cutoutPath = Path()..addRRect(rrect);
    final combinedPath = Path.combine(
      PathOperation.difference,
      fullPath,
      cutoutPath,
    );

    canvas.drawPath(combinedPath, dimPaint);

    // Draw glowing accent border around the spotlight cutout
    final glowPaint = Paint()
      ..color = accentColor.withValues(alpha: isDark ? 0.45 : 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(rrect, glowPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect ||
      oldDelegate.isDark != isDark ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.borderColor != borderColor;
}
