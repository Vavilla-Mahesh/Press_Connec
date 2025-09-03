import 'package:flutter/material.dart';
import '../../services/theme_service.dart';

class AnimatedGradientBackground extends StatefulWidget {
  final Widget child;
  
  const AnimatedGradientBackground({
    super.key,
    required this.child,
  });

  @override
  State<AnimatedGradientBackground> createState() => _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF1A1A2E),
                      const Color(0xFF16213E),
                      const Color(0xFF0F3460),
                    ]
                  : [
                      const Color(0xFFE3F2FD),
                      const Color(0xFFBBDEFB),
                      const Color(0xFF90CAF9),
                    ],
              stops: [
                0.0,
                0.5 + (_animation.value * 0.3),
                1.0,
              ],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}