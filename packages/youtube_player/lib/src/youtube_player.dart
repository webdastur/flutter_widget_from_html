import 'dart:convert';
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
  bool hasCompletedFetching = false;
  bool isShowingVideoPlayer = false;
  _Stream stream;
  _Thumbnail thumbnail;

  _YouTubePlayerState({this.aspectRatio});

  @override
  void initState() {
    super.initState();
    fetch();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: aspectRatio,
        child: isShowingVideoPlayer
            ? VideoPlayer(stream.url)
            : !hasCompletedFetching
                ? const Center(child: const CircularProgressIndicator())
                : thumbnail != null
                    ? GestureDetector(
                        child: CachedNetworkImage(
                          imageUrl: thumbnail.url,
                          fit: BoxFit.cover,
                          placeholder:
                              Center(child: CircularProgressIndicator()),
                        ),
                        onTap: _showVideoPlayerOrLaunchUrl,
                      )
                    : Container(height: 0.0, width: 0.0),
      );

  void fetch() async {
    // this is an unofficial YouTube api, it may die without notice
    final url =
        "http://www.youtube.com/get_video_info?html5=1&video_id=${widget.videoId}";
    final response = await http.get(url);
    if (response.statusCode != 200) {
      setState(() => hasCompletedFetching = true);
      return;
    }

    final params = Uri.splitQueryString(response.body);
    final parsedPlayerResponse = params.containsKey('player_response') &&
        _parsePlayerResponse(params['player_response']);

    if (!parsedPlayerResponse &&
        params.containsKey('url_encoded_fmt_stream_map')) {
      _parseStreamMap(params['url_encoded_fmt_stream_map']);
    }

    setState(() => hasCompletedFetching = true);
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
                  height: thumbnail['height'] as int,
                  url: thumbnail['url'],
                  width: thumbnail['width'] as int,
                ));
              }
            }
          }
        }
      }
    }

    setState(() {
      _setBestStream(newStreams);

      for (final newThumbnail in newThumbnails) {
        if (thumbnail == null || thumbnail.width < newThumbnail.width) {
          thumbnail = newThumbnail;
          aspectRatio = thumbnail.width / thumbnail.height;
        }
      }
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
      if (!streamType.startsWith('video/')) {
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
      if (stream == null || stream.width < _stream.width) {
        stream = _stream;
      }
    }
  }

  void _showVideoPlayerOrLaunchUrl() async {
    if (stream != null) {
      setState(() => isShowingVideoPlayer = true);
      return;
    }

    final videoUrl = "https://youtu.be/${widget.videoId}";
    if (await canLaunch(videoUrl)) {
      await launch(videoUrl);
    }
  }
}

class _Stream {
  final int height;
  final String quality;
  final String type;
  final String url;
  final int width;

  _Stream({this.height, this.quality, this.type, this.url, this.width});
}

class _Thumbnail {
  final int height;
  final String url;
  final int width;

  _Thumbnail({this.height, this.url, this.width});
}
