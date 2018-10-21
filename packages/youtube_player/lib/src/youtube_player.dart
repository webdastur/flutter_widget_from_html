import 'dart:convert';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'video_player.dart';

class YouTubePlayer extends StatefulWidget {
  final double aspectRatio;
  final String videoId;

  YouTubePlayer(
    this.videoId, {
    this.aspectRatio = 16 / 9,
    Key key,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() =>
      _YouTubePlayerState(aspectRatio: aspectRatio);
}

class _YouTubePlayerState extends State<YouTubePlayer> {
  double aspectRatio;
  bool aspectRatioFromStream = false;
  bool hasCompletedFetching = false;
  bool isShowingVideoPlayer = false;
  _Stream stream;
  _Thumbnail thumbnail;

  _YouTubePlayerState({this.aspectRatio});

  Widget get placeholder =>
      const Center(child: const CircularProgressIndicator());

  String get videoUrl => "https://youtu.be/${widget.videoId}";

  Color get youtubeRed => const Color.fromRGBO(204, 24, 30, 1.0);

  @override
  void initState() {
    super.initState();
    fetch();
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          accentColor: youtubeRed,
        ),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: isShowingVideoPlayer
              ? VideoPlayer(
                  stream.url,
                  onDismissed: () =>
                      setState(() => isShowingVideoPlayer = false),
                )
              : !hasCompletedFetching
                  ? placeholder
                  : thumbnail != null ? _buildThumbnail() : null,
        ),
      );

  void fetch() async {
    // we are using an unofficial YouTube api, it may die without notice
    await Future.wait([
      http
          .get('http://www.youtube.com/get_video_info?' +
              "html5=1&video_id=${widget.videoId}")
          .then(_fetchOnGetVideoInfo),
      http.get(videoUrl).then(_fetchOnHtml),
    ]);

    if (mounted) setState(() => hasCompletedFetching = true);
  }

  void _actionLaunchUrl() async {
    if (await canLaunch(videoUrl)) {
      await launch(videoUrl);
    }
  }

  void _actionShowVideoPlayerOrLaunchUrl() async {
    if (stream != null) {
      setState(() => isShowingVideoPlayer = true);
      return;
    }

    _actionLaunchUrl();
  }

  Widget _buildThumbnail() => GestureDetector(
        child: Stack(
          children: <Widget>[
            CachedNetworkImage(
              imageUrl: thumbnail.url,
              fit: BoxFit.cover,
              placeholder: placeholder,
            ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, bc) => Icon(
                      Icons.play_arrow,
                      color: Theme.of(context).accentColor,
                      size: min(bc.maxHeight, bc.maxWidth) / 2,
                    ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: GestureDetector(
                          child: Text(
                            videoUrl,
                            style: DefaultTextStyle.of(context)
                                .style
                                .copyWith(color: youtubeRed),
                          ),
                          onTap: _actionLaunchUrl,
                        ),
                      ),
                      Text(stream?.quality ?? ''),
                    ],
                  )),
            ),
          ],
        ),
        onTap: _actionShowVideoPlayerOrLaunchUrl,
      );

  void _fetchOnGetVideoInfo(http.Response response) {
    if (!mounted) return;

    final params = Uri.splitQueryString(response.body);
    if (params.containsKey('player_response') &&
        _parsePlayerResponse(params['player_response'])) {
      return;
    }

    if (params.containsKey('url_encoded_fmt_stream_map')) {
      _parseStreamMap(params['url_encoded_fmt_stream_map']);
    }
  }

  void _fetchOnHtml(http.Response response) {
    if (!mounted) return;

    final match = RegExp(r'<meta property="og:image" content="([^"]+)">')
        .firstMatch(response.body);
    if (match == null) return;

    _setBestThumbnail(<_Thumbnail>[
      _Thumbnail(
        height: double.infinity,
        url: match.group(1),
        width: double.infinity,
      )
    ]);
  }

  bool _parsePlayerResponse(String playerResponse) {
    final List<_Stream> newStreams = List();
    final List<_Thumbnail> newThumbnails = List();

    final map = json.decode(playerResponse);
    if (map is Map) {
      if (map.containsKey('streamingData')) {
        final streamingData = map['streamingData'] as Map;
        if (streamingData.containsKey('formats')) {
          final formats = streamingData['formats'] as List;
          for (final format in formats) {
            if (format is Map) {
              if (!format.containsKey('height')) continue;
              if (!format.containsKey('mimeType')) continue;
              if (!format.containsKey('qualityLabel')) continue;
              if (!format.containsKey('url')) continue;
              if (!format.containsKey('width')) continue;

              final type = format['mimeType'] as String;
              if (!type.startsWith('video/')) continue;

              newStreams.add(_Stream(
                height: format['height'] as int,
                quality: format['qualityLabel'],
                type: type,
                url: format['url'],
                width: format['width'] as int,
              ));
            }
          }
        }
      }

      // TODO: use higher quality thumbnail
      // may need api key to use YouTube Data API v3
      if (map.containsKey('videoDetails')) {
        final videoDetails = map['videoDetails'] as Map;
        if (videoDetails.containsKey('thumbnail')) {
          final videoDetailsThumbnail = videoDetails['thumbnail'] as Map;
          if (videoDetailsThumbnail.containsKey('thumbnails')) {
            final thumbnails = videoDetailsThumbnail['thumbnails'] as List;
            for (final thumbnail in thumbnails) {
              if (thumbnail is Map) {
                if (!thumbnail.containsKey('height')) continue;
                if (!thumbnail.containsKey('url')) continue;
                if (!thumbnail.containsKey('width')) continue;

                newThumbnails.add(_Thumbnail(
                  height: (thumbnail['height'] as int).toDouble(),
                  url: thumbnail['url'],
                  width: (thumbnail['width'] as int).toDouble(),
                ));
              }
            }
          }
        }
      }
    }

    setState(() {
      _setBestStream(newStreams);
      _setBestThumbnail(newThumbnails);
    });

    return newStreams.isNotEmpty;
  }

  void _parseStreamMap(String urlEncodedFmtStreamMap) {
    final List<_Stream> list = List();
    final values = urlEncodedFmtStreamMap.split(',');
    for (final value in values) {
      final params = Uri.splitQueryString(value);
      if (!params.containsKey('quality') ||
          !params.containsKey('type') ||
          !params.containsKey('url')) {
        continue;
      }

      final streamType = params['type'];
      if (!streamType.startsWith('video/mp4')) {
        continue;
      }

      list.add(_Stream(
        quality: params['quality'],
        type: params['type'],
        url: params['url'],
      ));
    }

    setState(() => _setBestStream(list));
  }

  void _setBestStream(List<_Stream> list) {
    for (final _stream in list) {
      print("Stream: ${_stream.type} ${_stream.quality}");

      if (stream == null || stream.width < _stream.width) {
        stream = _stream;

        if (_stream.width > 0 && _stream.height > 0) {
          aspectRatio = _stream.width / _stream.height;
          aspectRatioFromStream = true;
        }
      }
    }
  }

  void _setBestThumbnail(List<_Thumbnail> list) {
    for (final _thumbnail in list) {
      print("Thumbnail: ${_thumbnail.width}x${_thumbnail.height}");

      if (thumbnail == null || thumbnail.width < _thumbnail.width) {
        thumbnail = _thumbnail;
      }

      if (!aspectRatioFromStream &&
          _thumbnail.width > 0 &&
          _thumbnail.height > 0) {
        aspectRatio = _thumbnail.width / _thumbnail.height;
      }
    }
  }
}

class _Stream {
  final int height;
  final String quality;
  final String type;
  final String url;
  final int width;

  _Stream({this.height = 0, this.quality, this.type, this.url, this.width = 0});
}

class _Thumbnail {
  final double height;
  final String url;
  final double width;

  _Thumbnail({this.height, this.url, this.width});
}
