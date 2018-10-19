import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart' as lib;

class VideoPlayer extends StatefulWidget {
  final String url;

  VideoPlayer(this.url);

  @override
  State<StatefulWidget> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  lib.VideoPlayerController controller;
  _IconAnimation iconAnimation = _IconAnimation(Icons.play_arrow);
  VoidCallback listener;

  @override
  void initState() {
    super.initState();

    listener = () {
      setState(() {});
    };

    controller = lib.VideoPlayerController.network(widget.url);
    controller.addListener(listener);
    controller.initialize();
    controller.setVolume(1.0);
    controller.play();
  }

  @override
  void deactivate() {
    controller.setVolume(0.0);
    controller.removeListener(listener);
    super.deactivate();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          GestureDetector(
            child: lib.VideoPlayer(controller),
            onTap: _playOrPause,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: lib.VideoProgressIndicator(
              controller,
              allowScrubbing: true,
            ),
          ),
          Center(child: iconAnimation),
          Center(
              child: controller.value.isBuffering
                  ? const CircularProgressIndicator()
                  : null),
        ],
      );

  void _playOrPause() {
    if (!controller.value.initialized) return;

    if (controller.value.isPlaying) {
      iconAnimation = _IconAnimation(Icons.pause);
      controller.pause();
    } else {
      iconAnimation = _IconAnimation(Icons.play_arrow);
      controller.play();
    }
  }
}

class _IconAnimation extends StatefulWidget {
  final Duration duration;
  final IconData icon;

  _IconAnimation(
    this.icon, {
    this.duration = const Duration(milliseconds: 500),
  });

  @override
  State<StatefulWidget> createState() => _IconAnimationState();
}

class _IconAnimationState extends State<_IconAnimation>
    with SingleTickerProviderStateMixin {
  AnimationController animationController;

  @override
  void initState() {
    super.initState();

    animationController = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    animationController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    animationController.forward(from: 0.0);
  }

  @override
  void deactivate() {
    animationController.stop();
    super.deactivate();
  }

  @override
  void didUpdateWidget(_IconAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.icon != widget.icon) {
      animationController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => animationController.isAnimating
      ? Opacity(
          opacity: 1.0 - animationController.value,
          child: Icon(widget.icon, size: 100.0),
        )
      : Container();
}
