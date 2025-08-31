import 'package:flutter/material.dart';

class AnimatedButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Gradient? gradient;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double elevation;

  const AnimatedButton({
    super.key,
    this.onPressed,
    required this.child,
    this.gradient,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    this.elevation = 8.0,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _rippleController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    
    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeInOut,
    ));
    
    _rippleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _rippleController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        if (widget.onPressed != null) {
          _scaleController.forward();
          _rippleController.forward();
        }
      },
      onTapUp: (_) {
        if (widget.onPressed != null) {
          _scaleController.reverse();
          widget.onPressed!();
        }
      },
      onTapCancel: () {
        if (widget.onPressed != null) {
          _scaleController.reverse();
        }
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_scaleAnimation, _rippleAnimation]),
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: widget.gradient ?? LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(widget.borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: (widget.gradient?.colors.first ?? Theme.of(context).primaryColor)
                        .withOpacity(0.3),
                    blurRadius: widget.elevation,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Button content
                  Container(
                    padding: widget.padding,
                    child: Center(child: widget.child),
                  ),
                  
                  // Ripple effect
                  if (_rippleAnimation.value > 0)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(widget.borderRadius),
                        ),
                        child: CustomPaint(
                          painter: RipplePainter(
                            animationValue: _rippleAnimation.value,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class RipplePainter extends CustomPainter {
  final double animationValue;
  final Color color;

  RipplePainter({
    required this.animationValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width * animationValue) / 2;
    
    final paint = Paint()
      ..color = color.withOpacity(1 - animationValue)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}